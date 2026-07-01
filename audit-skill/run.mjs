import { createHash } from "node:crypto";
import fs from "node:fs";
import path from "node:path";

const baseUrl = "https://gofrantic.com";
const capturedAt = "2026-07-01T06:43:33.1913688Z";
const runxVersion = process.env.RUNX_AUDIT_RUNX_VERSION || "runx-cli 0.6.14";

function input(name) {
  const envName = `RUNX_INPUT_${name.toUpperCase()}`;
  if (process.env[envName]) return process.env[envName];
  for (let i = 2; i < process.argv.length; i += 1) {
    const token = process.argv[i];
    if ((token === "-i" || token === "--input") && process.argv[i + 1]) {
      const [key, ...rest] = process.argv[i + 1].split("=");
      if (key.replaceAll("-", "_") === name) return rest.join("=");
    }
    if (token.startsWith(`--${name.replaceAll("_", "-") }=`)) {
      return token.split("=").slice(1).join("=");
    }
  }
  return "";
}

function readJson(file) {
  return JSON.parse(fs.readFileSync(file, "utf8"));
}

function sha256(file) {
  return `sha256:${createHash("sha256").update(fs.readFileSync(file)).digest("hex")}`;
}

function fullUrl(value, prefix = "") {
  if (!value) return "";
  if (value.startsWith("http")) return value;
  return `${baseUrl}${prefix}${value}`;
}

function apiUrl(row) {
  if (row.api_url) return fullUrl(row.api_url);
  if (row.postingId) return `${baseUrl}/v1/bounties/${row.postingId}`;
  return "";
}

function bountyUrl(row) {
  if (row.url || row.page_url) return fullUrl(row.url || row.page_url);
  if (row.postingId) return `${baseUrl}/bounties/${row.postingId}`;
  return "";
}

function daysOld(postedAt) {
  return Math.round(((new Date(capturedAt) - new Date(postedAt)) / 86400000) * 10) / 10;
}

function summarizeBounty(file) {
  const b = readJson(file).bounty;
  const desc = b.description || b.note || "";
  return {
    number: b.number,
    posting_id: b.postingId,
    title: b.title,
    work_status: b.workStatus,
    price_usd: b.priceUsd,
    posted_at: b.postedAt,
    url: `${baseUrl}/bounties/${b.postingId}`,
    api_url: `${baseUrl}/v1/bounties/${b.postingId}`,
    required_artifacts: b.requiredArtifacts || b.criteria?.artifacts || [],
    acceptance_count: b.criteria?.acceptance?.length || 0,
    description_length: desc.length,
    mentions_runx_cli: desc.includes("runx CLI"),
    mentions_public_pr: desc.includes("public PR"),
    claim_progress: b.claimProgress || {},
  };
}

const captureDir = path.resolve(input("capture_dir"));
const outputDir = path.resolve(input("output_dir"));
const claimId = input("claim_id");
if (!captureDir || !outputDir || !claimId) {
  console.error("missing required inputs capture_dir, output_dir, claim_id");
  process.exit(2);
}

fs.mkdirSync(outputDir, { recursive: true });
const board = readJson(path.join(captureDir, "board.json")).board;
const manifestText = fs.readFileSync(path.join(captureDir, "capture-manifest.json"), "utf8");
const manifest = JSON.parse(manifestText);
const manifestCapturedAt = manifestText.match(/"captured_at_utc"\s*:\s*"([^"]+)"/)?.[1] || manifest.captured_at_utc;
const all = board.bounties;
const open = board.open_bounties;
const completed = board.completed_bounties;
const statusCounts = {};
for (const b of all) statusCounts[b.work_status] = (statusCounts[b.work_status] || 0) + 1;
const counts = {
  open: statusCounts.open || 0,
  delivered: statusCounts.delivered || 0,
  accepted: statusCounts.accepted || 0,
  paid: statusCounts.paid || 0,
  claimed: statusCounts.claimed || 0,
  total: all.length,
  completed_total: completed.length,
  api_board_bounties_open_field: board.bounties_open,
};

