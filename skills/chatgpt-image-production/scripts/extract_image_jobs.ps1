param(
    [Parameter(Mandatory = $true)]
    [string[]]$PromptFiles,

    [Parameter(Mandatory = $true)]
    [string]$OutputPath,

    [string]$AssetRoot,
    [string]$ManifestPath
)

$ErrorActionPreference = 'Stop'

function Get-TextSha256([string]$Text) {
    # PS5.1 兼容：.NET Framework 无 [SHA256]::HashData / [Convert]::ToHexString
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { $hash = $sha.ComputeHash($bytes) } finally { $sha.Dispose() }
    return ($hash | ForEach-Object { $_.ToString('X2') }) -join ''
}

function Get-SafeFileName([string]$Value) {
    $result = $Value
    foreach ($char in [System.IO.Path]::GetInvalidFileNameChars()) {
        $result = $result.Replace([string]$char, '_')
    }
    return $result.Trim().TrimEnd('.')
}

function Normalize-Shots([string]$Value) {
    if ([string]::IsNullOrWhiteSpace($Value) -or $Value -match '^(无|不适用)$') { return @() }
    $matches = [regex]::Matches($Value, '(?i)S\s*0*(\d{1,3})')
    $shots = foreach ($match in $matches) { 'S{0:D2}' -f [int]$match.Groups[1].Value }
    return @($shots | Select-Object -Unique)
}

$manifest = $null
if (-not [string]::IsNullOrWhiteSpace($ManifestPath)) {
    if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) { throw "Manifest not found: $ManifestPath" }
    $manifest = Get-Content -Raw -LiteralPath $ManifestPath -Encoding UTF8 | ConvertFrom-Json
    if ([string]::IsNullOrWhiteSpace($AssetRoot) -and -not [string]::IsNullOrWhiteSpace([string]$manifest.asset_library_root)) {
        $AssetRoot = [string]$manifest.asset_library_root
    }
}

if ([string]::IsNullOrWhiteSpace($AssetRoot)) {
    $AssetRoot = Join-Path (Split-Path -Parent $OutputPath) '图片'
}
$AssetRoot = [System.IO.Path]::GetFullPath($AssetRoot)

$jobs = [System.Collections.Generic.List[object]]::new()
$seen = @{}
$resolvedSources = [System.Collections.Generic.List[string]]::new()

