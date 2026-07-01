# Frantic Board Health Audit - Bounty 43

Captured at: `2026-07-01T06:43:33.1913688Z` from public URLs only.

## Counts From Public Read Model

- Source: `https://gofrantic.com/v1/board` saved as `captures/board.json`.
- Total bounties in `board.bounties`: **69**.
- Open: **15**; delivered: **4**; accepted: **1**; paid: **46**; claimed/in flight: **3**.
- Coverage: public board HTML, public status page, feed JSON, ledger JSON, public board API, and **15** bounty API/page pairs.

## Inventory Checks

- Stale: **5** open rows are at least 7 days old in the capture.
- Superseded: **one rewrite needed**. #46 depends on the prior Sourcey proof (#45 paid) but does not name the excluded ecosystem.
- Duplicated: **clean for exact duplicate titles**. No exact duplicate open bounty titles were found.
- Confusing: **one visible issue**. #49 shows 84 claim slots for a goodwill row.
- Over-crowded: **12 of 15** open rows are `runx skill:` bounties with a repeated heavy artifact checklist.
- API/page binding: **clean in sample**. The sampled posting ids match the captured API and page URLs.

## Operator Recommendations

- **REWRITE #27 `p-f400e96ef5` - runx skill: meeting prep from bounded context**
  URL: https://gofrantic.com/bounties/p-f400e96ef5
  Category: stale.
  Evidence: It is the oldest visible open paid bounty in the capture, posted 2026-06-20T12:22:10.909Z and still open more than 11 days later. It also asks for a public PR, registry publish, raw files, evidence_json, verification_json, receipt_ref, and report for only $10, which likely explains why it remains open.
  Next action: Keep the objective but rewrite the scope into one of: registry publish only, upstream PR only, or dogfood-only validation. Raise price or close if the all-in package is still required.
- **REWRITE #33 `p-8b91e1ac8c` - Publish Sourcey docs for a maintained OSS library**
  URL: https://gofrantic.com/bounties/p-8b91e1ac8c
  Category: stale.
  Evidence: It has been open since 2026-06-20T12:22:10.909Z. The acceptance requires a durable credible third-party docs home and at least 20 documented APIs for $20, while later Sourcey work (#45) is already paid and #46 is open as a second-ecosystem variant.
  Next action: Rewrite with a named target project or a short allowlist of acceptable durable homes; otherwise close until a credible host is prearranged.
- **REWRITE #46 `p-13c5574312` - Publish Sourcey docs for a second ecosystem**
  URL: https://gofrantic.com/bounties/p-13c5574312
  Category: superseded.
  Evidence: The bounty depends on knowing which ecosystem is already represented by a live or accepted Sourcey docs proof. The board shows #45 paid, but #46 does not name the excluded ecosystem in the listing, so workers must infer the hidden constraint before claiming.
  Next action: Rewrite the first paragraph to name the already-represented ecosystem and list allowed second ecosystems at claim time.
- **REWRITE #49 `p-0d641a030c` - Give runx some love**
  URL: https://gofrantic.com/bounties/p-0d641a030c
  Category: confusing.
  Evidence: The public board lists this goodwill bounty with 84 available claim slots, far above every paid open bounty's single slot. It is valid inventory, but at board scale it makes the open count look more actionable than it is for paid work.
  Next action: Keep the bounty but visually separate goodwill/zero-dollar rows from paid rows, or cap the displayed open-slot count on the main board.
- **REWRITE #61 `p-b141001db0` - runx skill: CI failure triage and classification**
  URL: https://gofrantic.com/bounties/p-b141001db0
  Category: over-crowded.
  Evidence: It is one of a dense cluster of open runx skill packaging bounties (#60-#68, #72-#73) that all demand the same artifact set: public_url, source_url, pr_url, x_yaml, skill_md, evidence_json, verification_json, receipt_ref, and report.
  Next action: Keep the CI triage topic but rewrite the listing title or summary with the unique failure-taxonomy value and group the shared packaging checklist behind a template link.
- **REWRITE #62 `p-a7db78d8a8` - runx skill: spam risk reviewer**
  URL: https://gofrantic.com/bounties/p-a7db78d8a8
  Category: over-crowded.
  Evidence: This is the lowest-price member of the same heavy artifact cluster at $6. Because the shared delivery packet is nearly identical to higher-priced skill bounties, workers may perceive it as underpriced rather than curated.
  Next action: Either raise the price to match the artifact workload or rewrite it as a smaller audit/report bounty without PR plus registry publication.
- **REWRITE #68 `p-c7bce878c8` - runx skill: list hygiene judge**
  URL: https://gofrantic.com/bounties/p-c7bce878c8
  Category: over-crowded.
  Evidence: This topic overlaps semantically with the current board-health audit and the visible list-curation concern. It is not a duplicate of #43, but on the board it reinforces the impression of multiple meta/list hygiene tasks at once.
  Next action: Keep if this skill is still needed, but add a one-line distinction from board curation and route it under the runx-skill cluster.

## Clean Evidence

- duplicated: clean for exact duplicates. No exact duplicate open titles in board.open_bounties.
- api/page URL binding: clean in sample. All sampled posting ids match their page/API URLs.
- public read model: clean. Counts and rows came from public responses only.

## Why This Matters

- Workers can still find real work, but the first screen mixes old paid work, goodwill capacity, and a large set of similar runx skill package bounties.
- Curation should prioritize rewriting old, high-friction listings and grouping repeated runx packaging requirements so each bounty's unique value is visible.
- The board/API read model itself is healthy enough for workers to audit without private access.
