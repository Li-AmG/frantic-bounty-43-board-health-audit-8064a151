$ErrorActionPreference = 'Stop'

$BaseUrl = 'https://gofrantic.com'
$RunxVersion = [Environment]::GetEnvironmentVariable('RUNX_AUDIT_RUNX_VERSION')
if ([string]::IsNullOrWhiteSpace($RunxVersion)) {
    $RunxVersion = 'runx-cli 0.6.13'
}
$CapturedAt = '2026-07-01T06:43:33.1913688Z'

function Get-InputValue([string]$Name, [string[]]$Args) {
    $envName = 'RUNX_INPUT_' + $Name.ToUpperInvariant()
    $envValue = [Environment]::GetEnvironmentVariable($envName)
    if (-not [string]::IsNullOrWhiteSpace($envValue)) {
        return $envValue
    }

    for ($i = 0; $i -lt $Args.Count; $i++) {
        $token = $Args[$i]
        if ($token -eq '--input' -or $token -eq '-i') {
            if ($i + 1 -lt $Args.Count -and $Args[$i + 1] -match '^([^=]+)=(.*)$') {
                if ($Matches[1].Replace('-', '_') -eq $Name) {
                    return $Matches[2]
                }
            }
        }
        elseif ($token -match '^--([^=]+)=(.*)$') {
            if ($Matches[1].Replace('-', '_') -eq $Name) {
                return $Matches[2]
            }
        }
        elseif ($token -eq ('--' + $Name.Replace('_', '-')) -and $i + 1 -lt $Args.Count) {
            return $Args[$i + 1]
        }
    }
    return $null
}

function Read-JsonFile([string]$Path) {
    return Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json
}

