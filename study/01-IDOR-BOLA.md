# Lesson 01 — IDOR / BOLA (Broken Object Level Authorization)

> **Source material:** real HackerOne disclosures + field analysis of 250 disclosed IDOR reports
> (`thebughunter.blog/case-studies/idor-analysis`, HackerOne reports [#3382343](https://hackerone.com/reports/3382343), [#743953](https://hackerone.com/reports/743953), [#1819832](https://hackerone.com/reports/1819832),
> [#3154983](https://hackerone.com/reports/3154983), [#2374730](https://hackerone.com/reports/2374730), [#1626508](https://hackerone.com/reports/1626508), [#2122671](https://hackerone.com/reports/2122671), [#415081](https://hackerone.com/reports/415081), [#2207248](https://hackerone.com/reports/2207248), [#1658418](https://hackerone.com/reports/1658418))
> **Format:** writeup → mechanism → raw traffic → bypasses → escalation → practice
> **Status:** Lesson 1 of the study track
> **Category:** 1. Access Control — see [CURRICULUM](CURRICULUM.md#1-access-control)

---

## 1. The one-line definition

**IDOR/BOLA = the API checks *who you are* but never checks *whether you own that object*.**

OWASP ranks this #1 in the API Security Top 10 (API1). It is the single most-paid web bug
class that requires **zero tooling** — only a second account and the discipline to change
one number.

---

## 2. Real money from real IDOR reports

Reality check from 250 real disclosures:

| Metric | Value |
|---|---|
| Reports with no bounty (responsible disclosure) | **82%** |
| High/Critical severity share | **36.4%** |
| Avg bounty — Critical | **$14,333** |
| Avg bounty — High | **$5,870** |
| Avg bounty — Medium | **$1,090** |
| Highest single disclosed | **$20,000** |
| Rising sub-class | GraphQL IDOR, **+140%** (2020–22 → 2023–25) |

**The lesson that matters:** all top-bounty reports demonstrated **write/delete**, not read.
Reading profile #2 pays ~$1k. Deleting anyone's account pays $6k–$20k.

---

## 3. The canonical pattern — raw traffic

The whole vulnerability in six lines:

```http
# ── Your own request (account A) ──
GET /api/users/1234/profile HTTP/1.1
Host: target.com
Authorization: Bearer <TOKEN_A>

# ── The test (change ONE character) ──
GET /api/users/1235/profile HTTP/1.1
Host: target.com
Authorization: Bearer <TOKEN_A>          ← still YOUR token
```

If the body comes back as **account B's** profile → IDOR confirmed.
Note what did *not* change: the token. The server authenticated you correctly. It just never
asked *"is user 1235 yours?"* That missing question is the entire bug.

---

## 4. Real writeups, dissected

### 3.1 Nextcloud OOO / BOLA — HackerOne [#3382343](https://hackerone.com/reports/3382343) (Dec 2025)

**Endpoint:** `/ocs/v2.php/apps/dav/api/v1/outOfOffice/{userId}`

The path parameter `{userId}` was used directly to look up the record. Auth was present,
ownership check was absent.

```http
GET /ocs/v2.php/apps/dav/api/v1/outOfOffice/victim_uid HTTP/1.1
OCS-APIRequest: true
Authorization: Bearer <YOUR_TOKEN>
```

**Impact:** read any user's private out-of-office data — vacation dates, destination,
free-text personal message. Sounds soft until you realise it leaks *when a target's house is
empty* and *where they are*.

**Why it was findable:** Nextcloud is open source. A hunter can grep the route handler,
see the missing ownership check, then confirm it on the live deployment. That is a repeatable
methodology — **read the code, then test the deployed version.**

---

### 3.2 GitLab project import — HackerOne [#743953](https://hackerone.com/reports/743953) — **$20,000**

The highest disclosed IDOR. Not an ID in a URL — an ID inside an **import file**.

```json
// project.json inside a crafted .tar.gz uploaded to the import feature
{ "issue_ids": [27422144] }
```

GitLab's importer trusted foreign keys in the uploaded archive. Importing a project with a
foreign `issue_ids` value **pulled another private project's issues, merge requests and notes
into yours** — including CI/CD secrets — and left them inaccessible on the origin.

**The transferable insight:** IDOR hides in *bulk operations* — import, export, bulk-edit,
move, clone. Any feature that takes an array of IDs is a candidate. Nobody rate-limits an
importer, and the payload is a file, not a parameter, so most scanners never see it.

---

### 3.3 Snapchat GraphQL — HackerOne [#1819832](https://hackerone.com/reports/1819832) — **$15,000**

```graphql
mutation DeleteStorySnaps(ids: ["VICTIM_SNAP_ID"], storyType: SPOTLIGHT_STORY) { ... }
```

A **mutation** — a write — with no field-level authorization. An attacker could delete
anyone's monetised Spotlight videos, directly destroying creator revenue (Crystal Awards
programme).

**The transferable insight:** GraphQL shifts authorization from endpoint-level to
**field/resolver-level**, and most teams never build the second layer. The gateway checks
"is this a valid session?" — the resolver for `DeleteStorySnaps` never checks ownership.
GraphQL IDORs grew **140%** for exactly this reason.

---

### 3.4 Mozilla account deletion — HackerOne [#3154983](https://hackerone.com/reports/3154983) — **$6,000**

The most instructive one, because the bug was *invisible* at the request level.

```http
POST /v1/account/destroy HTTP/1.1
Content-Type: application/json

{ "email": "victim@example.com", "authPW": "deterministic_value_for_sso_users" }
```

Two compounding flaws:
1. The endpoint accepted **the attacker's own Bearer token** while operating on a *victim's*
   account — session misbinding. Authenticate ≠ authorize.
2. Users who signed up via **Google SSO** never set a password, so their `authPW` was a
   **deterministic server-computed value** — identical across all SSO users. Only the email
   was needed.

**Impact:** delete *any* Firefox account. Initially closed **Informative**, later escalated to
**High / $6,000** after the researcher proved the edge case with persistent follow-up.

**Two lessons:** (a) always test endpoints where the *identity in the token* differs from the
*identity in the body*; (b) a closed report is not always a dead report — if you can prove
impact they missed, push back with evidence.

---

### 3.5 Small ones that show the shape

| Report | Endpoint | Technique | Impact |
|---|---|---|---|
| Bykea [#2374730](https://hackerone.com/reports/2374730) | `GET /api/v1/bookings/8847?token=abc` → `8848` | sequential increment | victim name, phone, address, trip |
| DoD [#1626508](https://hackerone.com/reports/1626508) | `GET /Download.aspx?id=4675` → `4676` | sequential increment | next military document |
| HackerOne [#2122671](https://hackerone.com/reports/2122671) | delete certifications | write, no ownership check | **$12,500** — delete all certs |
| PayPal [#415081](https://hackerone.com/reports/415081) | add user to business account | write, no ownership check | **$10,500** |
| Uber [#1145428](https://hackerone.com/reports/1145428) | 3-bug chain | chain | arbitrary charges to any business card — **$5,750** |

---

## 5. Where IDOR actually hides — the surface map

Ranked by how often real disclosures used them:

| Surface | Count | Why it's missed |
|---|---|---|
| Direct ID manipulation in URL/body | 35 (14.8%) | trivially testable, so teams assume they fixed it |
| File/document download | 21 (8.9%) | `?id=` on a download route looks like static content |
| **GraphQL mutations/queries** | 20 (8.4%) | field-level authz is a *second* layer teams never build |
| Session misbinding | uncounted | token valid, resource not owned — no anomalous status code |
| Import/export pipelines | uncounted | payload is a file; IDs live inside archives |
| Chains (IDOR + something) | uncounted | needs two bugs, pays the most |

**Non-obvious surfaces worth testing every engagement:**
- old API versions (`/v1` still live while `/v2` got the fix)
- mobile/zombie endpoints found by reversing the APK
- search endpoints (`/search?org_id=X` — authz often forgotten on filters)
- admin panels with a "user context" parameter
- webhooks / callbacks that echo an object ID
- microservice gateways that pass IDs straight through

### The parameter cheat-sheet

```
user_id, id, uid, user, profile_id, account_id, member_id
booking_id, order_id, transaction_id, payment_id, invoice_id
document_id, file_id, attachment_id, media_id, asset_id
project_id, org_id, team_id, workspace_id, tenant_id
report_id, ticket_id, case_id, issue_id, request_id
comment_id, note_id, message_id, thread_id, conversation_id
certification_id, license_id, credential_id, badge_id
```

**Encoded forms to decode:** base64 (`eyJ1c2VyX2lkIjoxMjM0fQ==` → `{"user_id": 1234}`),
hex (`0x4D2` → `1234`), GraphQL global node IDs (`node(id:"<base64>")`), UUIDs.

---

## 6. Bypasses when the obvious increment fails

1. **Second, forgotten path to the same object** — `/api/users/{id}/orders` may lack the check
   that `/api/users/{id}` has. Always probe alternative routes and sub-resources.
2. **Body vs path** — the path ID may be validated while a body field pointing at the same
   object is not (`{"user_id": 1235}` while URL says `1234`).
3. **Client-side-only enforcement** — the UI hides the button; the API answers anyway.
   Delete the hidden input / replay the request in Burp.
4. **Method swap** — `GET` blocked, `POST`/`PUT`/`PATCH`/`DELETE` unguarded.
5. **Array/parameter pollution** — `?id=1234&id=1235`, `{"id":[1234,1235]}`.
6. **UUID leak hunting** — UUIDs are defense-in-depth, not authorization. They leak in URLs,
   referrers, JSON blobs, emails, error messages, GraphQL responses. Collect, then re-use.
7. **Import file foreign keys** — craft an archive with `"*_ids": [victim_id]`.
8. **GraphQL aliasing** — batch many IDs in one query to prove blast radius without rate limits.

**What does NOT fix IDOR** (so don't be fooled into thinking a target is safe):
rate limiting, UUIDs alone, input validation, HTTPS, client-side checks.

---

## 7. Escalation — turning $500 into $20,000

The 6-phase kill chain:

1. **Recon** — map every endpoint that accepts an object ID
2. **Role mapping** — create ≥2 accounts, record each role's resource IDs
3. **Cross-account testing** — walk every CRUD verb across accounts, not just GET
4. **Enumeration & scale** — measure blast radius: how many objects exist? is it sequential?
5. **Impact demonstration** — move past "I can read profile #2": PII, financial data, writes
6. **Report & escalate** — if rated Low, hunt chains; attach precedence evidence

**Three escalation levers:**
1. Chain with another bug (SSO quirk + IDOR = account takeover)
2. Find the **write/delete** operation — this is the single highest-value move
3. Target **financial or compliance** data (PCI, HIPAA, GDPR)

> Severity reality: **IDOR read of non-sensitive data is Medium (~$1,090).**
> IDOR **write/delete with mass reach is Critical (~$14,333).**
> The vulnerability is the same. Only the demonstrated impact differs.

---

## 8. How to test — step by step (applies to any target)

```
1. Create TWO accounts (A = attacker, B = victim). Never test IDOR with one account.
2. Walk every feature as B; capture all requests with an object ID in path/body/query.
3. Replay each as A. Change ONE thing per request so you know what caused the outcome.
4. Record: status, size delta, and whether the body contains B's data.
5. If read works → try WRITE. PUT/PATCH/DELETE the same object as A.
6. If write works → try cross-tenant / cross-org. Escalate scope of damage.
7. Decode any non-sequential ID (base64/hex/UUID) and hunt the plain value.
8. Check old API versions, mobile endpoints, and alternative routes for the same resource.
9. Prove blast radius — how many objects are reachable, and how fast.
10. Write the report only with raw request/response pairs for both accounts.
```

**Evidence standard for the report:** raw request as A, raw response showing B's data, plus
B's own legitimate request showing the same object belongs to B. Three artifacts. No prose-only
claims — ever.

---

## 9. Common mistakes (what NOT to do)

- **Testing with one account.** You cannot prove IDOR without a second identity. This is the #1
  reason reports get closed as "expected behaviour".
- **Stopping at read.** Reads pay Medium. Writes pay Critical.
- **Claiming impact you didn't demonstrate.** "An attacker could delete all data" without
  actually deleting one test object = N/A.
- **Destroying real victim data to prove a point.** Use your own second account as the victim.
  Never delete a real user's content.
- **Missing the frontend-vs-API gap.** If the UI blocks it, that is a hint the API might not.
- **Ignoring the second route.** `/api/users/1235` validated ≠ `/api/users/1235/invoices` validated.
- **Silent negative.** Record ruled-out attempts — they prove coverage and inform the next pass.

---

## 10. Practice targets (where to find this legally)

| Target type | Why |
|---|---|
| **Vulnerable-by-design apps** | OWASP Juice Shop, DVWA, crAPI, PortSwigger API labs — build the muscle safely |
| **Nextcloud / GitLab / open-source SaaS** | run locally, read the source, then hunt deployed instances |
| **Any program with a "new feature" announcement** | new code = unaudited code; the $15k profile API was brand new |
| **Programs with mobile apps** | legacy endpoints behind the APK usually lag on authz |
| **GraphQL-first products** | field-level authz is the most common gap in 2026 |

Commitment for this lesson: pick **one** vulnerable-by-design app, spin it up in the lab VM,
and run the 10-step methodology end-to-end before the next lesson. That converts this from
reading into reflex.

---

## 11. Key takeaways

1. **Authenticate ≠ authorize.** The server knowing who you are says nothing about whether
   the object is yours.
2. **The bug is a missing question, not a broken function.** Look for where the ownership
   check *should* be and isn't.
3. **All top-bounty IDORs are writes.** Read for discovery, write for payout.
4. **Bulk, import and GraphQL surfaces are where 2026 IDORs live** — not simple `/api/user/1`.
5. **Two accounts minimum.** Every single time.
6. **A closed report isn't a dead report** if you can prove impact they missed.

---

## 12. What to study next

| You learned | Study next |
|---|---|
| Basic IDOR | IDOR with UUID / decodable IDs |
| IDOR on REST | **GraphQL IDOR + field-level authz** ← highest growth |
| Read-only IDOR | Write/delete IDOR + blast-radius proof |
| Cross-account IDOR | Cross-tenant / multi-org IDOR |
| IDOR alone | IDOR + SSO chain → account takeover |

---

## 13. Reference index — every report cited

| # | Report | Bounty | Class | Core technique |
|---|---|---|---|---|
| 1 | [HackerOne #3382343](https://hackerone.com/reports/3382343) | Disclosed | BOLA | `{userId}` in path, no ownership check |
| 2 | [HackerOne #743953](https://hackerone.com/reports/743953) | $20,000 | IDOR | import file foreign keys |
| 3 | [HackerOne #1819832](https://hackerone.com/reports/1819832) | $15,000 | GraphQL IDOR | mutation, no field authz |
| 4 | [HackerOne #3154983](https://hackerone.com/reports/3154983) | $6,000 | Session misbinding | SSO deterministic authPW |
| 5 | [HackerOne #2122671](https://hackerone.com/reports/2122671) | $12,500 | IDOR write | delete all certifications |
| 6 | [HackerOne #415081](https://hackerone.com/reports/415081) | $10,500 | IDOR write | add user to business account |
| 7 | [HackerOne #1145428](https://hackerone.com/reports/1145428) | $5,750 | IDOR chain | arbitrary credit-card charges |
| 8 | [HackerOne #2207248](https://hackerone.com/reports/2207248) | $5,000 | IDOR | cross-shop billing |
| 9 | [HackerOne #2374730](https://hackerone.com/reports/2374730) | — | IDOR | booking ID increment |
| 10 | [HackerOne #1626508](https://hackerone.com/reports/1626508) | — | IDOR | DoD document download |
