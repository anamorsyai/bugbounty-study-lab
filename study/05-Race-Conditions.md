# Lesson 05 — Race Conditions (limit overrun & TOCTOU)

> **Source material:** 35 disclosed HackerOne race condition reports (TOPRACECONDITION index),
> Stripe business-logic disclosure #1849626 ($5,000), YesWeHack race condition guide,
> James Kettle's *"The single-packet attack"*, PortSwigger Web Security Academy labs
> **Format:** writeup → mechanism → raw traffic → bypasses → escalation → practice
> **Status:** Lesson 5 of the study track

---

## 1. The one-line definition

**A race condition is a check that runs *before* the thing it's supposed to protect — so two
requests both pass the check before either one changes the state.**

The canonical shape, in pseudocode:

```python
if not coupon_already_used(user, code):   # ← CHECK
    apply_discount(user, code)            # ← then ACT
    mark_coupon_used(user, code)
```

Send that request 30 times **simultaneously** and all 30 pass the check, because none of them has
written `mark_coupon_used` yet. One coupon, 30 discounts.

**This is TOCTOU** — Time Of Check to Time Of Use. The window between the two lines is the bug.

**Why it pays:** every application has limits. "One per user." "One use per code." "One account
per invite." "You can't review twice." A race condition **deletes the limit** — and when the limit
guards money, that's a double-spend.

---

## 2. Real money from real race reports

From 35 disclosed HackerOne reports:

