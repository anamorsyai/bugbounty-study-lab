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

## Format contract for every lesson

1. One-line definition + real payout statistics
2. Canonical raw HTTP traffic (the whole bug in six lines)
3. Real writeups dissected — endpoint, request, impact, *why it was findable*
4. Surface map — where this class actually hides (ranked by real disclosure frequency)
5. Bypasses when the obvious test fails
6. Escalation ladder — how the same bug goes from $500 to $20,000
7. Step-by-step test methodology
8. Common mistakes
9. Practice targets + a concrete assignment
10. Key takeaways + "study next" ladder
11. Reference index — every source URL cited

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

## Suggested order for a new hunter

IDOR (01) → GraphQL (02) → OAuth (04) → SSRF (03)

Reason: IDOR builds the "change one value, observe the delta" reflex. GraphQL is IDOR's most
lucrative modern surface. OAuth is the highest-paying class and uses the same access-control
thinking. SSRF last because it needs the most supporting infrastructure knowledge (cloud IAM).

## Next candidates

- Open redirect (the chain enabler behind lessons 03 and 04)
- Race conditions / TOCTOU
- JWT claim tampering + algorithm confusion
- Business logic / coupon & price manipulation
- Request smuggling (CL.TE / TE.CL)
- Cache poisoning
