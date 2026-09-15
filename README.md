# bugbounty-study-lab

A study track for bug bounty hunting — real disclosed writeups taught in full, plus the lab
tooling to practise them.

Everything here is sourced from **publicly disclosed reports** on HackerOne, Medium, and
security research blogs. No invented cases: every technique cites a real report with a URL and
a bounty figure where one was published. Claims that can't be sourced are labelled as general
practice rather than case study.

> **Authorized testing only.** Every technique in this repo is for bug bounty programs you're
> enrolled in, engagements you're contracted for, or labs you own. Never test a system you
> don't have explicit permission to test. Reading about how an attack works is not the same as
> firing it at someone.

---

## `study/` — the curriculum + writeup track

**[`study/CURRICULUM.md`](study/CURRICULUM.md)** is the starting point: **10 categories, 30 steps
each (300 steps)**, organized for daily learning. One step per day, ~30 days per category.

| # | Category | Focus |
|---|---|---|
| 1 | Access Control | IDOR, BOLA, BFLA, auth bypass |
| 2 | API & Protocol | GraphQL, REST, mass assignment |
| 3 | Server-Side Request | SSRF, path traversal, open redirect |
| 4 | Identity & Auth | OAuth, JWT, SAML, OTP/2FA |
| 5 | Business Logic | races, price manipulation, workflows |
| 6 | Client-Side | XSS, CSRF, CORS, postMessage |
| 7 | Injection | SQLi, NoSQLi, SSTI, cmdi, XXE |
| 8 | Caching & Infrastructure | cache poison, smuggling, host header |
| 9 | File Handling | upload, traversal, archives |
| 10 | Recon & Disclosure | subdomains, secrets, cloud storage |

### The deep lessons

One lesson per bug class, each following the same structure so the knowledge compounds:

> definition + real payout statistics → canonical raw HTTP traffic → real writeups dissected →
> where the class actually hides → bypasses → escalation ladder → test methodology →
> common mistakes → practice targets + lab assignment → key takeaways → "study next" →
> reference index with URLs and bounty figures

| # | Lesson | Class | Highest disclosed case |
|---|---|---|---|
| 01 | [IDOR / BOLA](study/01-IDOR-BOLA.md) | Access control | GitLab — **$20,000** |
| 02 | [GraphQL BOLA & Alias Abuse](study/02-GraphQL-BOLA.md) | API authorization | GitHub — **$20,000** |
| 03 | [SSRF → Cloud Metadata](study/03-SSRF-cloud-metadata.md) | SSRF / cloud | HackerOne's own platform — **Critical** |
| 04 | [OAuth Redirect-URI Bypass](study/04-OAuth-redirect-bypass.md) | OAuth / account takeover | Meta — **$24,000** |
| 05 | [Race Conditions](study/05-Race-Conditions.md) | Concurrency / logic | Stripe — **$5,000** |
| 06 | [XSS → Account Takeover](study/06-XSS.md) | Client-side | PayPal — **$20,000** |

[`study/INDEX.md`](study/INDEX.md) tracks progress and holds the cross-lesson threads
(the principles that recur across classes).

### Suggested order

**IDOR (01) → GraphQL (02) → OAuth (04) → SSRF (03)**

IDOR builds the "change one value, observe the delta" reflex. GraphQL is IDOR's most lucrative
modern surface. OAuth is the highest-paying class and reuses the same access-control thinking.
SSRF comes last because it needs the most supporting cloud/IAM knowledge.

### The recurring principles

These show up in more than one class — this is the actually transferable knowledge:

| Thread | Appears in |
|---|---|
| **Authenticate ≠ authorize** — the check that's missing, not the function that's broken | 01, 02, 03 |
| **String matching vs parsing** — validation defeated by parser disagreement | 03, 04 |
| **Writes pay more than reads** — every top bounty involved a write or delete | 01, 02 |
| **Indirection defeats allowlists** — open redirect chains, re-resolution after hops | 03, 04 |
| **Undocumented surface = unaudited surface** — hidden mutations, zombie endpoints | 01, 02 |
| **The 41st payload** — validation testing is combinatorial; persist | 04 |

---

## `lab/` — the disposable Linux lab

### `lab/vmware-alpine/`

A skill for driving a headless VMware Workstation Linux VM — start/stop/reboot, wait for SSH,
run one-off remote commands, copy files in and out, and manage snapshots.

The point is a **disposable** environment: snapshot before something destructive, revert after.
That's what makes it safe to practise exploit techniques without risking a real machine.

| File | What it is |
|---|---|
| `SKILL.md` | Environment facts, workflow, failure modes, guest inventory, agent-harness gotchas |
| `scripts/alpine.ps1` | The wrapper — `start` / `stop` / `reboot` / `status` / `shell` / `ssh` / `put` / `get` / `snapshot` / `revert` |
| `scripts/diagnose-vmware.sh` | Read-only health check for the host + VM |
| `scripts/alpine-known-good.vmx` | A known-good VMX template — restore it if a VMX gets corrupted |

**House ports** (the defaults the launcher mirrors):

| Port | Direction | Purpose |
|---|---|---|
| `9876` | `-R` guest→host | callback / reverse-shell listener |
| `3333` | `-R` guest→host | alternate callback channel |
| `8089` | `-L` host→guest | host reaches services in the guest |

**Before you use it:** update the paths in `SKILL.md` and `scripts/alpine.ps1` — the VMX path
and SSH key location are placeholders (`<your-user>`) in this repo.

**One gotcha worth knowing up front:** on Windows, `vmrun`'s stdout is not reliably captured by
PowerShell's `&` operator — it can return a bare "exit code 0" with no output. The script works
around this by redirecting to a temp file and reading it back. If you add a new `vmrun` call,
do the same, or run your checks through Git Bash.

**The failure mode that costs people an hour:** `vmrun start` returns **exit 0** but the VM
never appears in `vmrun list`, and `vmware.log` gets no new lines. Exit 0 with a stale log means
the VMX never parsed, so the hypervisor never attempted a boot. The usual cause is a VMX left in
checkpoint/suspend state. Full root-cause writeup and the fix are in `SKILL.md`.

---

## Sources

The study track draws on:

- **HackerOne disclosed reports** — individual reports are cited inline with URLs and bounty figures
- **[reddelexc/hackerone-reports](https://github.com/reddelexc/hackerone-reports)** and
  **[huynhvanphuc/hackerone-reports](https://github.com/huynhvanphuc/hackerone-reports)** —
  top disclosed reports grouped by bug type, with bounty figures
- **`thebughunter.blog`** — statistical analysis of 250 disclosed IDOR reports
- **`neodrop.ai`** — dissected real payouts with amounts
- **`securitycipher.com`**, **`ssrfpayloads.com`**, **`blog.cyberxplore.com`** — technical playbooks
- **Academic research** — Innocenti et al. (ACSAC 2023, IEEE S&P 2025), Wang et al. (Black Hat
  Asia 2019), Birch (Black Hat USA 2019), Luo et al. (IEEE S&P 2026)
- **RFC 9700** — OAuth 2.0 Security Best Current Practice (IETF, March 2025)

---

## Licence

Study notes are my own synthesis of publicly disclosed material. Quoted figures, report links,
and research citations belong to their original authors. If you're a researcher whose work is
cited here and you'd like a correction, open an issue.
