# Bug Bounty Curriculum — Categories & 30-Step Paths

Organized for **daily learning**. Each category is a 30-step path you can walk one step per day
(≈30 days per category, 10 categories ≈ 10 months of structured practice).

Every step names a **concrete action** and, where one exists, a **real disclosed report** to read
for it. Bounty figures are the disclosed amounts.

**How to use this daily**

1. Pick **one** category as your current focus. Don't spread across categories.
2. Do **one step per day** — 30–60 minutes. Read the cited writeup, then *do* the action.
3. Keep a running log: what you tried, what the target said, what you learned.
4. When you hit a real target mid-path, **stop the curriculum and hunt**. Come back after.
5. Every step ends with either a lab rep or a live test. Reading alone doesn't count.

| # | Category | Lesson | Focus |
|---|---|---|---|
| 1 | [Access Control](#1-access-control) | [01](01-IDOR-BOLA.md) | IDOR, BOLA, BFLA, auth bypass |
| 2 | [API & Protocol](#2-api--protocol) | [02](02-GraphQL-BOLA.md) | GraphQL, REST, mass assignment |
| 3 | [Server-Side Request](#3-server-side-request) | [03](03-SSRF-cloud-metadata.md) | SSRF, path traversal, open redirect |
| 4 | [Identity & Auth](#4-identity--auth) | [04](04-OAuth-redirect-bypass.md) | OAuth, JWT, SAML, OTP/2FA |
| 5 | [Business Logic](#5-business-logic) | [05](05-Race-Conditions.md) | races, price manipulation, workflows |
| 6 | [Client-Side](#6-client-side) | [06](06-XSS.md) | XSS, CSRF, CORS, postMessage |
| 7 | [Injection](#7-injection) | — | SQLi, NoSQLi, SSTI, cmdi, XXE |
| 8 | [Caching & Infrastructure](#8-caching--infrastructure) | [07](07-Cache-Poisoning-Deception.md) · [08](08-Request-Smuggling.md) | cache poison, smuggling, host header |
| 9 | [File Handling](#9-file-handling) | — | upload, traversal, archives |
| 10 | [Recon & Disclosure](#10-recon--disclosure) | — | subdomains, secrets, cloud storage |

---

## 1. Access Control

*The highest-volume paying class. Lesson 01 covers this in full.*

| # | Step | Source |
|---|---|---|
| 1 | Learn the difference: **authentication** (who are you) vs **authorization** (is this yours) | — |
| 2 | Create **two accounts** on one target. Never test IDOR with one identity | — |
| 3 | Map every endpoint carrying an object ID — path, query, body, header | — |
| 4 | Replay account A's request with B's object ID. Change **one** thing per request | [Nextcloud #3382343](https://hackerone.com/reports/3382343) |
| 5 | Learn the ID-parameter cheat-sheet (`user_id`, `order_id`, `org_id`, `tenant_id`…) | Lesson 01 §5 |
| 6 | Decode non-sequential IDs: base64, hex, UUID, GraphQL global node IDs | Lesson 01 §5 |
| 7 | Test **write** verbs — PUT/PATCH/DELETE. Reads pay Medium, writes pay Critical | [HackerOne #2122671](https://hackerone.com/reports/2122671) $12,500 |
| 8 | Find the **second route** to the same object (`/users/{id}` vs `/users/{id}/invoices`) | Lesson 01 §6 |
| 9 | Test **nested objects** — authorized parent, unauthorized child | Lesson 02 §4 |
| 10 | Test **import/export** pipelines — IDs hidden inside files | [GitLab #743953](https://hackerone.com/reports/743953) $20,000 |
| 11 | Test **bulk operations** — any endpoint taking an array of IDs | — |
| 12 | Test old API versions (`/v1` vs `/v2`) — fixes often miss the old path | Lesson 01 §5 |
| 13 | Reverse a mobile APK; hunt **zombie endpoints** that lag on authz | [Bykea #3085742](https://hackerone.com/reports/3085742) |
| 14 | Test **cross-tenant** — swap `org_id`/`tenant_id` across two orgs you own | [TikTok #984965](https://hackerone.com/reports/984965) |
| 15 | Test **session misbinding** — your token, someone else's object in the body | [Mozilla #3154983](https://hackerone.com/reports/3154983) $6,000 |
| 16 | Test **BFLA** — call admin functions as a normal user | Lesson 02 §4 |
| 17 | Test **deactivated / logged-out** accounts — replay after revocation | [GitLab #1192460](https://hackerone.com/reports/1192460) $1,370 |
| 18 | Test **method swap** — GET blocked, POST/PUT unguarded | Lesson 01 §6 |
| 19 | Test **parameter pollution** — `?id=A&id=B`, `{"id":[A,B]}` | Lesson 01 §6 |
| 20 | Check for **client-side-only** enforcement — the UI hides it, the API answers | Lesson 01 §6 |
| 21 | Test **role boundaries** — every role against every endpoint | — |
| 22 | Test **mass assignment** — add `role`, `isAdmin`, `verified` to a profile update | — |
| 23 | Map **what the UI never calls** — undocumented endpoints are unaudited | Lesson 02 §7 |
| 24 | Chain IDOR with a role check gap → privilege escalation | Lesson 01 §7 |
| 25 | Prove **blast radius** — how many objects, how fast, sequential or not | Lesson 01 §7 |
| 26 | Learn what does **NOT** fix IDOR: rate limits, UUIDs, HTTPS, client checks | Lesson 01 §6 |
| 27 | Build a reusable ID-swap script for your arsenal | Lesson 01 §8 |
| 28 | Write the report: request as A + response showing B's data + B's own request | Lesson 01 §8 |
| 29 | Re-read every disclosed IDOR on your target's program page | Lesson 01 §13 |
| 30 | **Live rep:** run the full 10-step methodology on one real in-scope target | Lesson 01 §8 |

---

## 2. API & Protocol

*Lesson 02 covers GraphQL in full. This adds the surrounding API surface.*

| # | Step | Source |
|---|---|---|
| 1 | Find the API: `/api`, `/v1`, `/graphql`, `/rest`, JS bundles, mobile traffic | Lesson 02 §6 |
| 2 | Locate API docs: Swagger/OpenAPI, `/docs`, `/redoc`, Postman collections | — |
| 3 | Pull the full endpoint list from the docs — that's your test plan | — |
| 4 | Learn GraphQL fundamentals: query vs mutation, resolver, schema | Lesson 02 §1 |
| 5 | Fingerprint the GraphQL engine (`graphw00f`) | Lesson 02 §6 |
| 6 | Dump the schema via introspection | Lesson 02 §7 |
| 7 | If introspection is off, rebuild it with **clairvoyance** from field suggestions | Lesson 02 §8 |
| 8 | Read the schema as a target list: sensitive fields, admin types, **unused mutations** | Lesson 02 §7 |
| 9 | Test **resolver-level BOLA** on queries | [Shopify #2207248](https://hackerone.com/reports/2207248) $5,000 |
| 10 | Test BOLA on **mutations** — less guarded than queries | [Snapchat #1819832](https://hackerone.com/reports/1819832) $15,000 |
| 11 | Test **nested-object BOLA** | Lesson 02 §4 |
| 12 | Test **token-scope confusion** — a scoped token invoking a write | [GitHub #1711938](https://hackerone.com/reports/1711938) $20,000 |
| 13 | Learn the **alias attack** — 10,000 operations in one HTTP request | Lesson 02 §5 |
| 14 | Learn **batching** — array of operations for mass probing | Lesson 02 §5 |
| 15 | Attack the **cost model** — negative-cost queries | [Shopify #481518](https://hackerone.com/reports/481518) |
| 16 | Test **argument injection** in GraphQL args (SQL/NoSQL/operator) | Lesson 02 §9 |
| 17 | Test **CSRF over GET** — queries/mutations accepted via GET or form-POST | Lesson 02 §9 |
| 18 | Check for **verbose errors**, Apollo tracing, debug modes | Lesson 02 §9 |
| 19 | Test **REST verb tampering** — OPTIONS, TRACE, arbitrary methods | — |
| 20 | Test **content-type confusion** — JSON vs form vs XML on the same endpoint | — |
| 21 | Test **mass assignment** on every create/update endpoint | — |
| 22 | Look for **excessive data exposure** — API returns fields the UI never shows | — |
| 23 | Test **pagination/lookup** for enumeration (`?limit=99999`, cursor tampering) | — |
| 24 | Test **rate-limit gaps** on API endpoints vs the UI | — |
| 25 | Test **WebSocket** endpoints — auth on connect vs per-message | — |
| 26 | Compare **mobile API vs web API** — divergent authz | Lesson 01 §5 |
| 27 | Test **GraphQL subscriptions** for authz gaps | — |
| 28 | Build a schema→requests generator in your arsenal (or learn InQL) | Lesson 02 §7 |
| 29 | Learn to write a GraphQL BOLA report with a resolver-level explanation | Lesson 02 §11 |
| 30 | **Live rep:** full 14-step GraphQL checklist on a lab (DVGA) then a live target | Lesson 02 §11 |

---

## 3. Server-Side Request

*Lesson 03 covers SSRF→metadata in full. This adds traversal and redirect.*

| # | Step | Source |
|---|---|---|
| 1 | Learn the SSRF primitive: the server fetches a URL you control | Lesson 03 §1 |
| 2 | Find features that fetch server-side: webhooks, importers, PDF/render, link preview | Lesson 03 §3 |
| 3 | Confirm with an **OOB listener** (Burp Collaborator / interactsh) | Lesson 03 §4 |
| 4 | Distinguish **DNS-only** vs full HTTP callback — different bugs | Lesson 03 §4 |
| 5 | Test which **schemes** work: http, https, gopher, file, dict, ftp | Lesson 03 §9 |
| 6 | Test **method control** — can you force PUT/POST? | Lesson 03 §6 |
| 7 | Test **header control** — does it forward user headers? CRLF injection? | Lesson 03 §9 |
| 8 | Probe internal: `127.0.0.1`, `localhost`, RFC1918 ranges, common ports | Lesson 03 §11 |
| 9 | Probe `169.254.169.254` — AWS/GCP/Azure metadata paths | Lesson 03 §5–8 |
| 10 | Learn **IMDSv1 vs IMDSv2** — and that `HttpTokens=required` is the real fix | Lesson 03 §6 |
| 11 | Learn GCP's `Metadata-Flavor: Google` header requirement | Lesson 03 §7 |
| 12 | Learn Azure's `Metadata: true` + `api-version` (missing it looks like a dead endpoint) | Lesson 03 §8 |
| 13 | Learn **gopher://** — raw bytes let you satisfy header/PUT requirements | Lesson 03 §9 |
| 14 | Learn address encodings: decimal, octal, hex, IPv6-mapped, nip.io | Lesson 03 §9 |
| 15 | Test **redirect following** — open redirect on an allowlisted domain | Lesson 03 §9 |
| 16 | Learn **DNS rebinding** — resolve-then-connect mismatch | Lesson 03 §9 |
| 17 | Prove credential validity with `aws sts get-caller-identity` — and don't trip GuardDuty | Lesson 03 §5 |
| 18 | Map **blast radius** from the role — S3, Secrets Manager, role assumption | Lesson 03 §10 |
| 19 | Test **path traversal**: `../`, `%2e%2e/`, double encoding, null bytes | — |
| 20 | Test traversal in **non-obvious** places: file names, ZIP entries, log paths | — |
| 21 | Test **log poisoning** → traversal → RCE | — |
| 22 | Learn the difference: **open redirect** vs **SSRF** vs **path traversal** | — |
| 23 | Hunt open redirects on every allowlisted domain you find | Lesson 04 §5 |
| 24 | Test redirect params: `next`, `url`, `redirect`, `return`, `continue`, `dest` | — |
| 25 | Test open-redirect **bypasses**: `//evil.com`, `https:/evil.com`, `\/\/`, `@` | Lesson 04 §5 |
| 26 | Learn why SSRF severity is set by the **IAM role**, not the web bug | Lesson 03 §10 |
| 27 | Test SSRF in **GraphQL resolvers** (URL arguments) | [EXNESS #1864188](https://hackerone.com/reports/1864188) $3,000 |
| 28 | Test SSRF in **PDF/image renderers** — they follow `<img>`, `<iframe>`, CSS `url()` | Lesson 03 §3 |
| 29 | Test SSRF via **SVG/XML** — XXE that becomes SSRF | Lesson 03 §13 |
| 30 | **Live rep:** bypass a naive `169.254.169.254` blocklist four ways in the lab | Lesson 03 §13 |

---

## 4. Identity & Auth

*Lesson 04 covers OAuth redirect bypass in full. This adds JWT, SAML, OTP.*

| # | Step | Source |
|---|---|---|
| 1 | Learn the OAuth flows: authorization code, implicit, client credentials, PKCE | Lesson 04 §1 |
| 2 | Map a full legitimate flow; note every parameter and its format | Lesson 04 §8 |
| 3 | Understand `redirect_uri` — it tells the server where to send the token | Lesson 04 §2 |
| 4 | Test redirect_uri validation: suffix, prefix, subdomain tricks | Lesson 04 §5 |
| 5 | **The `@` userinfo bypass** — RFC 3986, host is what follows `@` | Lesson 04 §4 |
| 6 | Test encoding layers: `%40`, `%2f`, `%252e`, unicode look-alikes | Lesson 04 §5 |
| 7 | Test path confusion: `../`, fragments, backslashes | Lesson 04 §5 |
| 8 | Test parameter pollution: two `redirect_uri` values | Lesson 04 §5 |
| 9 | Test wildcard/prefix regex abuse in the allowlist | Lesson 04 §5 |
| 10 | Chain an **open redirect on an allowlisted domain** | Lesson 04 §5 |
| 11 | Test **`state`**: omit it, replay it, use one from another session | Lesson 04 §6 |
| 12 | Test **scope escalation** — request broader scopes than the client should have | Lesson 04 §6 |
| 13 | Test **PKCE downgrade** — remove `code_challenge`, plain vs S256 | Lesson 04 §6 |
| 14 | Learn **`postMessage` target-origin** parsing (server vs browser disagreement) | Lesson 04 §7 |
| 15 | Test silent flows (`mode=hidden`) — they remove the consent screen | Lesson 04 §4 |
| 16 | Test **first-party client_ids** — broader scopes, less scrutiny | Lesson 04 §9 |
| 17 | Test **pre-account-takeover** — register the victim's email first | Lesson 04 §6 |
| 18 | Test **account linking without verification** | Lesson 04 §6 |
| 19 | Learn JWT structure: header.payload.signature, base64url | — |
| 20 | Test **`alg:none`** — strip the signature entirely | — |
| 21 | Test **algorithm confusion** — RS256 → HS256 using the public key as the secret | — |
| 22 | Test **`kid` injection** — path traversal, SQLi, key confusion in the key ID | — |
| 23 | Test **weak HMAC secrets** — crack with hashcat against a wordlist | — |
| 24 | Test **claim tampering** — `role`, `isAdmin`, `sub`, `exp`, `aud` | — |
| 25 | Test JWT **revocation gaps** — does logout actually invalidate the token? | [HackerOne #417382](https://hackerone.com/reports/417382) $500 |
| 26 | Test **SAML** — XSW (XML signature wrapping), comment injection, audience confusion | — |
| 27 | Test **OTP/2FA** — brute force via GraphQL aliases (Lesson 02 §5) | — |
| 28 | Test **password reset** — token entropy, host-header poisoning, response leakage | — |
| 29 | Test **session fixation** and cookie attribute gaps (`HttpOnly`, `Secure`, `SameSite`) | — |
| 30 | **Live rep:** stand up Keycloak/authentik, walk the full §4 taxonomy, build a postMessage SPA | Lesson 04 §10 |

---

## 5. Business Logic

*Lesson 05 covers race conditions in full. This is the widest category.*

| # | Step | Source |
|---|---|---|
| 1 | Learn the mindset: business logic bugs need **domain understanding**, not scanners | Lesson 05 §1 |
| 2 | Map every workflow: signup, checkout, refund, upgrade, invite, transfer | — |
| 3 | For each workflow, write down **every assumption** the app makes | — |
| 4 | Find "one per user" limits. Ask: DB constraint or app-layer `if`? | Lesson 05 §5 |
| 5 | Learn TOCTOU: the check runs **before** the state change | Lesson 05 §1 |
| 6 | Test **coupon/voucher** double-redeem | [Stripe #1849626](https://hackerone.com/reports/1849626) $5,000 |
| 7 | Test **gift card** double-spend | [Reverb #759247](https://hackerone.com/reports/759247) $1,500 |
| 8 | Learn **last-byte synchronisation** (HTTP/1.1) | Lesson 05 §4.1 |
| 9 | Learn the **single-packet attack** (HTTP/2) — the technique that made races reliable | Lesson 05 §4.2 |
| 10 | Learn the Turbo Intruder script: `Engine.BURP2` + `gate`/`openGate`, ~20 requests | Lesson 05 §4.2 |
| 11 | Learn the **negative timestamp** diagnostic | Lesson 05 §4.2 |
| 12 | Test **invitation limits** | [Keybase #115007](https://hackerone.com/reports/115007) $350 |
| 13 | Test **plan/seat limits** | [Shopify #176127](https://hackerone.com/reports/176127) $500 |
| 14 | Test **vote/rating/review** duplication | [Coinbase #106360](https://hackerone.com/reports/106360) $100 |
| 15 | Test **currency/points** duplication | [InnoGames #509629](https://hackerone.com/reports/509629) $2,000 |
| 16 | Test **payout/payment** duplication | [HackerOne #429026](https://hackerone.com/reports/429026) $2,100 |
| 17 | Test **OAuth token issuance** races | [IBB #55140](https://hackerone.com/reports/55140) $2,500 |
| 18 | Learn to prove the **state change**, not the HTTP 200s | Lesson 05 §8 |
| 19 | Look for **negative balances** — the proof of double-spend | Lesson 05 §8 |
| 20 | Test **price manipulation** — negative quantity, zero price, currency swap | — |
| 21 | Test **quantity/rounding** abuse — fractional items, rounding in your favour | — |
| 22 | Test **workflow step skipping** — jump to step 3, replay step 1 | — |
| 23 | Test **refund after delivery**, refund twice, refund a discounted order | — |
| 24 | Test **trial/plan downgrade** abuse — keep the features | — |
| 25 | Test **free-tier limits** — bypass via a second workspace/org | — |
| 26 | Test **email/phone verification** bypass — unverified state reached by skipping | — |
| 27 | Learn **state-machine bugs** (Kettle's *Smashing the State Machine*) | Lesson 05 §12 |
| 28 | Test **client-side races** — don't assume races are server-only | [HackerOne #381356](https://hackerone.com/reports/381356) $1,250 |
| 29 | Learn that **a fix adding a check isn't a fix** — retest after every remediation | Lesson 05 §3 |
| 30 | **Live rep:** break a coupon limit, then add a DB constraint and confirm the race dies | Lesson 05 §10 |

---

## 6. Client-Side

*Lesson 06 covers XSS in full. This adds CSRF, CORS, prototype pollution.*

| # | Step | Source |
|---|---|---|
| 1 | Learn the three XSS types and **why stored pays most** | Lesson 06 §3 |
| 2 | Learn output contexts: HTML body, attribute, JS string, CSS, URL, JSON | Lesson 06 §3 |
| 3 | Learn the payload shapes per context | Lesson 06 §3 |
| 4 | Learn the DOM **sinks** and **sources** | Lesson 06 §3 |
| 5 | **Always prove origin** — `alert(document.domain)`, never `alert(1)` | Lesson 06 §3 |
| 6 | Test `location.hash` — never sent to the server, so filters never see it | [Slack #146336](https://hackerone.com/reports/146336) $1,100 |
| 7 | Test **stored** XSS in every field, then find every page it renders on | [Uber #217739](https://hackerone.com/reports/217739) $6,000 |
| 8 | Test **blind** XSS with an OOB payload in admin/support surfaces | [LocalTapiola #135154](https://hackerone.com/reports/135154) $5,000 |
| 9 | Grep JS for `postMessage` handlers; test **missing origin checks** | Lesson 06 §4 |
| 10 | Test the **target-origin** argument for parser disagreement | [HackerOne #398054](https://hackerone.com/reports/398054) $500 |
| 11 | Work the **bypass table**: tag, handler, quote, case, encoding | Lesson 06 §6 |
| 12 | Test **SVG** everywhere — upload, icons, filters | [Shopify #232174](https://hackerone.com/reports/232174) $5,000 |
| 13 | Test **double encoding** against WAFs | [Starbucks #716761](https://hackerone.com/reports/716761) |
| 14 | Test **mXSS** against DOMPurify/sanitisers | — |
| 15 | Test **CSP** — find JSONP endpoints and allowlisted libraries | Lesson 06 §6 |
| 16 | Escalate XSS: check **cookie flags** (`HttpOnly`) | Lesson 06 §5 |
| 17 | Escalate: hunt a **password change** form on the same origin | Lesson 06 §5 |
| 18 | Escalate: hunt an **email change** → password reset to your inbox | Lesson 06 §5 |
| 19 | Escalate: steal a **CSRF token** from the DOM, then act | [InnoGames #604120](https://hackerone.com/reports/604120) $1,100 |
| 20 | Escalate: **cookie manipulation + XSS → ATO** | [Grammarly #534450](https://hackerone.com/reports/534450) $2,000 |
| 21 | Learn **CSRF**: which state-changing endpoints lack a token | — |
| 22 | Test CSRF **SameSite bypasses** — GET-based, top-level navigation, subdomain | — |
| 23 | Learn **CORS** misconfig: reflect `Origin`, `null` origin, wildcard + credentials | — |
| 24 | Test CORS on **every** API endpoint, not just the one in the docs | — |
| 25 | Learn **prototype pollution** — client-side and server-side | — |
| 26 | Learn **DOM clobbering** — overwrite globals with HTML | — |
| 27 | Test **clickjacking** — missing `X-Frame-Options` / `frame-ancestors` | — |
| 28 | Test **dangling markup** injection for data exfil without script | — |
| 29 | Learn **self-XSS is not a bug** — you need a delivery mechanism | Lesson 06 §8 |
| 30 | **Live rep:** Juice Shop — stored XSS → check cookie flags → drive password change | Lesson 06 §9 |

---

## 7. Injection

| # | Step | Source |
|---|---|---|
| 1 | Learn **SQLi** classes: in-band, blind boolean, blind time, error-based, OOB | — |
| 2 | Test quote-break on every parameter: `'`, `"`, `\`, backtick | — |
| 3 | Learn **error-based** first — the fastest confirmation | — |
| 4 | Learn **boolean-based** blind (`AND 1=1` vs `AND 1=2`) | — |
| 5 | Learn **time-based** blind (`SLEEP`, `pg_sleep`, `WAITFOR DELAY`) | — |
| 6 | Learn **DBMS fingerprinting** so you pick the right payload | — |
| 7 | Learn **WAF bypass** for SQLi: comments, case, encoding, whitespace alternatives | — |
| 8 | Test SQLi in **non-obvious** places: headers, cookies, JSON, sort/order params | — |
| 9 | Test **second-order** SQLi — stored then executed elsewhere | — |
| 10 | Learn to escalate SQLi: file read/write, stacked queries, RCE | — |
| 11 | Learn **NoSQLi** — `$ne`, `$gt`, `$where`, `$regex` operator injection | — |
| 12 | Test NoSQL auth bypass: `{"user":"admin","pass":{"$ne":null}}` | — |
| 13 | Learn **SSTI** — detect with `{{7*7}}`, `${7*7}`, `<%= 7*7 %>` | — |
| 14 | Fingerprint the template engine, then pick the RCE payload | — |
| 15 | Test SSTI in **every** templated field: emails, PDFs, invoices, names | — |
| 16 | Learn **command injection** — `;`, `|`, `&&`, `$(...)`, backticks | — |
| 17 | Learn **blind command injection** — OOB DNS/HTTP callbacks, timing | — |
| 18 | Test command injection in **filename** parameters and export features | — |
| 19 | Learn **XXE** — `<!ENTITY>` file read, OOB exfil, SSRF via XXE | — |
| 20 | Test XXE in every XML parser: SOAP, SAML, SVG, DOCX/XLSX upload | — |
| 21 | Learn **XXE via file upload** — unzip an Office file, inject in `document.xml` | — |
| 22 | Learn **LDAP injection** — `*`, `)(`, filter break-out | — |
| 23 | Learn **XPath injection** | — |
| 24 | Learn **CRLF injection** — header splitting, response splitting | — |
| 25 | Learn **deserialization** — Java, PHP, Python, .NET gadget chains | — |
| 26 | Test deserialization in cookies, view state, cache keys, API bodies | — |
| 27 | Learn **expression language injection** (Spring EL, OGNL) | — |
| 28 | Test **log injection / log forging** | — |
| 29 | Learn **template/format string** injection in export and report features | — |
| 30 | **Live rep:** complete one SQLi lab blind (time-based) with no output at all | — |

---

## 8. Caching & Infrastructure

| # | Step | Source |
|---|---|---|
| 1 | Learn how a cache decides what to store: cache keys and unkeyed inputs | [Lesson 07 §3](07-Cache-Poisoning-Deception.md) |
| 2 | Find the cache: `X-Cache`, `Age`, `CF-Cache-Status`, `X-Served-By` | Lesson 07 §3 |
| 3 | Learn **web cache poisoning** — inject into an unkeyed input, poison the entry | Lesson 07 §1 |
| 4 | Learn the classic: **unkeyed header** → XSS for every visitor | [PayPal #488147](https://hackerone.com/reports/488147) $18,900 |
| 5 | Test unkeyed inputs: `X-Forwarded-Host`, `X-Host`, `X-Forwarded-Scheme` | Lesson 07 §5 |
| 6 | Learn **cache deception** — trick the cache into storing a private page | Lesson 07 §4.3 |
| 7 | Test deception with path tricks: `/account/profile.css`, `/profile;.css` | Lesson 07 §4.3 |
| 8 | Learn **host header injection** — password-reset poisoning, cache poisoning | Lesson 07 §4.4 |
| 9 | Test `X-Forwarded-Host` in password-reset flows | Lesson 07 §4.4 |
| 10 | Learn **request smuggling** basics: Content-Length vs Transfer-Encoding | [Lesson 08 §3](08-Request-Smuggling.md) |
| 11 | Learn **CL.TE** and **TE.CL** desync | Lesson 08 §4.1–4.2 |
| 12 | Learn **TE.TE** obfuscation — malformed Transfer-Encoding headers | Lesson 08 §4.3, §6 |
| 13 | Learn **HTTP/2 → HTTP/1.1 downgrade** smuggling | Lesson 08 §4.4 |
| 14 | Learn **H2.CL / H2.TE** desync | Lesson 08 §4.4 |
| 15 | Test smuggling only where authorized — it can break the backend | Lesson 08 §8 |
| 16 | Learn **response queue poisoning** | Lesson 08 §7 |
| 17 | Learn **HTTP request tunnelling** | Lesson 08 §12 |
| 18 | Learn **CL.0** desync | Lesson 08 §3 |
| 19 | Test **CORS + cache** interaction | Lesson 07 §6 |
| 20 | Test **CDN-specific** behaviours (Cloudflare, Akamai, Fastly quirks) | Lesson 07 §5, Lesson 08 §6 |
| 21 | Learn **WAF fingerprinting** and per-WAF bypass notes | Lesson 08 §6 |
| 22 | Test **rate limiting** at the edge vs origin — find the bypass | — |
| 23 | Learn **HTTP/2** features that create bugs: multiplexing, pseudo-headers | Lesson 08 §3 |
| 24 | Test **hop-by-hop header** handling | — |
| 25 | Test **absolute-URI** request lines | — |
| 26 | Learn **domain fronting / SNI confusion** | — |
| 27 | Learn **subdomain takeover** mechanics: dangling CNAMEs | — |
| 28 | Automate takeover checks across all resolved hosts | — |
| 29 | Learn **DNS rebinding** and its SSRF applications | Lesson 03 §9 |
| 30 | **Live rep:** poison a cache in a lab so a header change persists for the next visitor | Lesson 07 §10 |

---

## 9. File Handling

| # | Step | Source |
|---|---|---|
| 1 | Map every upload: avatar, attachment, import, invoice, document | — |
| 2 | Learn **extension bypasses**: `.php5`, `.phtml`, `.pHp`, trailing dot/space | — |
| 3 | Learn **content-type bypass** — send `image/png` for a PHP file | — |
| 4 | Learn **magic byte** bypass — prepend `GIF89a;` | — |
| 5 | Learn **.htaccess** / `web.config` upload tricks | — |
| 6 | Test **filename injection** — path traversal in the name | — |
| 7 | Test **double extension** — `shell.php.jpg` | — |
| 8 | Test **null byte** truncation where applicable | — |
| 9 | Test **SVG upload** → stored XSS | Lesson 06 §6 |
| 10 | Test **HTML upload** → stored XSS on the same origin | — |
| 11 | Test **polyglot files** — valid image *and* valid script | — |
| 12 | Test where the file is served from — same origin? a CDN? | — |
| 13 | Learn **archive extraction** attacks: zip-slip, tar traversal | — |
| 14 | Test **ZIP bomb** (carefully, with permission) | — |
| 15 | Test **symlink** entries in archives | — |
| 16 | Test **import pipelines** for object-ID injection | [GitLab #743953](https://hackerone.com/reports/743953) $20,000 |
| 17 | Test **filename collision** races in imports | [GitLab #214028](https://hackerone.com/reports/214028) |
| 18 | Learn **XXE via Office/XML upload** | [Injection §21](#7-injection) |
| 19 | Test **image processing** libraries (ImageMagick, Ghostscript) | — |
| 20 | Test **PDF generation** for SSRF and local file read | Lesson 03 §3 |
| 21 | Test **metadata** in uploaded files — EXIF injection | — |
| 22 | Learn **path traversal** in download endpoints | — |
| 23 | Test **file ID enumeration** on download routes | [DoD #1626508](https://hackerone.com/reports/1626508) |
| 24 | Test **presigned URL** abuse — scope, expiry, replay | — |
| 25 | Test **direct object storage** access (S3/GCS bucket listing) | — |
| 26 | Test **content-disposition** injection | — |
| 27 | Test **download** endpoints for authz (IDOR on files) | Lesson 01 §5 |
| 28 | Test **temp file** leakage | — |
| 29 | Test **source map** and backup file exposure (`.map`, `.bak`, `.git`) | — |
| 30 | **Live rep:** upload an SVG that executes, and a polyglot that passes both checks | — |

---

## 10. Recon & Disclosure

| # | Step | Source |
|---|---|---|
| 1 | Learn the recon pipeline: passive → active → content → crawl → secrets → fingerprint | — |
| 2 | Enumerate subdomains from **≥3 independent sources** (CT logs, brute, DNS history) | — |
| 3 | Query `crt.sh` / certificate transparency for every cert | — |
| 4 | Resolve and confirm **every** live host | — |
| 5 | Fingerprint the tech stack per host | — |
| 6 | Port-scan the live hosts | — |
| 7 | Record **WAF presence** and a rate-limit baseline before active testing | — |
| 8 | Run subdomain-takeover checks on every resolved host | — |
| 9 | Mine **wayback/CDN history** for old endpoints and params | — |
| 10 | Pull `robots.txt`, `sitemap.xml`, `security.txt` | — |
| 11 | Extract endpoints from **JS bundles** | — |
| 12 | Extract **keys and secrets** from JS bundles | — |
| 13 | Crawl with a headless browser to catch SPA routes | — |
| 14 | Fuzz directories and files | — |
| 15 | Fuzz **parameters** on every endpoint | — |
| 16 | Test **HTTP verb** tampering broadly | — |
| 17 | Test **content-type** manipulation broadly | — |
| 18 | Learn **cloud bucket** enumeration and naming patterns | — |
| 19 | Check **S3/GCS/Azure** buckets for listing and write access | — |
| 20 | Hunt **secrets in public repos** (`trufflehog`, GitHub search) | — |
| 21 | Hunt secrets in **JS, mobile apps, Docker images, CI configs** | — |
| 22 | Test **verbose errors** — stack traces, debug pages, framework banners | — |
| 23 | Test **backup/config exposure**: `.env`, `.git/`, `.svn/`, `backup.zip` | — |
| 24 | Test **actuator/debug endpoints** (Spring `/actuator`, `/debug`, `/metrics`) | — |
| 25 | Test **API docs** exposure (Swagger UI in production) | — |
| 26 | Build a **repeatable recon script** for your arsenal | — |
| 27 | Learn to **rank targets** by reward-to-effort | — |
| 28 | Learn to read a **scope document** three times before touching anything | [Profile API IDOR](https://infosecwriteups.com/finding-an-idor-in-user-profile-api-a-15-000-journey-to-critical-0f05e583c00b) $15,000 |
| 29 | Learn **ROE compliance**: rate limits, no destructive testing, disclosure terms | — |
| 30 | **Live rep:** run the full recon pipeline on one in-scope program end to end | — |

---

## Suggested category order

```
Recon (10) → Access Control (1) → Client-Side (6) → Business Logic (5)
  → API (2) → Identity (4) → Server-Side Request (3) → Injection (7)
  → File Handling (9) → Caching & Infrastructure (8)
```

**Why this order:** Recon teaches you to *find* surface. Access Control and Client-Side build the
core "change one thing, observe the delta" reflex on the highest-volume classes. Business Logic
teaches you to think about *intent*. API and Identity are where modern apps put their bugs.
Server-Side Request and Injection need supporting infrastructure knowledge. Caching &
Infrastructure is last because it's the most likely to break things and needs the most care.

## Cross-category threads

The real transferable knowledge — principles that appear in multiple categories:

| Thread | Categories |
|---|---|
| **Authenticate ≠ authorize** — the missing check, not the broken function | 1, 2, 3 |
| **String matching vs parsing** — validation defeated by parser disagreement | 3, 4, 8 |
| **Writes pay more than reads** | 1, 2, 5 |
| **Indirection defeats allowlists** — redirect chains, re-resolution | 3, 4, 8 |
| **Undocumented surface = unaudited surface** | 1, 2, 10 |
| **The check runs before the state change** (TOCTOU) | 1, 5 |
| **A fix that adds a check isn't a fix** — retest after remediation | 5, 6 |
| **The 41st payload** — validation testing is combinatorial; persist | 4, 6 |
| **Severity is set by impact, not by class** — prove the chain | 3, 5, 6 |

---

*Every technique here is grounded in publicly disclosed reports. Where a step has a real
disclosed case, the report and bounty are cited. Steps without a citation are general practice,
not case studies — treat them as methodology, not evidence.*
