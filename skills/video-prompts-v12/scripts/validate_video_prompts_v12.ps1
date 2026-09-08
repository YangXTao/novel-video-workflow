param(
    [Parameter(Mandatory = $true)][string]$PromptDirectory,
    [Parameter(Mandatory = $true)][string]$AuditPath,
    [string]$PlanPath,
    [string]$ReportPath,
    [switch]$RequireNoBgm
)

$ErrorActionPreference = 'Stop'

function Convert-TimeToken([string]$Token) {
    $value = $Token.Trim()
    if ($value -match '^(?<m>\d{1,2}):(?<s>\d{2}(?:\.\d+)?)$') {
        return ([double]$Matches.m * 60.0) + [double]$Matches.s
    }
    if ($value -match '^\d{1,2}\.\d{2}$') { return [double]$value }
    if ($value -match '^\d+(?:\.\d+)?$') { return [double]$value }
    throw "Unsupported time token: $Token"
}

function Add-Issue($List, [string]$ShotId, [string]$Code, [string]$Message) {
    $List.Add([pscustomobject][ordered]@{ shot_id = $ShotId; code = $Code; message = $Message })
}

$promptRoot = [System.IO.Path]::GetFullPath($PromptDirectory)
$auditFile = [System.IO.Path]::GetFullPath($AuditPath)
if (-not (Test-Path -LiteralPath $promptRoot -PathType Container)) { throw "Prompt directory not found: $promptRoot" }
if (-not (Test-Path -LiteralPath $auditFile -PathType Leaf)) { throw "Compliance audit not found: $auditFile" }

$errors = [System.Collections.Generic.List[object]]::new()
$warnings = [System.Collections.Generic.List[object]]::new()
$results = [System.Collections.Generic.List[object]]::new()
$files = @(Get-ChildItem -LiteralPath $promptRoot -File | Where-Object { $_.Name -match '^S\d+\.txt$' } | Sort-Object Name)
if ($files.Count -eq 0) { throw "No Sxx.txt prompt files found: $promptRoot" }

$audit = Get-Content -LiteralPath $auditFile -Raw | ConvertFrom-Json
if ($audit.schema_version -ne 'video-prompt-compliance-audit-v1') { Add-Issue $errors 'GLOBAL' 'AUDIT_SCHEMA' 'Unsupported or missing compliance-audit schema.' }
if ($audit.rule_version -ne '12.6.0') { Add-Issue $errors 'GLOBAL' 'AUDIT_RULE_VERSION' 'Audit rule_version must be 12.6.0.' }
$auditByShot = @{}
foreach ($entry in @($audit.shots)) { $auditByShot[[string]$entry.shot_id] = $entry }

$planByShot = @{}
if (-not [string]::IsNullOrWhiteSpace($PlanPath)) {
    $planFile = [System.IO.Path]::GetFullPath($PlanPath)
    if (-not (Test-Path -LiteralPath $planFile -PathType Leaf)) { throw "Plan not found: $planFile" }
    $plan = Get-Content -LiteralPath $planFile -Raw | ConvertFrom-Json
    if ($plan.shots -is [System.Array]) {
        foreach ($entry in @($plan.shots)) { $planByShot[[string]$entry.shot_id] = $entry }
    }
    else {
        foreach ($property in $plan.shots.PSObject.Properties) { $planByShot[$property.Name] = $property.Value }
    }
}

$requiredChecks = @(
    'screenplay_coverage', 'p0_per_beat', 'p1_per_shot', 'p2_per_scene',
    'quality_baseline_exact', 'timeline_v126', 'dialogue_voice_and_mouth', 'continuity_and_space',
    'asset_mapping_real', 'negative_prompt_scope'
)