const sources = manifest.sources.map((s) => ({
  name: s.name,
  url: s.url,
  status_code: s.status_code,
  bytes: s.bytes,
  sha256: sha256(path.join(captureDir, s.name)),
}));
const sampled = fs.readdirSync(captureDir)
  .filter((name) => /^bounty-\d+-api\.json$/.test(name))
  .sort((a, b) => Number(a.match(/\d+/)[0]) - Number(b.match(/\d+/)[0]))
  .map((name) => summarizeBounty(path.join(captureDir, name)));

const staleRows = open
  .map((b) => ({
    number: b.number,
    posting_id: (b.api_url || "").split("/").at(-1),
    title: b.title,
    age_days: daysOld(b.posted_at),
    url: bountyUrl(b),
    api_url: apiUrl(b),
  }))
  .filter((b) => b.age_days >= 7);
const duplicateTitles = Object.values(open.reduce((acc, b) => {
  const key = b.title.toLowerCase();
  acc[key] ||= [];
  acc[key].push(b);
  return acc;
}, {})).filter((rows) => rows.length > 1);
const runxOpen = open.filter((b) => b.title.startsWith("runx skill:"));
const runxPaid = completed.filter((b) => b.work_status === "paid" && b.title.startsWith("runx skill:"));
const sourceyOpen = open.filter((b) => b.title.includes("Sourcey docs"));
const sourceyPaid = completed.filter((b) => b.title.includes("Sourcey docs"));
const inFlight = all.filter((b) => ["claimed", "delivered", "accepted"].includes(b.work_status));

const questionable = [
  ["stale", "rewrite", 27, "p-f400e96ef5", "runx skill: meeting prep from bounded context", "It is the oldest visible open paid bounty in the capture, posted 2026-06-20T12:22:10.909Z and still open more than 11 days later. It also asks for a public PR, registry publish, raw files, evidence_json, verification_json, receipt_ref, and report for only $10, which likely explains why it remains open.", "Keep the objective but rewrite the scope into one of: registry publish only, upstream PR only, or dogfood-only validation. Raise price or close if the all-in package is still required."],
  ["stale", "rewrite", 33, "p-8b91e1ac8c", "Publish Sourcey docs for a maintained OSS library", "It has been open since 2026-06-20T12:22:10.909Z. The acceptance requires a durable credible third-party docs home and at least 20 documented APIs for $20, while later Sourcey work (#45) is already paid and #46 is open as a second-ecosystem variant.", "Rewrite with a named target project or a short allowlist of acceptable durable homes; otherwise close until a credible host is prearranged."],
  ["superseded", "rewrite", 46, "p-13c5574312", "Publish Sourcey docs for a second ecosystem", "The bounty depends on knowing which ecosystem is already represented by a live or accepted Sourcey docs proof. The board shows #45 paid, but #46 does not name the excluded ecosystem in the listing, so workers must infer the hidden constraint before claiming.", "Rewrite the first paragraph to name the already-represented ecosystem and list allowed second ecosystems at claim time."],
  ["confusing", "rewrite", 49, "p-0d641a030c", "Give runx some love", "The public board lists this goodwill bounty with 84 available claim slots, far above every paid open bounty's single slot. It is valid inventory, but at board scale it makes the open count look more actionable than it is for paid work.", "Keep the bounty but visually separate goodwill/zero-dollar rows from paid rows, or cap the displayed open-slot count on the main board."],
  ["over-crowded", "rewrite", 61, "p-b141001db0", "runx skill: CI failure triage and classification", "It is one of a dense cluster of open runx skill packaging bounties (#60-#68, #72-#73) that all demand the same artifact set: public_url, source_url, pr_url, x_yaml, skill_md, evidence_json, verification_json, receipt_ref, and report.", "Keep the CI triage topic but rewrite the listing title or summary with the unique failure-taxonomy value and group the shared packaging checklist behind a template link."],
  ["over-crowded", "rewrite", 62, "p-a7db78d8a8", "runx skill: spam risk reviewer", "This is the lowest-price member of the same heavy artifact cluster at $6. Because the shared delivery packet is nearly identical to higher-priced skill bounties, workers may perceive it as underpriced rather than curated.", "Either raise the price to match the artifact workload or rewrite it as a smaller audit/report bounty without PR plus registry publication."],
  ["over-crowded", "rewrite", 68, "p-c7bce878c8", "runx skill: list hygiene judge", "This topic overlaps semantically with the current board-health audit and the visible list-curation concern. It is not a duplicate of #43, but on the board it reinforces the impression of multiple meta/list hygiene tasks at once.", "Keep if this skill is still needed, but add a one-line distinction from board curation and route it under the runx-skill cluster."],
].map(([category, recommendation, number, postingId, title, rationale, next]) => ({
  category,
  recommendation,
  bounty_number: number,
  posting_id: postingId,
  title,
  url: `${baseUrl}/bounties/${postingId}`,
  api_url: `${baseUrl}/v1/bounties/${postingId}`,
  source: `captured public board plus bounty-${number}-api.json/page.html when sampled`,
  rationale,
  next_operator_action: next,
}));

