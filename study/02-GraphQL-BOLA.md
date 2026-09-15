# Lesson 02 — GraphQL: BOLA, Field-Level Authz & Alias Abuse

> **Source material:** 65 real disclosed GraphQL reports from HackerOne (TOPGRAPHQL index),
> plus `securitycipher.com/2026/07/13/hacking-graphql-apis-2026` and
> `burakdirlik.dev/posts/graphql-vulnerabilities`
> **Format:** writeup → mechanism → raw traffic → bypasses → escalation → practice
> **Status:** Lesson 2 of the study track
> **Category:** 2. API & Protocol — see [CURRICULUM](CURRICULUM.md#2-api--protocol)

---

## 1. The one-line definition

**GraphQL BOLA = the gateway authenticates the session, but each *resolver* is supposed to
re-check authorization for the field it returns — and developers forget them individually.**

That's the whole bug class. In REST, access control sits at the route. In GraphQL there is no
route — there's a resolver per field. A scanner that crawls URLs sees one endpoint and moves on.
**The real surface is the schema behind it.**

---

## 2. Real money from real GraphQL reports

From 65 disclosed HackerOne GraphQL reports — the paid ones:

| Report | Program | Bounty | The bug |
|---|---|---|---|
| [#1711938](https://hackerone.com/reports/1711938) | GitHub | **$20,000** | Scoped user-to-server token → **full access to a user's Project V2 projects** via GraphQL |
| [#2207248](https://hackerone.com/reports/2207248) | Shopify | **$5,000** | **IDOR** on `BillingDocumentDownload` + `BillDetails` queries |
| [#2216036](https://hackerone.com/reports/2216036) | GitHub | **$4,000** | Race between REST repo-transfer and `updateTeamsRepository` **mutation** → covert persistent admin access |
| [#858671](https://hackerone.com/reports/858671) | GitLab | **$4,000** | Insufficient type check → maintainer can **delete repository** |
| [#1864188](https://hackerone.com/reports/1864188) | EXNESS | **$3,000** | **SSRF** inside a GraphQL query |
| [#978143](https://hackerone.com/reports/978143) / [#770209](https://hackerone.com/reports/770209) / [#715192](https://hackerone.com/reports/715192) | HackerOne | **$2,500** each | Team object leaked `private_comment`, `report_sources`, `vpn_suspended` |
| [#981472](https://hackerone.com/reports/981472) | Shopify | **$2,000** | **Undocumented** `fileCopy` API |
| [#1085332](https://hackerone.com/reports/1085332) | Shopify | **$1,900** | `shopApps` returned all apps **including private ones** |
| [#1085546](https://hackerone.com/reports/1085546) | Shopify | **$1,600** | **Stored XSS** via `productUpdate` mutation |
| [#1192460](https://hackerone.com/reports/1192460) | GitLab | **$1,370** | **Deactivated** user still read data through GraphQL |
| [#633001](https://hackerone.com/reports/633001) | GitLab | **$1,000** | Private system-note disclosure |
| [#419883](https://hackerone.com/reports/419883) | Shopify | **$802** | GraphQL disclosed internal beer consumption 😄 |
| [#276174](https://hackerone.com/reports/276174) | New Relic | **$750** | Restricted user → root account license key |
| [#417382](https://hackerone.com/reports/417382) | HackerOne | **$500** | Revoking a session **didn't revoke the GraphQL session** |
| [#707406](https://hackerone.com/reports/707406) | HackerOne | **$500** | Team object leaked private programs by industry |
| [#1000567](https://hackerone.com/reports/1000567) | CS Money | **$250** | ReDoS on a GraphQL endpoint |

**Zero-dollar but instructive** (still worth studying — write-access bugs that paid nothing):
- TikTok [#984965](https://hackerone.com/reports/984965) — **cross-tenant IDOR** on
  `AddRulesToPixelEvents`: add, update **and delete** rules on any Pixel event
- Stripe [#1066203](https://hackerone.com/reports/1066203) — cross-tenant IDOR **write** via
  `UpdateAtlasApplicationPerson`

**Pattern to notice:** the highest payouts go to **mutations and token-scope confusion**, not
to introspection findings. Introspection leaks (many reports) almost always paid **$0** —
programs treat "you can see the schema" as informational. **Authz and write operations pay.**

---

## 3. Why GraphQL is a different game

REST spreads its attack surface across dozens of routes you have to *discover*.
GraphQL funnels everything through **one endpoint** that will **describe itself** if you ask.

Three properties change how you test:

| Property | Why it breaks REST habits |
|---|---|
| **Self-describing** | Introspection hands you the full schema — including operations no UI ever calls |
| **Client-controlled shape** | You choose fields, nesting, and *how many operations* go in one request |
| **Per-field authorization** | Authz must be re-checked inside **every resolver**. One missed field = a real bug |

That last row is the whole lesson — a scanner that crawls URLs sees one endpoint and moves on.
The real surface is the schema behind it.

---

## 4. The canonical attack — resolver-level BOLA

```
query {
  user(id: "1043") {        # your own id is 1042 — try the neighbour
    id
    email
    phone
    apiKey                  # sensitive field, often unprotected
  }
}
```

The parent `user` resolver checked that you're authenticated. The **field resolver** for
`apiKey` never asked whether 1043 is you. That's BOLA at field level.

Then the one that pays:

```
mutation {
  updateUser(id: "1043", input: { email: "attacker@evil.tld" }) {
    id
    email
  }
}
```

**Mutations are frequently less guarded than queries** — teams add authz to the read path
they think about, and forget the write path.

### Nested object BOLA — the sneaky variant

```
query {
  me {
    organization {
      members { email }     # ← authorized parent, unauthorized child
    }
  }
}
```

`me` is legitimately yours. `organization` is legitimately yours. `members` is **not** — but
the nested resolver inherited the parent's confidence and forgot its own check. This shape
appears repeatedly in the disclosed corpus and is invisible to endpoint-level testing.

---

## 5. Alias & batch attacks — the GraphQL-specific multiplier

### Aliases: one HTTP request, 10,000 operations

```
mutation {
  a1: verifyOtp(code: "0001") { token }
  a2: verifyOtp(code: "0002") { token }
  a3: verifyOtp(code: "0003") { token }
  # ... generate all 9999 and send as ONE request
}
```

If the server rate-limits **by HTTP request** instead of **by operation**, you just multiplied
your attempts by 10,000. That defeats OTP/2FA brute-force protection, coupon validation, and
login throttling — and it's a **near-direct path to account takeover**.

### Batching: an array of operations in one call

```json
[
  {"query":"{ user(id:\"1001\"){ email } }"},
  {"query":"{ user(id:\"1002\"){ email } }"},
  {"query":"{ user(id:\"1003\"){ email } }"}
]
```

Same rate-limit bypass, plus **mass BOLA probing** — fire 100 object IDs at once and diff the
responses. This is how you measure blast radius without tripping a throttle.

> Note the Shopify report [#481518](https://hackerone.com/reports/481518) — bypassing the
> GraphQL rate limit by abusing **negative cost queries**. The cost model itself is attackable.

---

## 6. Finding and fingerprinting the endpoint

Common paths: `/graphql`, `/graphql/console`, `/graphiql`, `/api/graphql`, `/v1/graphql`,
`/query`, `/gql`

**Confirmation one-liner** — a GET that returns the typename proves it:

```
GET /graphql?query={__typename}
→ {"data":{"__typename":"Query"}}
```

Also check **JS bundles and mobile traffic** — SPAs embed the endpoint and sample queries.

**Fingerprint the engine** (Apollo, graphene, Hasura, graphql-php have different quirks):

```
pip install graphw00f
python3 -m graphw00f -f -t https://target.tld/graphql
```

---

## 7. Dumping the schema with introspection

Confirm introspection is on:

```json
{"query":"{ __schema { queryType { name } mutationType { name } types { name kind } } }"}
```

If type names come back, fire the full `IntrospectionQuery` (the one GraphiQL uses) and load it
into:

- **InQL** (Burp extension) — auto-generates every query/mutation/subscription from the schema,
  flags circular refs and "points of interest", sends straight to Repeater/Intruder
- **Altair / GraphiQL** — interactive IDE
- **GraphQL Voyager** — visual graph, makes sensitive types obvious

**Read the schema like a target list.** Look for:
- mutations: `updateUser`, `deleteAccount`, `resetPassword`, `transferOwnership`
- admin-flavoured types
- fields: `role`, `isAdmin`, `apiKey`, `ssn`, `balance`, `internal`
- **operations the frontend never calls** — undocumented API = unaudited API
  (Shopify paid $2,000 for finding exactly that: `fileCopy`)

---

## 8. Introspection off? Rebuild the schema anyway

Disabled introspection is a speed bump, not a wall. If **field suggestions** are on, the server
corrects your typos and leaks field names one guess at a time:

```
Cannot query field 'pasword' on type 'User'. Did you mean 'password'?
```

**clairvoyance** automates this:

```
pip install clairvoyance
clairvoyance https://target.tld/graphql -o schema.json -w wordlist.txt
# then feed schema.json into InQL
```

> **This is the lesson:** "we disabled introspection" is **defense in depth, not a fix.** And
> crucially — **the real bugs don't need introspection at all** once you know a few operation
> names. You'll find those in JS bundles, mobile apps, or the error messages.

---

## 9. Bypasses & extra surfaces

| Technique | Payload / approach |
|---|---|
| **Nested BOLA** | `me { org { members { email } } }` — parent authorized, child not |
| **Alias flooding** | 1000 aliases of one mutation in a single request |
| **Batch array** | `[{query},{query},...]` for mass probing |
| **Negative cost queries** | abuse the cost model to bypass rate limits (Shopify [#481518](https://hackerone.com/reports/481518)) |
| **Token-scope confusion** | a *scoped* token (read-only, or app-scoped) invoking a **write** mutation (GitHub $20k, GitLab CVE-2025-11340) |
| **Deactivated-user access** | log out / deactivate an account, replay the query (GitLab $1,370) |
| **Session revocation gap** | revoke session in UI, replay GraphQL (HackerOne [#417382](https://hackerone.com/reports/417382), $500) |
| **Cross-tenant write** | swap `tenant_id`/`org_id` inside a mutation (TikTok, Stripe) |
| **GET-based CSRF** | if queries/mutations accept GET or form-POST, cross-site requests trigger them |
| **Argument injection** | `user(id: "1 OR 1=1")`, Hasura filters `{where:{role:{_eq:"admin"}}}` |
| **SSRF via resolver** | a URL argument that gets fetched server-side (EXNESS [#1864188](https://hackerone.com/reports/1864188), $3,000) |
| **DoS (careful!)** | circular nesting `posts{author{posts{author{...}}}}`, directive overloading, field duplication |

**DoS warning:** only test with **explicit permission and agreed limits**. Prove it with a
measured response-time spike, never by actually taking the service down. Many programs want a
description plus a small PoC, not an outage.

---

## 10. Escalation — what separates $0 from $20,000

Reading the corpus, the escalation levers are clear:

1. **Query → Mutation.** Read BOLA pays ~$2,500. Write BOLA pays $5,000–$20,000.
2. **Add a scope/role dimension.** "A user can read another user" is Medium. "A **scoped** token
   can read **everything**" is Critical (GitHub $20k).
3. **Chain it.** GitHub's $4,000 was a *race* between a REST endpoint and a GraphQL mutation —
   neither alone was exploitable. Chains pay.
4. **Find the undocumented operation.** No UI calls it → no security review touched it.
5. **Prove blast radius.** "I read one field" vs "I can enumerate every tenant's billing
   documents."

**Severity reality:** introspection findings paid **$0** across the entire corpus. Don't lead
with them. Authz and writes are the money.

---

## 11. How to test — the checklist

```
01. Locate endpoint (paths, JS bundles, mobile traffic) + fingerprint engine (graphw00f)
02. Test introspection; dump schema; load into InQL / Voyager
03. If off → run clairvoyance against field suggestions to rebuild it
04. Review schema: sensitive fields, admin types, UNUSED mutations
05. BOLA on queries AND mutations, INCLUDING nested relationships
06. Test as the LOWEST-privilege role you can get
07. Alias attack on OTP / login / coupon for rate-limit bypass
08. Batch array for mass BOLA probing + rate-limit bypass
09. Depth / circular / directive / field-duplication DoS — within agreed limits only
10. Argument injection (SQL/NoSQL/operator) and CSRF-over-GET
11. Info leaks: verbose errors, Apollo tracing/debug, field suggestions
12. Deactivated / logged-out / revoked-session replay
13. Scoped-token → write-mutation test (the $20k pattern)
14. Confirm every finding by hand with raw request/response before reporting
```

**Tooling one-liner for a first sweep** (treat output as leads, not findings):

```
pip install graphql-cop
graphql-cop -t https://target.tld/graphql --header '{"Authorization": "Bearer <token>"}'
```

---

## 12. Common mistakes

- **Leading with introspection.** It's a $0 finding in practice. Note it, don't headline it.
- **Testing only queries.** Mutations are the money and the most-forgotten authz.
- **Missing nested objects.** The parent check passing is not the child check passing.
- **Testing with a privileged account.** Get the lowest role you can. Test as a deactivated user.
- **Ignoring the token scope.** A scoped token that can write is the highest-paying pattern here.
- **Not diffing batch responses.** Batching is how you measure blast radius silently.
- **Causing real DoS.** Prove it measured, never by outage.
- **Assuming "introspection off" = secure.** clairvoyance exists.

---

## 13. Practice targets

| Target | Why |
|---|---|
| **DVGA (Damn Vulnerable GraphQL App)** | purpose-built, runs in the lab VM, covers all classes above |
| **crAPI** | API-focused, has GraphQL surfaces |
| **Hasura / Apollo demo apps** | filter/operator injection, missing field authz |
| **Any SPA** | the endpoint + sample queries are embedded in the JS bundle |
| **Programs with mobile apps** | mobile GraphQL queries are often less-guarded than web |

**Assignment:** stand up DVGA in the lab, dump the schema, then complete the 14-step checklist
end-to-end — including one alias-flood on the OTP mutation and one nested-object BOLA. That's
the muscle. Next lesson builds on it.

---

## 14. Key takeaways

1. **One endpoint, many resolvers.** Authz is per-field, and developers forget fields.
2. **Mutations > queries.** Write bugs pay 2–10× read bugs.
3. **Scoped-token → write-mutation is the $20k pattern.** Test token scope against every mutation.
4. **Aliases/batching defeat rate limits** by turning 1 request into 10,000 operations.
5. **Introspection off ≠ safe.** clairvoyance rebuilds it from typo suggestions.
6. **Nested BOLA hides in authorized parents.** Always probe the child relationship.
7. **Undocumented operations are unaudited operations.** Grep the schema for what the UI ignores.

---

## 15. What to study next

| You learned | Study next |
|---|---|
| GraphQL BOLA | **SSRF via resolver → cloud metadata** ← Lesson 03 |
| Alias rate-limit bypass | OTP/2FA brute force → account takeover chains |
| Token scope confusion | OAuth scope escalation + JWT confusion |
| GraphQL DoS | Cost-model abuse, negative-cost queries |
| Cross-tenant write | Multi-tenant isolation testing methodology |

---

## 16. Reference index

| # | Report | Bounty | Class |
|---|---|---|---|
| 1 | [GitHub #1711938](https://hackerone.com/reports/1711938) | $20,000 | token scope → full project access |
| 2 | [Shopify #2207248](https://hackerone.com/reports/2207248) | $5,000 | IDOR on billing queries |
| 3 | [GitHub #2216036](https://hackerone.com/reports/2216036) | $4,000 | race: REST ↔ GraphQL mutation |
| 4 | [GitLab #858671](https://hackerone.com/reports/858671) | $4,000 | type check → repo deletion |
| 5 | [EXNESS #1864188](https://hackerone.com/reports/1864188) | $3,000 | SSRF in GraphQL query |
| 6 | [HackerOne #978143](https://hackerone.com/reports/978143) | $2,500 | private_comment disclosure |
| 7 | [Shopify #981472](https://hackerone.com/reports/981472) | $2,000 | undocumented `fileCopy` |
| 8 | [Shopify #1085332](https://hackerone.com/reports/1085332) | $1,900 | private apps exposed |
| 9 | [Shopify #1085546](https://hackerone.com/reports/1085546) | $1,600 | stored XSS via mutation |
| 10 | [GitLab #1192460](https://hackerone.com/reports/1192460) | $1,370 | deactivated user access |
| 11 | [TikTok #984965](https://hackerone.com/reports/984965) | $0 | cross-tenant IDOR write |
| 12 | [Stripe #1066203](https://hackerone.com/reports/1066203) | $0 | cross-tenant IDOR write |
| 13 | [Shopify #481518](https://hackerone.com/reports/481518) | $0 | negative-cost rate-limit bypass |
| 14 | [HackerOne #417382](https://hackerone.com/reports/417382) | $500 | session revocation gap |
| 15 | [CS Money #1000567](https://hackerone.com/reports/1000567) | $250 | ReDoS |