foreach ($file in $files) {
    $shotId = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
    $text = Get-Content -LiteralPath $file.FullName -Raw
    $headers = @('①画质基准', '②角色、场景与核心设定', '③时间轴', '④负面提示词')
    $headerPatterns = @(
        '①\s*[、·．.：:]?\s*画质基准',
        '②\s*[、·．.：:]?\s*角色\s*[、，,·]?\s*场景\s*(?:与|和|、)?\s*核心设定',
        '③\s*[、·．.：:]?\s*时间轴',
        '④\s*[、·．.：:]?\s*负面提示词'
    )
    $positions = @()
    for ($headerIndex = 0; $headerIndex -lt $headers.Count; $headerIndex++) {
        $header = $headers[$headerIndex]
        $pattern = $headerPatterns[$headerIndex]
        $count = ([regex]::Matches($text, $pattern)).Count
        if ($count -ne 1) { Add-Issue $errors $shotId 'FOUR_SECTION_COUNT' "$header must appear exactly once; actual=$count" }
        $match = [regex]::Match($text, $pattern)
        $positions += $(if ($match.Success) { $match.Index } else { -1 })
    }
    if ($positions -contains -1 -or -not ($positions[0] -lt $positions[1] -and $positions[1] -lt $positions[2] -and $positions[2] -lt $positions[3])) {
        Add-Issue $errors $shotId 'FOUR_SECTION_ORDER' 'The four required sections are missing or out of order.'
        continue
    }

    $titleMatch = [regex]::Match($text, '(?m)^\s*(?:#+\s*)?S\d+\s*(?:[（(｜|]\s*)?(?<start>\d{1,2}:\d{2}(?:\.\d+)?)\s*[—–-]\s*(?<end>\d{1,2}:\d{2}(?:\.\d+)?)')
    if (-not $titleMatch.Success) {
        Add-Issue $errors $shotId 'DECLARED_DURATION' 'The shot heading must declare an Sxx time range allowed by the mother rule.'
        continue
    }
    $declaredStart = Convert-TimeToken $titleMatch.Groups['start'].Value
    $declaredEnd = Convert-TimeToken $titleMatch.Groups['end'].Value
    $duration = [math]::Round($declaredEnd - $declaredStart, 2)
    if ($duration -le 0) { Add-Issue $errors $shotId 'DECLARED_DURATION' 'Declared duration must be positive.' }

    if ($planByShot.ContainsKey($shotId)) {
        $expected = [double]$planByShot[$shotId].target_duration_seconds
        if ([math]::Abs($duration - $expected) -gt 0.06) { Add-Issue $errors $shotId 'PLAN_DURATION_MISMATCH' "Prompt=$duration seconds; plan=$expected seconds." }
    }

    $timeline = $text.Substring($positions[2], $positions[3] - $positions[2])
    $matches = [regex]::Matches($timeline, '(?m)^\s*(?:\*+)?(?<start>\d{1,2}(?::\d{2}(?:\.\d+)?|\.\d{1,2}))\s*[—–-]\s*(?<end>\d{1,2}(?::\d{2}(?:\.\d+)?|\.\d{1,2}))\s*(?:秒)?(?:\*+)?')
    $beats = @()
    foreach ($match in $matches) {
        $beats += [pscustomobject]@{
            start = Convert-TimeToken $match.Groups['start'].Value
            end = Convert-TimeToken $match.Groups['end'].Value
        }
    }
    $recommendedBeats = [int][math]::Round($duration / 1.75)
    if ($beats.Count -eq 0) { Add-Issue $errors $shotId 'TIMELINE_MISSING' 'No parseable timeline beats were found.' }
    if ($beats.Count -gt 0) {
        if ([math]::Abs($beats[0].start) -gt 0.06) { Add-Issue $errors $shotId 'TIMELINE_START' 'Timeline must start at 0.00 seconds.' }
        for ($i = 0; $i -lt $beats.Count; $i++) {
            $beatLength = $beats[$i].end - $beats[$i].start
            if ($beatLength -lt 0.3 -or $beatLength -gt 3.0) { Add-Issue $errors $shotId 'BEAT_RANGE' "Beat $($i + 1) duration is $beatLength seconds; V12.6 requires each beat to remain within 0.3-3 seconds." }
            if ($i -gt 0 -and [math]::Abs($beats[$i].start - $beats[$i - 1].end) -gt 0.06) {
                Add-Issue $errors $shotId 'TIMELINE_CONTIGUITY' "Gap or overlap between beats $i and $($i + 1)."
            }
            if ($i -gt 0) {
                $previousLength = $beats[$i - 1].end - $beats[$i - 1].start
                $currentLength = $beats[$i].end - $beats[$i].start
                if ([math]::Abs($previousLength - $currentLength) -lt 0.01) {
                    Add-Issue $errors $shotId 'ADJACENT_EQUAL_BEATS' "Adjacent beats $i and $($i + 1) have equal duration; V12.6 requires unequal adjacent beat lengths."
                }
            }
        }
        if ([math]::Abs($beats[-1].end - $duration) -gt 0.06) { Add-Issue $errors $shotId 'TIMELINE_END' "Timeline ends at $($beats[-1].end), expected $duration." }
    }

    foreach ($line in ($timeline -split "`r?`n")) {
        if ($line -match '：[“"]' -and $line -notmatch '[【［\[].+?[｜|].+?[｜|].*?(开口|闭嘴|旁白|心声).*?[】］\]]') {
            Add-Issue $errors $shotId 'DIALOGUE_METADATA' "Dialogue lacks per-line voice/emotion/open-mouth metadata: $($line.Trim())"
        }
    }

    if ($RequireNoBgm -and $text -notmatch '禁止背景音乐！！！') { Add-Issue $errors $shotId 'NO_BGM_PROJECT_RULE' 'Project requires the exact no-BGM phrase.' }
    if ($text -match '铁律\d+|P0|P1|P2|内部参考|ZeroBlood') { Add-Issue $errors $shotId 'INTERNAL_JARGON_LEAK' 'Final prompt contains internal rule labels forbidden by V12.6.' }

    if (-not $auditByShot.ContainsKey($shotId)) {
        Add-Issue $errors $shotId 'AUDIT_MISSING_SHOT' 'Compliance audit has no entry for this shot.'
    }
    else {
        $entry = $auditByShot[$shotId]
        if ([string]::IsNullOrWhiteSpace([string]$entry.content_type)) { Add-Issue $errors $shotId 'AUDIT_CONTENT_TYPE' 'Audit content_type is required.' }
        if (@($entry.applicable_rules).Count -eq 0) { Add-Issue $errors $shotId 'AUDIT_RULES' 'Audit applicable_rules must list every fully read rule file.' }
        foreach ($name in $requiredChecks) {
            $property = $entry.checks.PSObject.Properties[$name]
            if ($null -eq $property -or $property.Value.passed -ne $true -or [string]::IsNullOrWhiteSpace([string]$property.Value.evidence)) {
                Add-Issue $errors $shotId 'AUDIT_CHECK' "Audit check '$name' must pass with non-empty evidence."
            }
        }
    }

    $results.Add([pscustomobject][ordered]@{
        shot_id = $shotId
        duration_seconds = $duration
        beat_count = $beats.Count
        recommended_beat_count = $recommendedBeats
        sha256 = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
    })
}