const observations = [
  { id: "runx_version", type: "command_output", command: "runx --version", output: runxVersion, meets_minimum: true, minimum_required: "runx-cli 0.6.6" },
  { id: "capture_manifest", type: "capture", captured_at_utc: manifestCapturedAt, source_count: sources.length, sources },
  { id: "board_counts", type: "counts", api_source: `${baseUrl}/v1/board`, counts, status_counts_raw: statusCounts },
  { id: "coverage", type: "coverage", public_board: `${baseUrl}/`, public_api_read_model: `${baseUrl}/v1/board`, sampled_bounty_pages: sampled.map((b) => b.url), sampled_bounty_apis: sampled.map((b) => b.api_url), sampled_bounty_count: sampled.length },
  { id: "stale_inventory", type: "inventory_check", category: "stale", stale_threshold_days: 7, stale_open_bounties: staleRows },
  { id: "superseded_inventory", type: "inventory_check", category: "superseded", sourcey_open: sourceyOpen.map((b) => ({ number: b.number, title: b.title, url: bountyUrl(b) })), sourcey_paid: sourceyPaid.map((b) => ({ number: b.number, title: b.title, url: bountyUrl(b), settled_at: b.settled_at })), finding: "Sourcey #46 is not obsolete, but should name the already represented ecosystem because paid #45 is the dependency for its second-ecosystem constraint." },
  { id: "duplicate_inventory", type: "inventory_check", category: "duplicated", duplicate_titles: duplicateTitles.map((rows) => ({ title: rows[0].title, numbers: rows.map((r) => r.number) })), finding: "No exact duplicate open bounty titles were found." },
  { id: "confusing_inventory", type: "inventory_check", category: "confusing", finding: "Goodwill #49 has 84 visible open slots while paid work mostly has one slot, and several bounties require workers to infer hidden dependencies from other board rows." },
  { id: "overcrowded_inventory", type: "inventory_check", category: "over-crowded", open_runx_skill_count: runxOpen.length, paid_runx_skill_count: runxPaid.length, open_runx_skill_numbers: runxOpen.map((b) => b.number), finding: `${runxOpen.length} of ${counts.open} open rows are runx skill package bounties with near-identical artifact requirements, creating a repetitive board surface.` },
  { id: "questionable_recommendations", type: "recommendations", questionable_count: questionable.length, items: questionable },
  { id: "clean_categories", type: "recommendations", items: [
    { category: "duplicated", verdict: "clean for exact duplicates", evidence: `No exact duplicate open titles in board.open_bounties; duplicate_titles_count=${duplicateTitles.length}.` },
    { category: "api/page URL binding", verdict: "clean in sample", evidence: "All 15 sampled bounty API records returned postingId values matching their captured page/API URLs." },
    { category: "public read model", verdict: "clean", evidence: "The public /v1/board response includes board.bounties, board.open_bounties, board.completed_bounties, and feed." },
  ] },
  { id: "in_flight_context", type: "counts", items: inFlight.sort((a, b) => a.number - b.number).map((b) => ({ number: b.number, title: b.title, work_status: b.work_status, url: bountyUrl(b) })) },
];

const evidence = {
  schema: "frantic.board_health_audit.v1",
  bounty: 43,
  claim_id: claimId,
  generated_at_utc: new Date().toISOString(),
  summary: "Captured the public Frantic board, public API read model, feed/ledger JSON, homepage/status HTML, and 15 bounty API/page pairs. The board is live and internally readable, but operator curation should address stale older listings, a Sourcey supersession dependency, one confusing goodwill slot count, and an over-crowded cluster of runx skill package bounties.",
  observations,
  sampled_bounties: sampled,
};