foreach ($promptFile in $PromptFiles) {
    if (-not (Test-Path -LiteralPath $promptFile -PathType Leaf)) { throw "Prompt file not found: $promptFile" }
    $resolvedFile = (Resolve-Path -LiteralPath $promptFile).Path
    $resolvedSources.Add($resolvedFile)
    $lines = @(Get-Content -LiteralPath $resolvedFile -Encoding UTF8)
    $current = $null

    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = [string]$lines[$i]
        if ($line -match '^【角色\d+｜(?<id>[^｜】]+)｜(?<name>[^｜】]+)｜') {
            $current = [pscustomobject]@{ id = $Matches.id.Trim(); name = $Matches.name.Trim(); type = 'character'; start = $i }
            continue
        }
        if ($line -match '^【道具\d+｜(?<id>[^｜】]+)｜(?<name>[^｜】]+)｜') {
            $current = [pscustomobject]@{ id = $Matches.id.Trim(); name = $Matches.name.Trim(); type = 'prop'; start = $i }
            continue
        }
        if ($line -match '^【场景\d+｜(?<name>[^｜】]+)｜(?<id>SCENE-[A-Z0-9-]+)') {
            $current = [pscustomobject]@{ id = $Matches.id.Trim(); name = $Matches.name.Trim(); type = 'scene'; start = $i }
            continue
        }

        if ($line -notmatch '^【(?:独立生图提示词|生图 Prompt)｜' -or $null -eq $current) { continue }
        if ($seen.ContainsKey($current.id)) { throw "Duplicate prompt block for asset: $($current.id)" }

        $contextLines = if ($i -gt $current.start) { @($lines[($current.start + 1)..($i - 1)]) } else { @() }
        $context = $contextLines -join "`n"
        $shots = @()
        $shotMatch = [regex]::Match($context, '【适用分镜：(?<shots>[^】]+)】')
        if ($shotMatch.Success) { $shots = @(Normalize-Shots $shotMatch.Groups['shots'].Value) }

        $promptLines = [System.Collections.Generic.List[string]]::new()
        for ($j = $i + 1; $j -lt $lines.Count; $j++) {
            $candidate = [string]$lines[$j]
            if (
                $candidate -match '^━{4,}' -or
                $candidate -match '^【资产小结】' -or
                $candidate -match '^【逐个生成顺序】' -or
                $candidate -match '^【沿用已有资产清单】' -or
                $candidate -match '^【无需建图】' -or
                $candidate -match '^本阶段到此结束' -or
                $candidate -match '^【(?:角色|场景|道具)\d+｜'
            ) { break }
            $promptLines.Add($candidate)
        }
        while ($promptLines.Count -gt 0 -and [string]::IsNullOrWhiteSpace($promptLines[0])) { $promptLines.RemoveAt(0) }
        while ($promptLines.Count -gt 0 -and [string]::IsNullOrWhiteSpace($promptLines[$promptLines.Count - 1])) { $promptLines.RemoveAt($promptLines.Count - 1) }
        $prompt = ($promptLines -join "`n")
        if ([string]::IsNullOrWhiteSpace($prompt)) { throw "Empty prompt block for asset: $($current.id)" }

        $referencePaths = [System.Collections.Generic.List[string]]::new()
        $pathMatches = [regex]::Matches($context, '(?i)[A-Z]:\\[^\r\n`|｜]+?\.(?:png|jpe?g|webp)')
        foreach ($pathMatch in $pathMatches) {
            $candidatePath = $pathMatch.Value.Trim().Trim('`')
            if (Test-Path -LiteralPath $candidatePath -PathType Leaf) { $referencePaths.Add((Resolve-Path -LiteralPath $candidatePath).Path) }
        }

        $existing = $null
        if ($null -ne $manifest -and $null -ne $manifest.assets) {
            $existingProperty = $manifest.assets.PSObject.Properties[$current.id]
            if ($null -ne $existingProperty) { $existing = $existingProperty.Value }
        }

        $safeName = Get-SafeFileName "$($current.id)-$($current.name).png"
        $targetPath = Join-Path $AssetRoot $safeName
        $action = 'generate'
        $existingStatus = if ($null -ne $existing) { [string]$existing.status } else { $null }
        if ($null -ne $existing -and -not [string]::IsNullOrWhiteSpace([string]$existing.file_path)) {
            $targetPath = [string]$existing.file_path
        }
        if ($existingStatus -in @('approved', 'reuse_approved') -and (Test-Path -LiteralPath $targetPath -PathType Leaf)) {
            if (-not [string]::IsNullOrWhiteSpace([string]$existing.sha256)) {
                $actualHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $targetPath).Hash
                if ($actualHash -ne [string]$existing.sha256) { throw "$($current.id): existing asset hash mismatch" }
            }
            $action = 'reuse'
        }
        elseif ($existingStatus -eq 'no_build') {
            throw "$($current.id): prompt exists but manifest status is no_build"
        }

        $jobs.Add([pscustomobject][ordered]@{
            asset_id = $current.id
            name = $current.name
            type = $current.type
            applicable_shots = $shots
            source_file = $resolvedFile
            prompt = $prompt
            prompt_sha256 = Get-TextSha256 $prompt
            reference_paths = @($referencePaths | Select-Object -Unique)
            action = $action
            existing_status = $existingStatus
            target_file_path = [System.IO.Path]::GetFullPath($targetPath)
        })
        $seen[$current.id] = $true
    }
}

if ($jobs.Count -eq 0) { throw 'No supported image prompt blocks were found.' }

$result = [pscustomobject][ordered]@{
    schema_version = 'chatgpt-image-jobs-v1'
    created_at = [DateTimeOffset]::Now.ToString('o')
    asset_root = $AssetRoot
    source_files = @($resolvedSources)
    jobs = @($jobs)
}
$outputDirectory = Split-Path -Parent $OutputPath
if (-not [string]::IsNullOrWhiteSpace($outputDirectory)) { [System.IO.Directory]::CreateDirectory($outputDirectory) | Out-Null }
[System.IO.File]::WriteAllText([System.IO.Path]::GetFullPath($OutputPath), ($result | ConvertTo-Json -Depth 100), [System.Text.UTF8Encoding]::new($false))
Write-Output "JOBS=$($jobs.Count) GENERATE=$(@($jobs | Where-Object action -eq 'generate').Count) REUSE=$(@($jobs | Where-Object action -eq 'reuse').Count) OUTPUT=$([System.IO.Path]::GetFullPath($OutputPath))"