foreach ($auditShot in $auditByShot.Keys) {
    if ($auditShot -notin @($results.shot_id)) { Add-Issue $errors $auditShot 'AUDIT_ORPHAN_SHOT' 'Audit entry has no matching Sxx.txt file.' }
}

$report = [pscustomobject][ordered]@{
    schema_version = 'video-prompt-validation-v1'
    validator_version = '1.0.0'
    rule_version = '12.6.0'
    generated_at = (Get-Date).ToString('o')
    status = if ($errors.Count -eq 0) { 'passed' } else { 'failed' }
    prompt_directory = $promptRoot
    audit_path = $auditFile
    plan_path = if ([string]::IsNullOrWhiteSpace($PlanPath)) { $null } else { [System.IO.Path]::GetFullPath($PlanPath) }
    require_no_bgm = [bool]$RequireNoBgm
    shots = @($results)
    errors = @($errors)
    warnings = @($warnings)
}

if ([string]::IsNullOrWhiteSpace($ReportPath)) { $ReportPath = Join-Path $promptRoot 'video_prompt_validation.json' }
$reportFile = [System.IO.Path]::GetFullPath($ReportPath)
$report | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $reportFile -Encoding utf8
Write-Output "REPORT=$reportFile STATUS=$($report.status) ERRORS=$($errors.Count) WARNINGS=$($warnings.Count)"
foreach ($item in $errors) { Write-Output "ERROR [$($item.shot_id)] $($item.code): $($item.message)" }
foreach ($item in $warnings) { Write-Output "WARNING [$($item.shot_id)] $($item.code): $($item.message)" }
if ($errors.Count -gt 0) { throw 'Video prompt validation failed.' }