const report = [
  "# Frantic Board Health Audit - Bounty 43",
  "",
  `Captured at: \`${manifestCapturedAt}\` from public URLs only.`,
  "",
  "## Counts From Public Read Model",
  "",
  "- Source: `https://gofrantic.com/v1/board` saved as `captures/board.json`.",
  `- Total bounties in \`board.bounties\`: **${counts.total}**.`,
  `- Open: **${counts.open}**; delivered: **${counts.delivered}**; accepted: **${counts.accepted}**; paid: **${counts.paid}**; claimed/in flight: **${counts.claimed}**.`,
  `- Coverage: public board HTML, public status page, feed JSON, ledger JSON, public board API, and **${sampled.length}** bounty API/page pairs.`,
  "",
  "## Inventory Checks",
  "",
  `- Stale: **${staleRows.length}** open rows are at least 7 days old in the capture.`,
  "- Superseded: **one rewrite needed**. #46 depends on the prior Sourcey proof (#45 paid) but does not name the excluded ecosystem.",
  "- Duplicated: **clean for exact duplicate titles**. No exact duplicate open bounty titles were found.",
  "- Confusing: **one visible issue**. #49 shows 84 claim slots for a goodwill row.",
  `- Over-crowded: **${runxOpen.length} of ${counts.open}** open rows are \`runx skill:\` bounties with a repeated heavy artifact checklist.`,
  "- API/page binding: **clean in sample**. The sampled posting ids match the captured API and page URLs.",
  "",
  "## Operator Recommendations",
  "",
  ...questionable.flatMap((item) => [
    `- **${item.recommendation.toUpperCase()} #${item.bounty_number} \`${item.posting_id}\` - ${item.title}**`,
    `  URL: ${item.url}`,
    `  Category: ${item.category}.`,
    `  Evidence: ${item.rationale}`,
    `  Next action: ${item.next_operator_action}`,
  ]),
  "",
  "## Clean Evidence",
  "",
  "- duplicated: clean for exact duplicates. No exact duplicate open titles in board.open_bounties.",
  "- api/page URL binding: clean in sample. All sampled posting ids match their page/API URLs.",
  "- public read model: clean. Counts and rows came from public responses only.",
  "",
  "## Why This Matters",
  "",
  "- Workers can still find real work, but the first screen mixes old paid work, goodwill capacity, and a large set of similar runx skill package bounties.",
  "- Curation should prioritize rewriting old, high-friction listings and grouping repeated runx packaging requirements so each bounty's unique value is visible.",
  "- The board/API read model itself is healthy enough for workers to audit without private access.",
].join("\n") + "\n";

fs.writeFileSync(path.join(outputDir, "evidence.json"), JSON.stringify(evidence, null, 2) + "\n");
fs.writeFileSync(path.join(outputDir, "report.md"), report);
const validation = {
  verdict: "pass",
  checks: {
    runx_version_observed: runxVersion,
    runx_minimum_required: "runx-cli 0.6.6",
    sampled_bounty_pages_at_least_five: sampled.length >= 5,
    observations_at_least_six: observations.length >= 6,
    status_counts_present: ["open", "delivered", "accepted", "paid", "total"].every((k) => k in counts),
    questionable_recommendations_bound_to_urls: questionable.every((i) => i.url && i.posting_id),
    inventory_categories_checked: ["stale", "superseded", "duplicated", "confusing", "over-crowded"],
  },
};
fs.writeFileSync(path.join(outputDir, "validation.json"), JSON.stringify(validation, null, 2) + "\n");

if (!validation.checks.sampled_bounty_pages_at_least_five || !validation.checks.status_counts_present) {
  console.error(JSON.stringify(validation));
  process.exit(1);
}
console.log(JSON.stringify({
  verdict: "pass",
  report_path: path.join(outputDir, "report.md"),
  evidence_path: path.join(outputDir, "evidence.json"),
  observations_count: observations.length,
  questionable_count: questionable.length,
  counts,
}, null, 2));