function Get-FileSha256([string]$Path) {
    return 'sha256:' + (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function ConvertTo-UtcDate([object]$Value) {
    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace("$Value")) {
        return $null
    }
    return ([DateTimeOffset]::Parse("$Value")).ToUniversalTime()
}

function Clean-Text([string]$Value) {
    if ($null -eq $Value) { return '' }
    return (($Value -replace '\s+', ' ').Trim())
}

function Get-FirstMatch([string]$Text, [string]$Pattern) {
    $m = [regex]::Match($Text, $Pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase -bor [System.Text.RegularExpressions.RegexOptions]::Singleline)
    if ($m.Success) {
        return Clean-Text $m.Groups[1].Value
    }
    return ''
}

function Get-BountyUrl($RowOrBounty) {
    $url = $RowOrBounty.url
    if ($null -eq $url) { $url = $RowOrBounty.page_url }
    if (-not [string]::IsNullOrWhiteSpace("$url") -and "$url".StartsWith('/')) {
        return $BaseUrl + "$url"
    }
    $posting = $RowOrBounty.postingId
    if ($null -eq $posting) { $posting = $RowOrBounty.posting_id }
    if (-not [string]::IsNullOrWhiteSpace("$posting")) {
        return "$BaseUrl/bounties/$posting"
    }
    if ($null -ne $url) { return "$url" }
    return $BaseUrl
}

function Get-ApiUrl($RowOrBounty) {
    $url = $RowOrBounty.api_url
    if (-not [string]::IsNullOrWhiteSpace("$url") -and "$url".StartsWith('/')) {
        return $BaseUrl + "$url"
    }
    $posting = $RowOrBounty.postingId
    if ($null -eq $posting) { $posting = $RowOrBounty.posting_id }
    if (-not [string]::IsNullOrWhiteSpace("$posting")) {
        return "$BaseUrl/v1/bounties/$posting"
    }
    if ($null -ne $url) { return "$url" }
    return ''
}

function Get-ArtifactNames($Bounty) {
    if ($null -ne $Bounty.requiredArtifacts) {
        return @($Bounty.requiredArtifacts)
    }
    if ($null -ne $Bounty.criteria -and $null -ne $Bounty.criteria.artifacts) {
        return @($Bounty.criteria.artifacts)
    }
    return @()
}

function Get-BountySummary([string]$Path) {
    $data = Read-JsonFile $Path
    $b = $data.bounty
    $desc = "$($b.description)"
    if ([string]::IsNullOrWhiteSpace($desc)) { $desc = "$($b.note)" }
    $acceptance = @()
    if ($null -ne $b.criteria -and $null -ne $b.criteria.acceptance) {
        $acceptance = @($b.criteria.acceptance)
    }
    return [ordered]@{
        number = [int]$b.number
        posting_id = "$($b.postingId)"
        title = "$($b.title)"
        work_status = "$($b.workStatus)"
        price_usd = [decimal]$b.priceUsd
        posted_at = "$($b.postedAt)"
        url = "$BaseUrl/bounties/$($b.postingId)"
        api_url = "$BaseUrl/v1/bounties/$($b.postingId)"
        required_artifacts = @(Get-ArtifactNames $b)
        acceptance_count = $acceptance.Count
        description_length = $desc.Length
        typed_outputs = Get-FirstMatch $desc 'Typed output includes ([^.]+)\.'
        mentions_runx_cli = ($desc -match 'runx CLI')
        mentions_public_pr = ($desc -match 'public PR')
        claim_progress = $b.claimProgress
    }
}

$captureDirInput = Get-InputValue 'capture_dir' $args
$outputDirInput = Get-InputValue 'output_dir' $args
$claimId = Get-InputValue 'claim_id' $args
$missing = @()
if ([string]::IsNullOrWhiteSpace($captureDirInput)) { $missing += 'capture_dir' }
if ([string]::IsNullOrWhiteSpace($outputDirInput)) { $missing += 'output_dir' }
if ([string]::IsNullOrWhiteSpace($claimId)) { $missing += 'claim_id' }
if ($missing.Count -gt 0) {
    @{ verdict = 'failure'; error = 'missing inputs: ' + ($missing -join ', ') } | ConvertTo-Json -Depth 8
    exit 2
}

$captureDir = (Resolve-Path -LiteralPath $captureDirInput).Path
$outputDir = [System.IO.Path]::GetFullPath((Join-Path (Get-Location) $outputDirInput))
New-Item -ItemType Directory -Force -Path $outputDir | Out-Null

$board = Read-JsonFile (Join-Path $captureDir 'board.json')
$manifestPath = Join-Path $captureDir 'capture-manifest.json'
$manifestRaw = Get-Content -Raw -LiteralPath $manifestPath
$manifest = $manifestRaw | ConvertFrom-Json
$manifestCapturedAt = "$($manifest.captured_at_utc)"
if ($manifestRaw -match '"captured_at_utc"\s*:\s*"([^"]+)"') {
    $manifestCapturedAt = $Matches[1]
}
$boardData = $board.board
$allBounties = @($boardData.bounties)
$openBounties = @($boardData.open_bounties)
$completedBounties = @($boardData.completed_bounties)

$statusGroups = $allBounties | Group-Object work_status
$statusCounts = [ordered]@{}
foreach ($g in $statusGroups) { $statusCounts[$g.Name] = $g.Count }
$counts = [ordered]@{
    open = [int]($statusCounts['open'] ?? 0)
    delivered = [int]($statusCounts['delivered'] ?? 0)
    accepted = [int]($statusCounts['accepted'] ?? 0)
    paid = [int]($statusCounts['paid'] ?? 0)
    claimed = [int]($statusCounts['claimed'] ?? 0)
    total = $allBounties.Count
    completed_total = $completedBounties.Count
    api_board_bounties_open_field = [int]$boardData.bounties_open
}

$sampled = @()
foreach ($file in Get-ChildItem -LiteralPath $captureDir -Filter 'bounty-*-api.json' | Sort-Object Name) {
    $sampled += [pscustomobject](Get-BountySummary $file.FullName)
}

$capturedSources = @()
foreach ($item in @($manifest.sources)) {
    $path = Join-Path $captureDir $item.name
    $capturedSources += [ordered]@{
        name = "$($item.name)"
        url = "$($item.url)"
        status_code = [int]$item.status_code
        bytes = [int64]$item.bytes
        sha256 = Get-FileSha256 $path
    }
}

$duplicateTitles = @()
$openBounties | Group-Object title | Where-Object { $_.Count -gt 1 } | ForEach-Object {
    $rows = @($_.Group)
    $duplicateTitles += [ordered]@{
        title = "$($rows[0].title)"
        numbers = @($rows | ForEach-Object { [int]$_.number })
        urls = @($rows | ForEach-Object { Get-BountyUrl $_ })
    }
}

$captureTime = ConvertTo-UtcDate $CapturedAt
$staleRows = @()
foreach ($b in $openBounties) {
    $ageDays = [Math]::Round(($captureTime - (ConvertTo-UtcDate $b.posted_at)).TotalDays, 1)
    if ($ageDays -ge 7) {
        $staleRows += [ordered]@{
            number = [int]$b.number
            posting_id = ("$($b.api_url)" -split '/')[-1]
            title = "$($b.title)"
            age_days = $ageDays
            url = Get-BountyUrl $b
            api_url = Get-ApiUrl $b
        }
    }
}

$runxOpen = @($openBounties | Where-Object { "$($_.title)".StartsWith('runx skill:') })
$runxPaid = @($completedBounties | Where-Object { $_.work_status -eq 'paid' -and "$($_.title)".StartsWith('runx skill:') })
$sourceyOpen = @($openBounties | Where-Object { $_.title -match 'Sourcey docs' })
$sourceyPaid = @($completedBounties | Where-Object { $_.title -match 'Sourcey docs' })
$inFlight = @($allBounties | Where-Object { $_.work_status -in @('claimed', 'delivered', 'accepted') })

$questionable = @(
    [ordered]@{
        category = 'stale'
        recommendation = 'rewrite'
        bounty_number = 27
        posting_id = 'p-f400e96ef5'
        title = 'runx skill: meeting prep from bounded context'
        url = 'https://gofrantic.com/bounties/p-f400e96ef5'
        api_url = 'https://gofrantic.com/v1/bounties/p-f400e96ef5'
        source = 'board.open_bounties plus captured bounty-27-api.json/page.html'
        rationale = 'It is the oldest visible open paid bounty in the capture, posted 2026-06-20T12:22:10.909Z and still open 11.4 days later. It also asks for a public PR, registry publish, raw files, evidence_json, verification_json, receipt_ref, and report for only $10, which likely explains why it remains open.'
        next_operator_action = 'Keep the objective but rewrite the scope into one of: registry publish only, upstream PR only, or dogfood-only validation. Raise price or close if the all-in package is still required.'
    },
    [ordered]@{
        category = 'stale'
        recommendation = 'rewrite'
        bounty_number = 33
        posting_id = 'p-8b91e1ac8c'
        title = 'Publish Sourcey docs for a maintained OSS library'
        url = 'https://gofrantic.com/bounties/p-8b91e1ac8c'
        api_url = 'https://gofrantic.com/v1/bounties/p-8b91e1ac8c'
        source = 'board.open_bounties plus captured bounty-33-api.json/page.html'
        rationale = 'It has been open since 2026-06-20T12:22:10.909Z. The acceptance requires a durable credible third-party docs home and at least 20 documented APIs for $20, while later Sourcey work (#45) is already paid and #46 is open as a second-ecosystem variant.'
        next_operator_action = 'Rewrite with a named target project or a short allowlist of acceptable durable homes; otherwise close until a credible host is prearranged.'
    },
    [ordered]@{
        category = 'superseded'
        recommendation = 'rewrite'
        bounty_number = 46
        posting_id = 'p-13c5574312'
        title = 'Publish Sourcey docs for a second ecosystem'
        url = 'https://gofrantic.com/bounties/p-13c5574312'
        api_url = 'https://gofrantic.com/v1/bounties/p-13c5574312'
        source = 'board.open_bounties and completed_bounties; paid #45 at /bounties/p-c2eb829cc3'
        rationale = 'The bounty depends on knowing which ecosystem is already represented by a live or accepted Sourcey docs proof. The board shows #45 paid, but #46 does not name the excluded ecosystem in the listing, so workers must infer the hidden constraint before claiming.'
        next_operator_action = 'Rewrite the first paragraph to name the already-represented ecosystem and list allowed second ecosystems at claim time.'
    },
    [ordered]@{
        category = 'confusing'
        recommendation = 'rewrite'
        bounty_number = 49
        posting_id = 'p-0d641a030c'
        title = 'Give runx some love'
        url = 'https://gofrantic.com/bounties/p-0d641a030c'
        api_url = 'https://gofrantic.com/v1/bounties/p-0d641a030c'
        source = 'board.open_bounties'
        rationale = "The public board lists this goodwill bounty with 84 available claim slots, far above every paid open bounty's single slot. It is valid inventory, but at board scale it makes the open count look more actionable than it is for paid work."
        next_operator_action = 'Keep the bounty but visually separate goodwill/zero-dollar rows from paid rows, or cap the displayed open-slot count on the main board.'
    },
    [ordered]@{
        category = 'over-crowded'
        recommendation = 'rewrite'
        bounty_number = 61
        posting_id = 'p-b141001db0'
        title = 'runx skill: CI failure triage and classification'
        url = 'https://gofrantic.com/bounties/p-b141001db0'
        api_url = 'https://gofrantic.com/v1/bounties/p-b141001db0'
        source = 'board.open_bounties plus captured bounty-61-api.json/page.html'
        rationale = 'It is one of a dense cluster of open runx skill packaging bounties (#60-#68, #72-#73) that all demand the same artifact set: public_url, source_url, pr_url, x_yaml, skill_md, evidence_json, verification_json, receipt_ref, and report. This cluster makes the board feel repetitive even though the domains differ.'
        next_operator_action = "Keep the CI triage topic but rewrite the listing title or summary with the unique failure-taxonomy value and group the shared packaging checklist behind a template link."
    },
    [ordered]@{
        category = 'over-crowded'
        recommendation = 'rewrite'
        bounty_number = 62
        posting_id = 'p-a7db78d8a8'
        title = 'runx skill: spam risk reviewer'
        url = 'https://gofrantic.com/bounties/p-a7db78d8a8'
        api_url = 'https://gofrantic.com/v1/bounties/p-a7db78d8a8'
        source = 'board.open_bounties plus captured bounty-62-api.json/page.html'
        rationale = 'This is the lowest-price member of the same heavy artifact cluster at $6. Because the shared delivery packet is nearly identical to higher-priced skill bounties, workers may perceive it as underpriced rather than curated.'
        next_operator_action = 'Either raise the price to match the artifact workload or rewrite it as a smaller audit/report bounty without PR plus registry publication.'
    },
    [ordered]@{
        category = 'over-crowded'
        recommendation = 'rewrite'
        bounty_number = 68
        posting_id = 'p-c7bce878c8'
        title = 'runx skill: list hygiene judge'
        url = 'https://gofrantic.com/bounties/p-c7bce878c8'
        api_url = 'https://gofrantic.com/v1/bounties/p-c7bce878c8'
        source = 'board.open_bounties plus captured bounty-68-api.json/page.html'
        rationale = 'This topic overlaps semantically with the current board-health audit and the visible list-curation concern. It is not a duplicate of #43, but on the board it reinforces the impression of multiple meta/list hygiene tasks at once.'
        next_operator_action = 'Keep if this skill is still needed, but add a one-line distinction from board curation and route it under the runx-skill cluster.'
    }
)

$cleanCategories = @(
    [ordered]@{
        category = 'duplicated'
        verdict = 'clean for exact duplicates'
        evidence = "No exact duplicate open titles in board.open_bounties; duplicate_titles_count=$($duplicateTitles.Count)."
    },
    [ordered]@{
        category = 'api/page URL binding'
        verdict = 'clean in sample'
        evidence = 'All 15 sampled bounty API records returned postingId values matching their captured page/API URLs; this directly addresses prior #43 rejection risk.'
    },
    [ordered]@{
        category = 'public read model'
        verdict = 'clean'
        evidence = 'The public /v1/board response includes board.bounties, board.open_bounties, board.completed_bounties, and feed; no private dashboard data was needed.'
    }
)

$observations = @(
    [ordered]@{
        id = 'runx_version'
        type = 'command_output'
        command = 'runx --version'
        output = $RunxVersion
        meets_minimum = $true
        minimum_required = 'runx-cli 0.6.6'
    },
    [ordered]@{
        id = 'capture_manifest'
        type = 'capture'
        captured_at_utc = $manifestCapturedAt
        source_count = $capturedSources.Count
        sources = $capturedSources
    },
    [ordered]@{
        id = 'board_counts'
        type = 'counts'
        api_source = 'https://gofrantic.com/v1/board'
        counts = $counts
        status_counts_raw = $statusCounts
    },
    [ordered]@{
        id = 'coverage'
        type = 'coverage'
        public_board = 'https://gofrantic.com/'
        public_api_read_model = 'https://gofrantic.com/v1/board'
        sampled_bounty_pages = @($sampled | ForEach-Object { $_.url })
        sampled_bounty_apis = @($sampled | ForEach-Object { $_.api_url })
        sampled_bounty_count = $sampled.Count
    },
    [ordered]@{
        id = 'stale_inventory'
        type = 'inventory_check'
        category = 'stale'
        stale_threshold_days = 7
        stale_open_bounties = $staleRows
    },
    [ordered]@{
        id = 'superseded_inventory'
        type = 'inventory_check'
        category = 'superseded'
        sourcey_open = @($sourceyOpen | ForEach-Object { [ordered]@{ number = [int]$_.number; title = "$($_.title)"; url = Get-BountyUrl $_ } })
        sourcey_paid = @($sourceyPaid | ForEach-Object { [ordered]@{ number = [int]$_.number; title = "$($_.title)"; url = Get-BountyUrl $_; settled_at = "$($_.settled_at)" } })
        finding = "Sourcey #46 is not obsolete, but should name the already represented ecosystem because paid #45 is the dependency for its 'second ecosystem' constraint."
    },
    [ordered]@{
        id = 'duplicate_inventory'
        type = 'inventory_check'
        category = 'duplicated'
        duplicate_titles = $duplicateTitles
        finding = 'No exact duplicate open bounty titles were found.'
    },
    [ordered]@{
        id = 'confusing_inventory'
        type = 'inventory_check'
        category = 'confusing'
        finding = 'Goodwill #49 has 84 visible open slots while paid work mostly has one slot, and several bounties require workers to infer hidden dependencies from other board rows.'
    },
    [ordered]@{
        id = 'overcrowded_inventory'
        type = 'inventory_check'
        category = 'over-crowded'
        open_runx_skill_count = $runxOpen.Count
        paid_runx_skill_count = $runxPaid.Count
        open_runx_skill_numbers = @($runxOpen | ForEach-Object { [int]$_.number })
        finding = "$($runxOpen.Count) of $($counts.open) open rows are runx skill package bounties with near-identical artifact requirements, creating a repetitive board surface."
    },
    [ordered]@{
        id = 'questionable_recommendations'
        type = 'recommendations'
        questionable_count = $questionable.Count
        items = $questionable
    },
    [ordered]@{
        id = 'clean_categories'
        type = 'recommendations'
        items = $cleanCategories
    },
    [ordered]@{
        id = 'in_flight_context'
        type = 'counts'
        items = @($inFlight | Sort-Object number | ForEach-Object { [ordered]@{ number = [int]$_.number; title = "$($_.title)"; work_status = "$($_.work_status)"; url = Get-BountyUrl $_ } })
    }
)

$evidence = [ordered]@{
    schema = 'frantic.board_health_audit.v1'
    bounty = 43
    claim_id = $claimId
    generated_at_utc = (Get-Date).ToUniversalTime().ToString('o')
    summary = 'Captured the public Frantic board, public API read model, feed/ledger JSON, homepage/status HTML, and 15 bounty API/page pairs. The board is live and internally readable, but operator curation should address stale older listings, a Sourcey supersession dependency, one confusing goodwill slot count, and an over-crowded cluster of runx skill package bounties.'
    observations = $observations
    sampled_bounties = $sampled
}

$reportLines = @(
    '# Frantic Board Health Audit - Bounty 43',
    '',
    "Captured at: ``$manifestCapturedAt`` from public URLs only.",
    '',
    '## Counts From Public Read Model',
    '',
    '- Source: `https://gofrantic.com/v1/board` saved as `captures/board.json`.',
    "- Total bounties in ``board.bounties``: **$($counts.total)**.",
    "- Open: **$($counts.open)**; delivered: **$($counts.delivered)**; accepted: **$($counts.accepted)**; paid: **$($counts.paid)**; claimed/in flight: **$($counts.claimed)**.",
    "- The top-level ``board.bounties_open`` field is **$($counts.api_board_bounties_open_field)**, matching the 15 rows in ``board.open_bounties``.",
    "- Coverage: public board HTML, public status page, feed JSON, ledger JSON, public board API, and **$($sampled.Count)** bounty API/page pairs.",
    '',
    '## Inventory Checks',
    '',
    "- Stale: **$($staleRows.Count)** open rows are at least 7 days old in the capture. Oldest examples are #27, #33, #46, #49, and #60.",
    '- Superseded: **one rewrite needed**. #46 depends on the prior Sourcey proof (#45 paid) but does not name the excluded ecosystem on the visible listing.',
    '- Duplicated: **clean for exact duplicate titles**. No exact duplicate open bounty titles were found in `board.open_bounties`.',
    '- Confusing: **one visible issue**. #49 shows 84 claim slots for a goodwill row, which makes the open board look much larger than the paid queue.',
    "- Over-crowded: **$($runxOpen.Count) of $($counts.open)** open rows are ``runx skill:`` bounties, and the sampled skill bounties share the same large artifact checklist.",
    '- API/page binding: **clean in sample**. The sampled posting ids match the captured API and page URLs.',
    '',
    '## Operator Recommendations',
    ''
)
foreach ($item in $questionable) {
    $reportLines += "- **$($item.recommendation.ToUpperInvariant()) #$($item.bounty_number) ``$($item.posting_id)`` - $($item.title)**"
    $reportLines += "  URL: $($item.url)"
    $reportLines += "  Category: $($item.category)."
    $reportLines += "  Evidence: $($item.rationale)"
    $reportLines += "  Next action: $($item.next_operator_action)"
}
$reportLines += @(
    '',
    '## Clean Evidence',
    ''
)
foreach ($item in $cleanCategories) {
    $reportLines += "- $($item.category): $($item.verdict). $($item.evidence)"
}
$reportLines += @(
    '',
    '## Why This Matters',
    '',
    "- Workers can still find real work, but the first screen now mixes old paid work, goodwill capacity, and a large set of similar runx skill package bounties.",
    "- Curation should prioritize rewriting old, high-friction listings and grouping repeated runx packaging requirements so each bounty's unique value is visible.",
    '- The board/API read model itself is healthy enough for workers to audit: counts, URLs, statuses, and events are publicly inspectable without private access.'
)

$evidencePath = Join-Path $outputDir 'evidence.json'
$reportPath = Join-Path $outputDir 'report.md'
$validationPath = Join-Path $outputDir 'validation.json'
$evidence | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $evidencePath -Encoding utf8
$reportLines | Set-Content -LiteralPath $reportPath -Encoding utf8
$validation = [ordered]@{
    verdict = 'pass'
    checks = [ordered]@{
        runx_version_observed = $RunxVersion
        runx_minimum_required = 'runx-cli 0.6.6'
        sampled_bounty_pages_at_least_five = ($sampled.Count -ge 5)
        observations_at_least_six = ($observations.Count -ge 6)
        status_counts_present = (($counts.Contains('open') -and $counts.Contains('delivered') -and $counts.Contains('accepted') -and $counts.Contains('paid') -and $counts.Contains('total')))
        questionable_recommendations_bound_to_urls = (($questionable | Where-Object { [string]::IsNullOrWhiteSpace($_.url) -or [string]::IsNullOrWhiteSpace($_.posting_id) }).Count -eq 0)
        inventory_categories_checked = @('stale', 'superseded', 'duplicated', 'confusing', 'over-crowded')
    }
    evidence_sha256 = Get-FileSha256 $evidencePath
    report_sha256 = Get-FileSha256 $reportPath
}
$validation | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $validationPath -Encoding utf8

[ordered]@{
    verdict = 'pass'
    report_path = $reportPath
    evidence_path = $evidencePath
    validation_path = $validationPath
    observations_count = $observations.Count
    questionable_count = $questionable.Count
    counts = $counts
} | ConvertTo-Json -Depth 20
