# Writeup Study Track — Index

Studying real disclosed writeups from HackerOne, Medium/InfoSecWriteups, and hunter blogs.
One lesson per bug class. Each lesson: mechanism → raw traffic → real cases → bypasses →
escalation → practice assignment.

| # | Lesson | Class | Highest case | Status |
|---|---|---|---|---|
| 01 | [IDOR / BOLA](01-IDOR-BOLA.md) | Access control | GitLab $20,000 | **done** |
| 02 | [GraphQL BOLA & Alias Abuse](02-GraphQL-BOLA.md) | API authz | GitHub $20,000 | **done** |
| 03 | [SSRF → Cloud Metadata](03-SSRF-cloud-metadata.md) | SSRF / cloud | HackerOne critical | **done** |
| 04 | [OAuth Redirect-URI Bypass](04-OAuth-redirect-bypass.md) | OAuth / ATO | Meta $24,000 | **done** |
| 05 | [Race Conditions](05-Race-Conditions.md) | Concurrency / logic | Stripe $5,000 | **done** |
| 06 | [XSS → Account Takeover](06-XSS.md) | Client-side | PayPal $20,000 | **done** |
| 07 | [Web Cache Poisoning & Deception](07-Cache-Poisoning-Deception.md) | Caching | PayPal $18,900 | **done** |
| 08 | [HTTP Request Smuggling](08-Request-Smuggling.md) | Infrastructure | Basecamp $7,500 | **done** |

**Curriculum:** [`../CURRICULUM.md`](CURRICULUM.md) — 10 categories, **30 steps each**, organized
for daily learning. Start there for the full path; the lessons below go deep on one class each.

## Format contract for every lesson

All lessons follow the same shape. Sections 1–2 and the final six are **fixed**; the middle
sections vary by class (mechanism, real cases, surface map, bypasses, escalation).

**Fixed head**

1. **The one-line definition** — the whole bug in one sentence
2. **Real money from real `<class>` reports** — a table of disclosed reports with URLs and bounties

**Middle — varies by class**

3. Mechanism / why the class exists / how the target actually breaks
4. Canonical raw HTTP traffic (the bug in a few lines)
5. Real writeups dissected — endpoint, request, impact, *why it was findable*
6. Surface map — where the class hides, ranked by real disclosure frequency
7. Bypasses when the obvious test fails
8. Escalation ladder — how the same bug goes from $500 to $20,000

**Fixed tail**

- **How to test — methodology** — a numbered checklist
- **Common mistakes** — what gets reports closed
- **Practice targets** — where to find this legally, plus a concrete lab assignment
- **Key takeaways** — numbered, the durable lessons
- **What to study next** — a ladder of related classes
- **Reference index** — every report cited, with URL and bounty

Every lesson header carries `> **Category:**` linking back to its
[CURRICULUM](CURRICULUM.md) section.

### Maintaining consistency

Two scripts in `../tools/` keep the lessons aligned as they're edited:

| Script | Purpose |
|---|---|
| `renumber_sections.py` | Renumber `## N.` headings sequentially after inserting or reordering sections. Skips fenced code blocks. Supports `--check` for a dry run. |
| `fix_section_refs.py` | Rewrite `Lesson NN §X` cross-references after a renumber, using a per-lesson old→new map. |
| `link_report_ids.py` | Turn bare `#1234567` report IDs into clickable links to `hackerone.com/reports/…`. Leaves alone IDs already inside links, inline code, and fenced blocks. Supports `--check`. |

**Workflow when restructuring a lesson:** edit the content → `renumber_sections.py` → update the
map in `fix_section_refs.py` → run it → `link_report_ids.py` → spot-check that citations still
land on the right sections.

**Report IDs are always links.** Never leave a bare `#1234567` in a lesson — run
`link_report_ids.py` before committing.

## Rule

Every technique is backed by a real disclosed report with a URL and a bounty figure where
published. No invented cases. Where a claim can't be sourced, it's marked as general practice
rather than a case study.

## Cross-lesson threads

Recurring principles that appear in more than one class — the real transferable knowledge:

| Thread | Appears in |
|---|---|
| **Authenticate ≠ authorize** — the check that's missing, not the function that's broken | 01, 02, 03 |
| **String matching vs parsing** — validation defeated by parser disagreement | 03, 04 |
| **Writes pay more than reads** — every top bounty involved a write/delete | 01, 02 |
| **Indirection defeats allowlists** — open redirect chains, re-resolution after hops | 03, 04 |
| **Undocumented surface = unaudited surface** — hidden mutations, zombie endpoints | 01, 02 |
| **The 41st payload** — validation testing is combinatorial; persist | 04 |
| **The check runs before the state change** — TOCTOU is just access control with a timing window | 01, 05 |
| **A fix that adds a check isn't a fix** — retest after every remediation | 05, 06 |
| **Prove the origin/impact, not the reflection** — `alert(document.domain)`, the state change | 05, 06 |
| **Two parsers, one request** — desync is a parsing disagreement (cache vs origin, CL vs TE) | 03, 07, 08 |
| **Persistence + cross-client delivery = the finding** — reflection alone proves nothing | 06, 07 |
| **The security layer is a parser too** — WAFs and CDNs have the bugs (Cloudflare $6,000) | 07, 08 |
| **Critical ≠ paid** — Slack and Zomato paid $0 for genuine mass ATO | 08 |

## Suggested order

**The curriculum's order is authoritative** — see [CURRICULUM.md](CURRICULUM.md#suggested-category-order):
Recon → Access Control → Client-Side → Business Logic → API → Identity → Server-Side Request →
Injection → File Handling → Caching & Infrastructure.

Within the lessons written so far, if you just want the fastest route to a paying bug class:

**IDOR (01) → XSS (06) → Race Conditions (05) → OAuth (04) → GraphQL (02) → SSRF (03)**

Reason: IDOR and XSS build the "change one value, observe the delta" reflex on the two
highest-volume classes. Race conditions teach you to think about *intent* and state. OAuth is the
highest-paying class and reuses the same access-control thinking. GraphQL is IDOR's most lucrative
modern surface. SSRF last because it needs the most supporting infrastructure knowledge (cloud IAM).

## Next candidates

These map to curriculum categories that don't have a deep lesson yet:

| Candidate | Curriculum category |
|---|---|
| SQLi / NoSQLi / SSTI / command injection / XXE | 7. Injection |
| File upload + archive extraction | 9. File Handling |
| JWT claim tampering + algorithm confusion | 4. Identity & Auth |
| Open redirect (the chain enabler behind 03 and 04) | 3. Server-Side Request |
| Subdomain takeover + recon pipeline | 10. Recon & Disclosure |
| CSRF + SameSite bypasses | 6. Client-Side |
| CORS misconfiguration | 6. Client-Side |
| Prototype pollution / DOM clobbering | 6. Client-Side |

**Done:** 01 IDOR · 02 GraphQL · 03 SSRF · 04 OAuth · 05 Race · 06 XSS · 07 Cache · 08 Smuggling
— covering curriculum categories 1, 2, 3, 4, 5, 6 and 8.
