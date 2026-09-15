# Lesson 08 — HTTP Request Smuggling (desync)

> **Source material:** top disclosed request smuggling reports from HackerOne
> (TOPREQUESTSMUGGLING index, 48 reports) — Basecamp [#1211724](https://hackerone.com/reports/1211724) ($7,500), Cloudflare [#1478633](https://hackerone.com/reports/1478633)
> ($6,000), Mail.ru [#957881](https://hackerone.com/reports/957881) ($5,000), New Relic [#498052](https://hackerone.com/reports/498052) ($3,000), Slack [#737140](https://hackerone.com/reports/737140), Zomato [#771666](https://hackerone.com/reports/771666);
> James Kettle's *"HTTP/2: The Sequel is Always Worse"*
> **Format:** writeup → mechanism → raw traffic → bypasses → escalation → practice
> **Status:** Lesson 8 of the study track
> **Category:** 8. Caching & Infrastructure — see [CURRICULUM](CURRICULUM.md#8-caching--infrastructure)

---

## 1. The one-line definition

**Two servers sit in a chain — a front-end (proxy/CDN) and a back-end. If they disagree about
where one request ends and the next begins, you can hide a second request inside the first.**

The front-end forwards **one** request; the back-end sees **two**. The extra one is yours, and it
inherits whatever trust the front-end has — it's coming from *inside*.

**Why it's the most dangerous web bug class:** you're not bypassing a check, you're **rewriting
the traffic of other users**. A successful desync lets you:

- steal other users' requests (including their **session cookies and auth tokens**)
- poison the **cache** for everyone (Lesson 07)
- bypass front-end access controls entirely
- trigger a **response queue** where victims receive *your* response and you receive *theirs*

> **Slack's [#737140](https://hackerone.com/reports/737140) was "mass account takeovers … to steal session cookies."** Zomato's stole
> `X-Access-Token` **in bulk**. New Relic's stole **passwords**. These aren't theoretical.

---

## 2. Real money from real smuggling reports

| Report | Program | Bounty | The bug |
|---|---|---|---|
| [#1211724](https://hackerone.com/reports/1211724) | Basecamp | **$7,500** | HTTP/2 request smuggling |
| [#1478633](https://hackerone.com/reports/1478633) | **Cloudflare** | **$6,000** | Transform Rules — **hex escape sequences** in `concat()` |
| [#957881](https://hackerone.com/reports/957881) | Mail.ru | **$5,000** | Request smuggling on `canpol.deti.mail.ru` |
| [#2280391](https://hackerone.com/reports/2280391) | Internet Bug Bounty | **$4,660** | Request smuggling |
| [#2327341](https://hackerone.com/reports/2327341) | Internet Bug Bounty | **$4,660** | **CVE-2024-21733** Apache Tomcat — client-side desync |
| [#2299692](https://hackerone.com/reports/2299692) | Internet Bug Bounty | **$4,660** | **CVE-2023-45648** Apache Tomcat |
| [#1575912](https://hackerone.com/reports/1575912) | **Cloudflare** | **$3,100** | Origin Rules — **newlines** in the `host_header` action |
| [#498052](https://hackerone.com/reports/498052) | New Relic | **$3,000** | **Password theft** on `login.newrelic.com` |
| [#1594627](https://hackerone.com/reports/1594627) | Internet Bug Bounty | **$2,400** | Apache `mod_proxy_ajp` |
| [#1888760](https://hackerone.com/reports/1888760) | Internet Bug Bounty | **$1,800** | Incorrect parsing of header fields |
| [#2032842](https://hackerone.com/reports/2032842) | Internet Bug Bounty | **$1,800** | **Empty headers separated by CR** |
| [#1630668](https://hackerone.com/reports/1630668) / [#1630669](https://hackerone.com/reports/1630669) / [#1630667](https://hackerone.com/reports/1630667) | Internet Bug Bounty | **$1,800** each | CVE-2022-32213 / 32214 / 32215 |
| [#867577](https://hackerone.com/reports/867577) | Basecamp | **$1,737** | **Unauthenticated** smuggling on `launchpad.37signals.com` |
| [#919175](https://hackerone.com/reports/919175) | Basecamp | **$1,700** | Smuggling → **web cache poisoning** (Lesson 07) |
| [#726773](https://hackerone.com/reports/726773) | GSA | **$750** | Smuggling on `labs.data.gov` |
| [#713285](https://hackerone.com/reports/713285) | X (Twitter) | **$560** | Smuggling in `pscp.tv` / `periscope.tv` |
| [#919988](https://hackerone.com/reports/919988) | Visma | **$500** | Smuggling on `app.workbox.dk` |
| [#694604](https://hackerone.com/reports/694604) | Lob | **$500** | Smuggling on `vpn.lob.com` |
| [#965267](https://hackerone.com/reports/965267) | Ruby | **$500** | Smuggling in `webrick` |
| [#711679](https://hackerone.com/reports/711679) | Razer | **$375** | Vulnerable `skipper` reverse proxy |
| [#1238709](https://hackerone.com/reports/1238709) | Node.js | **$250** | Space **before** the colon |
| [#1002188](https://hackerone.com/reports/1002188) | Node.js | **$250** | Potential smuggling in Node.js |
| [#1238099](https://hackerone.com/reports/1238099) | Node.js | **$250** | **Chunk extensions** ignored |

**Zero-dollar but essential reading** — the technique, not the payout:
- [Slack #737140](https://hackerone.com/reports/737140) — **mass ATO** via session-cookie theft
- [LY #740037](https://hackerone.com/reports/740037) — smuggling on an admin host → ATO
- [Zomato #771666](https://hackerone.com/reports/771666) — **bulk** `X-Access-Token` theft
- [Node.js #922597](https://hackerone.com/reports/922597) — **CR-to-hyphen conversion**
- [Node.js #735748](https://hackerone.com/reports/735748) — malformed `Transfer-Encoding`
- [QIWI #955170](https://hackerone.com/reports/955170) — smuggling → **XSS on customer sites**

**A structural observation:** the **Internet Bug Bounty** paid **$4,660** repeatedly for parser
bugs in Tomcat/Node/Apache. If you like reading source code, parser-level smuggling in open-source
servers is a steady, well-paid lane.

---

## 3. Why desync happens — the one concept

HTTP has **two** ways to specify a request body's length:

```http
Content-Length: 13          ← "the body is exactly 13 bytes"
Transfer-Encoding: chunked  ← "the body is chunked; read until the 0-length chunk"
```

**If a request has both, the spec says `Transfer-Encoding` wins and `Content-Length` must be
ignored.** Real servers disagree about this. That disagreement is the vulnerability.

```
Front-end uses Content-Length → forwards N bytes, treats the rest as a NEW request
Back-end  uses Transfer-Encoding → reads only the chunked part, then sees leftover bytes as a NEW request
```

Whichever server is "wrong" leaves a fragment of your request in the buffer, and the **next
victim request gets appended to it**. That's the desync.

### The four classic variants

| Variant | Front-end | Back-end | How it desyncs |
|---|---|---|---|
| **CL.TE** | `Content-Length` | `Transfer-Encoding` | Front-end forwards both; back-end stops early → leftover |
| **TE.CL** | `Transfer-Encoding` | `Content-Length` | Front-end reads chunked; back-end reads CL bytes → leftover |
| **TE.TE** | both honour TE | one can be **obfuscated** into ignoring it | One server dechunks, the other doesn't |
| **H2.CL / H2.TE** | HTTP/2 front-end | HTTP/1.1 back-end | Front-end downgrades; length is inferred from headers it shouldn't trust |
| **CL.0** | `Content-Length` | ignores it entirely | Body is treated as the start of the next request |

**Client-side desync (CSD)** is the newer, browser-reachable variant — Tomcat CVE-2024-21733 was
worth **$4,660**. Instead of a proxy/backend split, a single server mis-handles a crafted request
so the *browser's own connection* desyncs, and the next request the victim's browser sends gets
attached to your payload. **No proxy needed** — that's what makes CSD powerful.

---

## 4. The canonical attacks — raw traffic

### 4.1 CL.TE

```http
POST / HTTP/1.1
Host: target.com
Content-Length: 13
Transfer-Encoding: chunked

0

SMUGGLED
```

The front-end sends all 13 bytes. The back-end reads `0` + CRLF as the end of a zero-length
chunked body, and treats `SMUGGLED` as the **start of the next request**.

### 4.2 TE.CL

```http
POST / HTTP/1.1
Host: target.com
Content-Length: 3
Transfer-Encoding: chunked

8
SMUGGLED
0


```

The front-end honours `Transfer-Encoding` and forwards the chunked body. The back-end honours
`Content-Length: 3`, reads only `8\r\n`, and leaves the rest to prefix the next request.

### 4.3 TE.TE — obfuscating the header

```http
Transfer-Encoding: xchunked
Transfer-Encoding : chunked          ← space before the colon
Transfer-Encoding: chunked
Transfer-Encoding: x
Transfer-Encoding:[\x0b]chunked      ← vertical tab
Transfer-Encoding: chunked\r\nTransfer-encoding: cow
```

**At least one of the two servers fails to recognise `Transfer-Encoding` as present.** Whichever
one still dechunks desyncs against the one that doesn't.

### 4.4 H2.CL — the HTTP/2 downgrade

HTTP/2 has no `Content-Length`/`Transfer-Encoding` ambiguity — it uses a `content-length`
pseudo-header. But if the front-end **downgrades** to HTTP/1.1 for the back-end, and it copies
attacker-supplied header values into the downgraded request, you can inject a bogus length:

```
:method: POST
:path: /
content-length: 0        ← lie about the length
```

The front-end forwards a request whose real body is longer than the declared length, and the
back-end over-reads. **This is the Basecamp $7,500 shape and the Cloudflare findings.**

### 4.5 The smuggling → session-theft flow

```
1. Send a request whose "next request" prefix is:  POST /login
                                                    (or a partial request with no body yet)
2. The back-end holds the connection, waiting for the rest
3. The NEXT victim's request gets appended to your prefix
4. The victim's cookies/headers are absorbed into the request YOU started
5. You read them in the response, or they land in a log/endpoint you control
```

That's how Slack ([#737140](https://hackerone.com/reports/737140)), Zomato ([#771666](https://hackerone.com/reports/771666)) and New Relic ([#498052](https://hackerone.com/reports/498052)) stole session data,
tokens and passwords.

---

## 5. Where it hides — the surface map

**Any architecture with a proxy/backend split is a candidate:**

| Architecture | Why it desyncs |
|---|---|
| CDN → origin (Cloudflare, Akamai, Fastly) | CDN and origin parse differently |
| Load balancer → app server | LB normalises, app doesn't |
| Reverse proxy (nginx/HAProxy) → app | different TE handling |
| HTTP/2 front-end → HTTP/1.1 back-end | **the highest-yield setup** — downgrade bugs |
| Gateway → microservice | gateway validates, service trusts |
| Client → single server (**CSDS**) | one server's parser bug desyncs the browser |

**Signals you're on a candidate:**
- Different `Server` header from the proxy vs the app
- `Via:`, `X-Served-By`, `X-Cache` headers (there's a middlebox)
- HTTP/2 supported (`h2`) with an HTTP/1.1 backend
- Known proxy fingerprint (nginx, HAProxy, Varnish, Envoy, skipper)

**Tools:** Burp's **HTTP Request Smuggler** extension does the detection automatically — it's the
standard starting point. For manual work and for CSD, use **Turbo Intruder** with a desync script
(the GSA report [#726773](https://hackerone.com/reports/726773) published one: a desync request followed by 14 pipelined requests).

---

## 6. Bypasses & obfuscation

Front-ends increasingly normalise the obvious forms. The bypasses that keep working:

```
Transfer-Encoding: xchunked
Transfer-Encoding : chunked                    # space before colon
Transfer-Encoding:\tchunked                    # tab
Transfer-Encoding: chunked\r\nTransfer-Encoding: x
Transfer-Encoding:[\x0b]chunked                # vertical tab
Transfer-Encoding: chunked\x0d\x0a             # double CRLF
Transfer-Encoding: "chunked"                   # quoted
X: X\r\nTransfer-Encoding: chunked             # header folding
Content-Length: 13\r\nContent-Length: 13       # duplicate CL
Content-Length: 13, 13                         # comma-separated CL
Content-Length: +13                            # signed
Content-Length: 013                            # padded
```

**Plus:**
- **Chunk extensions** — `8;ext=1\r\n` (Node.js [#1238099](https://hackerone.com/reports/1238099), $250)
- **CR-to-hyphen conversion** — Node.js [#922597](https://hackerone.com/reports/922597) turned a CR into a hyphen, changing the parse
- **Space before colon** — Node.js [#1238709](https://hackerone.com/reports/1238709), $250
- **Empty headers separated by CR** — IBB [#2032842](https://hackerone.com/reports/2032842), $1,800
- **HTTP/2 pseudo-header abuse** — inject `\r\n` into a header value that gets downgraded
- **Cloudflare Transform/Origin Rules** — hex escapes in `concat()`, newlines in `host_header`
  (paid $6,000 and $3,100 — **the WAF itself was the vulnerable parser**)

> **The lesson from the Cloudflare findings:** the security product is a parser too. When a WAF
> or CDN lets you compose header values via a rule engine, **test whether you can smuggle a CRLF
> through it.** That's $6,000 of bug in a place nobody looks.

---

## 7. Escalation — what makes it pay

```
Smuggling detected but no impact       → Low / Informational
→ bypass front-end access control      → Medium
→ poison the cache                     → High      (Basecamp $1,700)
→ steal session cookies / tokens       → Critical  (Slack, Zomato, New Relic)
→ mass account takeover                → Critical
→ stored XSS on customer sites         → High      (QIWI #955170)
→ DoS / response queue                 → High
```

**The escalation ladder:**

1. **Detect the desync** — a timing difference between two crafted requests.
2. **Confirm the desync** — make the *next* request on the connection return a different result.
3. **Prove you control the victim's request** — inject a prefix, observe it in a subsequent response.
4. **Steal something real** — a session cookie, an `Authorization` header, an API token.
5. **Show the impact** — "I can act as any user who connects after my payload" is Critical.

> **Step 3 is the hard part and the reason most reports stall.** Detection ≠ exploitation. Burp's
> scanner flags desyncs that turn out to be unexploitable. You must show a **concrete victim
> impact**, not just a timing anomaly.

**Severity reality:** the market clearly prices this as critical-class — but note that **Slack,
Zomato and LY paid $0** for genuine mass-ATO findings (they were responsible-disclosure or
no-bounty programs at the time). **A critical bug on a no-bounty program pays nothing.** Check the
program's payout status before spending days on a desync.

---

## 8. How to test — methodology

```
01. Fingerprint the chain: different Server headers? Via/X-Cache/X-Served-By? h2 support?
02. Run Burp's HTTP Request Smuggler extension for a first pass (CL.TE, TE.CL, TE.TE, H2.*)
03. Confirm any hit MANUALLY — timing differences are notoriously noisy
04. Build the payload: smuggle a prefix that changes the NEXT request's behaviour
05. Test the obfuscation table (section 6) when the obvious form is blocked
06. For H2: check whether the front-end downgrades, and whether it trusts your content-length
07. For CSD: test from a browser context — a single-server desync needs no proxy
08. Prove victim impact: make the next request return a marker you control
09. Escalate: capture a session cookie, poison a cache, or bypass a front-end ACL
10. Be careful with the connection — a bad desync breaks the site for real users
11. Document: raw bytes of the payload, the timing evidence, and the stolen artefact
```

**⚠️ Destructive-testing warning.** Request smuggling is the class most likely to **break
production**. A mis-timed payload can corrupt the request queue for other users, and repeated
probing can hang the backend. **Only test where the program explicitly permits it**, use the
minimum number of requests, and never run it against a target outside scope. If a program
scopes out "denial of service" or "automated scanning", smuggling testing may be out of bounds
even though the bug class is in scope.

---

## 9. Common mistakes

- **Reporting a timing difference as a finding.** Detection is not exploitation. Show victim impact.
- **Not confirming manually.** Scanner false positives here are common; the tool will flag
  harmless jitter.
- **Ignoring the obfuscation table.** The obvious `Transfer-Encoding: chunked` is blocked
  everywhere. The bugs live in the malformed variants.
- **Forgetting HTTP/2.** The downgrade path (H2.CL / H2.TE) is the highest-yield modern variant —
  Basecamp's $7,500 and Cloudflare's $6,000 were both there.
- **Overlooking client-side desync.** No proxy required; a single parser bug is enough.
- **Not checking the WAF/CDN itself.** Cloudflare paid $6,000 and $3,100 for bugs *in its rule
  engine*. The security layer is a parser.
- **Breaking production.** The single best way to get banned. Minimal requests, authorized scope.
- **Not checking the program pays.** Slack and Zomato paid $0 for critical findings.
- **Missing the cache chain.** Smuggling → cache poisoning is a documented, paid escalation
  (Basecamp [#919175](https://hackerone.com/reports/919175), $1,700).

---

## 10. Practice targets

| Target | Why |
|---|---|
| **PortSwigger Request Smuggling labs** | the full progression: CL.TE, TE.CL, TE.TE, H2.CL, H2.TE, response queue poisoning, CSD |
| **A local nginx/Varnish → app stack** | configure mismatched TE handling and desync your own lab |
| **Open-source servers (Node, Tomcat, webrick)** | parser bugs are a steady IBB lane ($1,800–$4,660) |
| **Any CDN-fronted site in scope** | check for a proxy chain first |
| **WAF rule engines** | the Cloudflare findings — test CRLF through rule composition |

**Assignment:** in the lab VM, build a **deliberately desyncing stack** — nginx in front of a small
Python app, with nginx configured to honour `Content-Length` and the app configured to honour
`Transfer-Encoding` (or use a vulnerable old version of a real proxy). Then:

1. Send the CL.TE payload and observe the desync
2. Smuggle a prefix that makes the *next* request return a marker you control
3. Prove victim impact — have a "victim" request on the same connection get absorbed
4. Then **fix it** (normalise the headers at the front-end) and confirm the desync dies
5. Finally, chain it: desync into a **cacheable** endpoint and poison the cache (Lesson 07)

Steps 4 and 5 are the ones that matter — the fix teaches you what to look for, and the chain is
what turns a Medium into a High.

---

## 11. Key takeaways

1. **Two servers, two parsers, one request.** Desync is a parsing disagreement, not a broken check.
2. **`Transfer-Encoding` beats `Content-Length` per spec — but real servers disagree.**
   That disagreement is the whole bug class.
3. **Impact is critical-class:** session theft, mass ATO, cache poisoning, ACL bypass.
4. **HTTP/2 downgrade is the modern high-yield path.** Basecamp $7,500, Cloudflare $6,000.
5. **Client-side desync needs no proxy** — one parser bug is enough. Tomcat CVE-2024-21733, $4,660.
6. **The obfuscation table is the job.** Obvious TE headers are blocked; malformed ones aren't.
7. **The WAF/CDN is a parser too.** Cloudflare paid $6,000 for a bug in its own rule engine.
8. **Detection ≠ exploitation.** Prove victim impact or it's an Informational.
9. **It's the most destructive class to test.** Minimal requests, authorized scope, or don't.
10. **Critical ≠ paid.** Slack and Zomato paid $0 for genuine mass ATO.

---

## 12. What to study next

| You learned | Study next |
|---|---|
| CL/TE desync | **Cache poisoning** — the natural escalation (Lesson 07) |
| HTTP/2 downgrade | HTTP/2 protocol internals, pseudo-headers, HPACK |
| Parser bugs in servers | Source-code review as a bug class (IBB lane, $1,800–$4,660) |
| WAF rule-engine bugs | Cloudflare Workers, rule composition, template injection in rules |
| Session theft via desync | Session management, cookie scoping, token binding |
| Response queue poisoning | **Web cache deception** and response splitting |

---

## 13. Reference index

| # | Report | Bounty | Class |
|---|---|---|---|
| 1 | [Basecamp #1211724](https://hackerone.com/reports/1211724) | **$7,500** | HTTP/2 request smuggling |
| 2 | [Cloudflare #1478633](https://hackerone.com/reports/1478633) | **$6,000** | hex escapes in `concat()` |
| 3 | [Mail.ru #957881](https://hackerone.com/reports/957881) | **$5,000** | request smuggling |
| 4 | [IBB #2280391](https://hackerone.com/reports/2280391) | **$4,660** | request smuggling |
| 5 | [IBB #2327341](https://hackerone.com/reports/2327341) | **$4,660** | CVE-2024-21733 Tomcat **CSD** |
| 6 | [IBB #2299692](https://hackerone.com/reports/2299692) | **$4,660** | CVE-2023-45648 Tomcat |
| 7 | [Cloudflare #1575912](https://hackerone.com/reports/1575912) | **$3,100** | newlines in `host_header` |
| 8 | [New Relic #498052](https://hackerone.com/reports/498052) | **$3,000** | **password theft** |
| 9 | [IBB #1594627](https://hackerone.com/reports/1594627) | **$2,400** | `mod_proxy_ajp` |
| 10 | [IBB #1888760](https://hackerone.com/reports/1888760) | **$1,800** | incorrect header parsing |
| 11 | [IBB #2032842](https://hackerone.com/reports/2032842) | **$1,800** | empty headers separated by CR |
| 12 | [IBB #1630668](https://hackerone.com/reports/1630668) | **$1,800** | CVE-2022-32213 |
| 13 | [IBB #1630669](https://hackerone.com/reports/1630669) | **$1,800** | CVE-2022-32214 |
| 14 | [IBB #1630667](https://hackerone.com/reports/1630667) | **$1,800** | CVE-2022-32215 |
| 15 | [Basecamp #867577](https://hackerone.com/reports/867577) | **$1,737** | **unauthenticated** smuggling |
| 16 | [Basecamp #919175](https://hackerone.com/reports/919175) | **$1,700** | smuggling → **cache poisoning** |
| 17 | [GSA #726773](https://hackerone.com/reports/726773) | **$750** | Turbo Intruder desync script published |
| 18 | [Twitter #713285](https://hackerone.com/reports/713285) | **$560** | `pscp.tv` / `periscope.tv` |
| 19 | [Visma #919988](https://hackerone.com/reports/919988) | **$500** | `app.workbox.dk` |
| 20 | [Lob #694604](https://hackerone.com/reports/694604) | **$500** | `vpn.lob.com` |
| 21 | [Ruby #965267](https://hackerone.com/reports/965267) | **$500** | `webrick` |
| 22 | [Razer #711679](https://hackerone.com/reports/711679) | **$375** | vulnerable `skipper` proxy |
| 23 | [Node.js #1238709](https://hackerone.com/reports/1238709) | **$250** | space before colon |
| 24 | [Node.js #1002188](https://hackerone.com/reports/1002188) | **$250** | potential smuggling |
| 25 | [Node.js #1238099](https://hackerone.com/reports/1238099) | **$250** | chunk extensions ignored |
| 26 | [Slack #737140](https://hackerone.com/reports/737140) | $0 | **mass ATO** — session cookie theft |
| 27 | [LY #740037](https://hackerone.com/reports/740037) | $0 | admin host → ATO |
| 28 | [Zomato #771666](https://hackerone.com/reports/771666) | $0 | **bulk** `X-Access-Token` theft |
| 29 | [QIWI #955170](https://hackerone.com/reports/955170) | $0 | smuggling → **XSS on customer sites** |
| 30 | [Node.js #922597](https://hackerone.com/reports/922597) | $0 | **CR-to-hyphen conversion** |
| 31 | [Node.js #735748](https://hackerone.com/reports/735748) | $0 | malformed `Transfer-Encoding` |
| 32 | Kettle, *HTTP/2: The Sequel is Always Worse* | — | the H2 desync research |