| Report | Program | Bounty | The bug |
|---|---|---|---|
| [#1849626](https://hackerone.com/reports/1849626) | **Stripe** | **$5,000** | Fee discount redeemed **30×** → $600,000 of fee-free transactions |
| [#55140](https://hackerone.com/reports/55140) | The Internet (IBB) | **$2,500** | Race in OAuth 2 → **multiple `access_token`/`refresh_token` pairs** from one authorization → authorization bypass when access should be revoked |
| [#429026](https://hackerone.com/reports/429026) | HackerOne | **$2,100** | Race in retest confirmation → **duplicated payments** |
| [#509629](https://hackerone.com/reports/509629) | InnoGames | **$2,000** | Race in email activation → **infinite diamonds** |
| [#759247](https://hackerone.com/reports/759247) | Reverb.com | **$1,500** | Gift cards redeemed multiple times → free "money" |
| [#381356](https://hackerone.com/reports/381356) | HackerOne | **$1,250** | Client-side race via Marketo → `data:` protocol in Safari |
| [#317557](https://hackerone.com/reports/317557) | Mail.ru | **$1,000** | Race on market.games.mail.ru |
| [#220445](https://hackerone.com/reports/220445) | HackerOne | **$750** | Race → **duplicate payouts** |
| [#183624](https://hackerone.com/reports/183624) | Pornhub | **$520** | Race on premium subscription |
| [#604534](https://hackerone.com/reports/604534) | HackerOne | **$500** | Race → **undeletable group member** (admin can't remove them) |
| [#176127](https://hackerone.com/reports/176127) | Shopify | **$500** | Race adding team members → **bypasses staff limit on all plans** |
| [#413759](https://hackerone.com/reports/413759) | Shopify | **$500** | Race creating Locations → bypass limit |
| [#454949](https://hackerone.com/reports/454949) | HackerOne | **$500** | Race in flag submission → duplicate points |
| [#488985](https://hackerone.com/reports/488985) | HackerOne | **$500** | Race claiming program credentials |
| [#768110](https://hackerone.com/reports/768110) | NordVPN | **$500** | **TOCTOU → local privilege escalation** |
| [#115007](https://hackerone.com/reports/115007) | Keybase | **$350** | Race bypasses **invitation limit** |
| [#148609](https://hackerone.com/reports/148609) | Keybase | **$350** | Register multiple users with **one invitation** |
| [#59179](https://hackerone.com/reports/59179) | Dropbox | **$216** | Race redeeming coupon codes |
| [#157996](https://hackerone.com/reports/157996) | Instacart | **$200** | Race redeeming coupons |
| [#165570](https://hackerone.com/reports/165570) | Slack | **$150** | Race in account survey |
| [#249319](https://hackerone.com/reports/249319) | TTS | **$150** | Race → **DoS** on Federalist API |
| [#106360](https://hackerone.com/reports/106360) | Coinbase | **$100** | Review an app multiple times |
| [#395351](https://hackerone.com/reports/395351) | Chaturbate | **$100** | Bypass subdomain limits |
| [#67562](https://hackerone.com/reports/67562) | VK.com | **$100** | Captcha implementation race |

**The biggest single payouts in the corpus aren't even web app bugs:**
[#37240](https://hackerone.com/reports/37240) and [#47227](https://hackerone.com/reports/47227)
— Adobe Flash worker races causing an **exploitable double-free** — paid **$10,000 each**.
Memory-safety races are their own league.

**Zero-dollar but instructive:** GitLab [#214028](https://hackerone.com/reports/214028) — a race
in the **import** feature caused a **filename collision**, giving one user access to **other
people's imports**. Same class as the GitLab import IDOR from Lesson 01.

---

## 3. The Stripe case — dissected

The best-documented real race condition, because HackerOne wrote it up publicly.

**Setup.** Hacker `@ian` was a real Stripe customer. Stripe Support offered him a **$20,000 fee
discount**, and his dashboard showed a prompt to accept it.

**The test.** He intercepted the "accept discount" request and used **Turbo Intruder inside Burp
Suite** to fire it many times **in parallel**.

```
He called the endpoint 30 times.
Each call applied the discount successfully.
Result: $600,000 of fee-free transactions.
```

At ~3% per transaction, each abused $20,000 discount cost Stripe about **$600**. Thirty of them
is roughly **$18,000 in direct loss** — and it was capped only by how many times he chose to send
the request.

**The part everyone misses — the first fix failed.** Stripe added a check. Ian **demonstrated the
race still worked.** Only the *second* iteration actually closed it.

> **Two lessons:** (1) an application-layer `if` check does **not** fix a race — you need a lock or
> a transaction. (2) When a program says "fixed," **retest it.** A fix that adds a check without
> adding synchronisation is still racy.

**Bounty: $5,000.** Severity was rated **Medium** — despite $600k of theoretical exposure. Worth
remembering when you're arguing severity: programs price the *class*, not your arithmetic.

---

## 4. The two exploitation techniques

### 4.1 Last-byte synchronisation (HTTP/1.1)

The older, more common method. Keep the first request **open** — send everything except the final
byte — then send the last bytes of many requests at once. The server holds all of them in a
partially-processed state, and they land together.

```
Request A: [headers + body ... █]   ← withhold last byte
Request B: [headers + body ... █]   ← withhold last byte
...
Send all final bytes in one write() → they arrive together
```

### 4.2 Single-packet attack (HTTP/2) — the modern standard

Introduced by **James Kettle** (PortSwigger), *"The single-packet attack: making remote
race-conditions 'local'."*

HTTP/2 **multiplexes** many requests over one connection. The technique: send all requests but
**deliberately withhold a small fragment of each** so the server can't process them. Then send
the final fragments **all at once, inside a single TCP packet.**

**Why it matters:** it eliminates network jitter. Without it, your 30 requests arrive spread over
milliseconds and the race window may close between them. With it, they arrive **in the same
packet** — the timing becomes effectively local. This is what turned race conditions from
"probabilistic, often unreliable" into a **dependable** bug class.

### The Turbo Intruder script

```python
def queueRequests(target, wordlists):
    # HTTP/2 target -> Engine.BURP2 triggers the single-packet attack
    # HTTP/1 only    -> use Engine.THREADED or Engine.BURP
    engine = RequestEngine(endpoint=target.endpoint,
                           concurrentConnections=10,
                           engine=Engine.BURP2)

    # the 'gate' argument withholds part of each request until openGate is invoked
    for i in range(20):
        engine.queue(target.req, gate='race1')

    # all 'race1' requests are queued -> release them in sync
    engine.openGate('race1')

def handleResponse(req, interesting):
    table.add(req)
```

**Key mechanics:**
- `engine=Engine.BURP2` → single-packet attack. `Engine.THREADED`/`Engine.BURP` → HTTP/1 fallback.
- The **`gate`** withholds each request's final fragment until `openGate`.
- **~20 requests** is the sweet spot. Some servers cap operations per connection — don't fire 10,000.

> **Diagnostic tip:** a **negative timestamp** in Turbo Intruder means the server responded
> *before* the request was complete. That's a strong signal you've hit a real timing anomaly.

### Burp Repeater alternative (no scripting)

Capture the request → **Send to Repeater** → duplicate the tab **10–15 times** → select all tabs →
right-click → **"Send group (parallel)"**. That uses the single-packet attack under the hood.
Good for a first pass; Turbo Intruder for control.

---

## 5. Where races hide — the surface map

Look for endpoints that **enforce a limit, a uniqueness constraint, or a check-before-modify**:

| Category | Concrete examples | Why it's racy |
|---|---|---|
| **Coupons / vouchers / promo codes** | apply discount, redeem code | "one use per code" is an app-layer check |
| **Gift cards / store credit** | redeem balance | classic double-spend |
| **Payments / payouts / refunds** | confirm, claim, retest | money leaves twice |
| **Currency / points / in-game items** | email activation, daily bonus, loyalty claim | "infinite diamonds" (InnoGames, $2,000) |
| **Invitations / referrals** | accept invite, register with invite | one invite → many accounts (Keybase, $350) |
| **Seat / staff / plan limits** | add team member, create location | bypasses paid-tier limits (Shopify, $500) |
| **Votes / ratings / reviews** | upvote, review an app | "one vote per user" (Coinbase, $100) |
| **Flag / answer submission** | submit flag, claim points | duplicate credit (HackerOne, $500) |
| **OTP / captcha / 2FA** | verify code | rate-limit + validation race |
| **OAuth token issuance** | authorize, refresh | **multiple token pairs** (IBB, $2,500) |
| **Import / file operations** | filename collision | one user reads another's import (GitLab) |
| **Local / OS-level** | TOCTOU on file ops | privesc (NordVPN, $500; Dirty COW) |

**The reflex question:** *"What does this endpoint claim you can only do once?"* Then ask whether
that claim is enforced by a **database constraint** (safe) or an **application-layer `if`** (racy).

---

## 6. Impact taxonomy — what races actually cause

| Impact | Description | Real example |
|---|---|---|
| **Double-spend / financial** | money, credit, or value duplicated | Stripe $5,000; Reverb $1,500 |
| **Limit bypass** | paid tiers, invite limits, quotas | Shopify $500; Keybase $350 |
| **State corruption** | inconsistent data, undeletable objects | HackerOne #604534 ($500) |
| **Authorization bypass** | extra tokens, revoked access still works | IBB #55140 ($2,500) |
| **Access to others' data** | filename/ID collision across users | GitLab #214028 |
| **Privilege escalation** | TOCTOU on a privileged operation | NordVPN #500; Dirty COW |
| **DoS** | resource exhaustion from concurrent ops | TTS #249319 ($150) |

**Severity reality:** most web races land **Medium–High** and pay **$100–$2,500**. The Stripe case
was rated **Medium** despite $600k exposure. **Memory-safety races pay far more** — Flash
double-frees were **$10,000** each.

---

## 7. Real-world CVEs worth studying

| CVE | What it was |
|---|---|
| **CVE-2022-4037** | Race in **GitLab CE/EE** → **verified email forgery** → takeover of third-party accounts when GitLab is used as an **OAuth provider**. Cross-links to Lesson 04. |
| **CVE-2024-58248** | **nopCommerce < 4.80.0** — no locking for **order placement** → **duplicate gift-card redemption**. |
| **CVE-2016-5195** | **"Dirty COW"** — Linux kernel race in `mm/gup.c` (2.x–4.x before 4.8.3) → local privilege escalation via copy-on-write mishandling. |

---

## 8. How to test — methodology

```
01. Enumerate endpoints that enforce a limit / uniqueness / check-before-modify
    (use section 5's table as a checklist against the app's features)
02. For each, capture the request that performs the action
03. Ask: is the guard a DB constraint or an app-layer if?
    → DB constraint (UNIQUE index, transaction): likely safe
    → app-layer check: prime candidate
04. First pass: Burp Repeater, duplicate tab 10-15×, "Send group (parallel)"
05. If inconclusive: Turbo Intruder, Engine.BURP2 (HTTP/2), ~20 requests behind a gate
06. Watch for NEGATIVE TIMESTAMPS — server responded before request completion = timing anomaly
07. Count successes: how many of the N returned "applied/success"?
08. Verify the STATE CHANGE, not just the responses —
    balance, discount total, object count, token count
09. Check for NEGATIVE BALANCES — a negative number is proof of double-spend
10. Scale only as needed; some servers cap operations per connection
11. Document: exact request count, success count, resulting state, before/after values
12. Report with the raw parallel-send evidence and the concrete loss figure
```

**Evidence standard for the report:** the raw request, the N parallel responses, and the
**resulting state** showing the duplicated effect. Responses alone are not proof — the *state
change* is. Screenshot the balance/counter.

---

## 9. Common mistakes

- **Only testing the happy path once.** A race requires **parallel** requests — sequential requests
  will never trigger it.
- **Trusting "the app blocked it."** If the block is an `if`, it's still racy. Test harder.
- **Not retesting after a fix.** Stripe's first fix didn't work. Programs ship incomplete fixes.
- **Reporting the responses instead of the state.** "I got 30 success responses" is weaker than
  "$600,000 of discounts actually applied to my account."
- **Firing 10,000 requests.** Servers cap operations per connection; you'll get errors, not a
  race. ~20 is the sweet spot. Also: that's a DoS risk.
- **Causing real financial damage.** Use the smallest demonstrable duplication. Prove the
  mechanism, don't drain the system — and never do this outside a program that authorizes it.
- **Ignoring client-side races.** HackerOne #381356 ($1,250) was a *client-side* race — don't
  assume races only exist server-side.
- **Forgetting the TOCTOU/privesc flavour.** Local file races (NordVPN $500) are the same class
  with a different payout profile.
- **Not checking whether the guard is DB-level.** Wasting time on a UNIQUE-constrained endpoint.

---

## 10. Practice targets

| Target | Why |
|---|---|
| **PortSwigger "Limit overrun race conditions" lab** | the canonical coupon race — €1,337 jacket for **€37.62** |
| **PortSwigger other race labs** | multi-step, partial-construction, session-based races |
| **OWASP Juice Shop** | basket/coupon logic with race surfaces |
| **crAPI** | API-level limits |
| **A local e-commerce app you deploy** | give it a coupon limit, then try to break it |

**Assignment:** in the lab VM, deploy a small app (or use the PortSwigger lab) with a
"one use per coupon" rule enforced by an application-layer check. Then:

1. Confirm the check works **sequentially** (second use rejected)
2. Break it with **Burp Repeater parallel send** (10–15 tabs)
3. Break it again with **Turbo Intruder** using `Engine.BURP2` and a gate
4. Record the **state change** — the discount total, not just the responses
5. Then add a DB-level `UNIQUE` constraint and confirm the race **no longer works**

Step 5 is the one that teaches the fix. Once you've *made* a race safe, you'll recognise the
unsafe pattern on sight.

---

## 11. Key takeaways

1. **A race deletes a limit.** Find what the app says you can only do once.
2. **App-layer `if` = racy. DB constraint = safe.** Ask which one guards the endpoint.
3. **Single-packet attack (HTTP/2) made races reliable.** `Engine.BURP2` + a gate, ~20 requests.
4. **Negative timestamp = timing anomaly.** Your best diagnostic signal.
5. **Prove the STATE change, not the responses.** Balance/counter, not HTTP 200s.
6. **A fix that adds a check isn't a fix.** Stripe's first attempt failed — retest everything.
7. **Races pay Medium–High on web ($100–$2,500); memory-safety races pay $10,000+.**
8. **Don't fire thousands of requests.** ~20 works, and more is a DoS.

---

## 12. What to study next

| You learned | Study next |
|---|---|
| Limit overrun races | **Business logic / price manipulation** (the parent class) |
| TOCTOU on state | **State-machine bugs** — James Kettle's *"Smashing the State Machine"* |
| OAuth token race (IBB $2,500) | OAuth scope + token lifecycle abuse (Lesson 04) |
| Import filename collision | Archive/path handling — zip-slip, tar traversal |
| Local TOCTOU | **Memory-safety races** — double-free, use-after-free |
| HTTP/2 multiplexing | **Request smuggling** — another HTTP/2-vs-HTTP/1 desync class |

---

## 13. Reference index

| # | Report | Bounty | Class |
|---|---|---|---|
| 1 | [Stripe #1849626](https://hackerone.com/reports/1849626) | $5,000 | discount redeemed 30× |
| 2 | [IBB #55140](https://hackerone.com/reports/55140) | $2,500 | OAuth token pair duplication |
| 3 | [HackerOne #429026](https://hackerone.com/reports/429026) | $2,100 | retest → duplicated payments |
| 4 | [InnoGames #509629](https://hackerone.com/reports/509629) | $2,000 | email activation → infinite diamonds |
| 5 | [Reverb #759247](https://hackerone.com/reports/759247) | $1,500 | gift cards redeemed multiple times |
| 6 | [HackerOne #381356](https://hackerone.com/reports/381356) | $1,250 | client-side race → `data:` protocol |
| 7 | [Mail.ru #317557](https://hackerone.com/reports/317557) | $1,000 | marketplace race |
| 8 | [HackerOne #220445](https://hackerone.com/reports/220445) | $750 | duplicate payouts |
| 9 | [Pornhub #183624](https://hackerone.com/reports/183624) | $520 | premium subscription race |
| 10 | [HackerOne #604534](https://hackerone.com/reports/604534) | $500 | undeletable group member |
| 11 | [Shopify #176127](https://hackerone.com/reports/176127) | $500 | staff limit bypass |
| 12 | [Shopify #413759](https://hackerone.com/reports/413759) | $500 | location limit bypass |
| 13 | [HackerOne #454949](https://hackerone.com/reports/454949) | $500 | duplicate flag points |
| 14 | [HackerOne #488985](https://hackerone.com/reports/488985) | $500 | program credential claim |
| 15 | [NordVPN #768110](https://hackerone.com/reports/768110) | $500 | TOCTOU → local privesc |
| 16 | [Keybase #115007](https://hackerone.com/reports/115007) | $350 | invitation limit bypass |
| 17 | [Keybase #148609](https://hackerone.com/reports/148609) | $350 | one invite, many users |
| 18 | [Dropbox #59179](https://hackerone.com/reports/59179) | $216 | coupon codes |
| 19 | [Instacart #157996](https://hackerone.com/reports/157996) | $200 | coupon redemption |
| 20 | [Slack #165570](https://hackerone.com/reports/165570) | $150 | account survey |
| 21 | [TTS #249319](https://hackerone.com/reports/249319) | $150 | DoS via API race |
| 22 | [Coinbase #106360](https://hackerone.com/reports/106360) | $100 | review app multiple times |
| 23 | [Chaturbate #395351](https://hackerone.com/reports/395351) | $100 | subdomain limit bypass |
| 24 | [VK.com #67562](https://hackerone.com/reports/67562) | $100 | captcha race |
| 25 | [GitLab #214028](https://hackerone.com/reports/214028) | $0 | import filename collision |
| 26 | [Flash IBB #37240](https://hackerone.com/reports/37240) | **$10,000** | exploitable double-free |
| 27 | [Flash IBB #47227](https://hackerone.com/reports/47227) | **$10,000** | double-free via `bytearray.compress()` |
| 28 | [Flash IBB #119657](https://hackerone.com/reports/119657) | $2,000 | Flash worker race |
| 29 | Kettle, *The single-packet attack* | — | the technique that made races reliable |
| 30 | [YesWeHack race guide](https://www.yeswehack.com/learn-bug-bounty/ultimate-guide-race-condition-vulnerabilities) | — | technique + tooling reference |
| 31 | [PortSwigger race labs](https://portswigger.net/web-security/race-conditions) | — | hands-on practice |
