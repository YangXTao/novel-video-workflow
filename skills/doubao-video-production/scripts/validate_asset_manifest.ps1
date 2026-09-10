param(
    [Parameter(Mandatory = $true)]
    [string]$ManifestPath,
    [ValidateSet('AssetsOnly', 'Production')]
    [string]$Stage = 'Production'
)

$ErrorActionPreference = 'Stop'
$errors = [System.Collections.Generic.List[string]]::new()
$warnings = [System.Collections.Generic.List[string]]::new()

if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) {
    Write-Error "Manifest not found: $ManifestPath"
    exit 2
}

try {
    $manifest = Get-Content -Raw -LiteralPath $ManifestPath | ConvertFrom-Json -Depth 100
}
catch {
    Write-Error "Invalid JSON: $($_.Exception.Message)"
    exit 2
}

if ($manifest.schema_version -ne 'novel-video-asset-manifest-v1') {
    $errors.Add("Unsupported schema_version: $($manifest.schema_version)")
}

$eligibleStatuses = @($manifest.reference_policy.eligible_statuses)
$maxImages = [int]$manifest.reference_policy.max_images_per_shot
if ($maxImages -lt 1 -or $maxImages -gt 10) { $errors.Add('Image limit must be between 1 and 10.') }
$assetProperties = @($manifest.assets.PSObject.Properties)
$assetMap = @{}

foreach ($property in $assetProperties) {
    $assetMap[$property.Name] = $property.Value
    $asset = $property.Value
    if ($eligibleStatuses -contains $asset.status) {
        if ([string]::IsNullOrWhiteSpace([string]$asset.file_path)) {
            $errors.Add("$($property.Name): eligible asset has no file_path")
            continue
        }
        if (-not (Test-Path -LiteralPath $asset.file_path -PathType Leaf)) {
            $errors.Add("$($property.Name): file missing: $($asset.file_path)")
            continue
        }
        if (-not [string]::IsNullOrWhiteSpace([string]$asset.sha256)) {
            $actualHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $asset.file_path).Hash
            if ($actualHash -ne $asset.sha256) {
                $errors.Add("$($property.Name): SHA256 mismatch")
            }
        }
    }
    elseif (-not [string]::IsNullOrWhiteSpace([string]$asset.file_path)) {
        $warnings.Add("$($property.Name): ineligible status '$($asset.status)' still has a file_path")
    }
}

$shotProperties = @()
if ($Stage -eq 'Production' -and $null -ne $manifest.shots) { $shotProperties = @($manifest.shots.PSObject.Properties) }
if ($Stage -eq 'Production' -and $shotProperties.Count -eq 0) { $errors.Add('Production requires shot bindings; assets-only input must use -Stage AssetsOnly.') }
$expectedShotNumbers = @()
if ($shotProperties.Count -gt 0) { $expectedShotNumbers = @(1..$shotProperties.Count | ForEach-Object { 'S{0:D2}' -f $_ }) }
$actualShotNumbers = @($shotProperties.Name | Sort-Object)
if (($expectedShotNumbers -join ',') -ne ($actualShotNumbers -join ',')) {
    $errors.Add("Shot IDs are not consecutive: $($actualShotNumbers -join ', ')")
}

foreach ($property in $shotProperties) {
    $shotId = $property.Name
    $shot = $property.Value
    $seen = @{}
    foreach ($assetId in @($shot.static_reference_assets)) {
        if ($seen.ContainsKey($assetId)) {
            $errors.Add("${shotId}: duplicate static asset $assetId")
            continue
        }
        $seen[$assetId] = $true
        if (-not $assetMap.ContainsKey($assetId)) {
            $errors.Add("${shotId}: unknown static asset $assetId")
            continue
        }
        $asset = $assetMap[$assetId]
        if (-not ($eligibleStatuses -contains $asset.status)) {
            $errors.Add("${shotId}: static asset $assetId has ineligible status '$($asset.status)'")
        }
    }

    foreach ($assetId in @($shot.text_only_entities)) {
        if ([string]::IsNullOrWhiteSpace([string]$assetId)) { continue }
        if (-not $assetMap.ContainsKey($assetId)) {
            $errors.Add("${shotId}: unknown text-only entity $assetId")
        }
        elseif ($seen.ContainsKey($assetId)) {
            $errors.Add("${shotId}: $assetId cannot be both static reference and text-only")
        }
    }

    $tailSlots = 0
    if ($shot.tail_frame.eligible -eq $true) {
        $tailSlots = 1
        if ([string]::IsNullOrWhiteSpace([string]$shot.tail_frame.source_shot)) {
            $errors.Add("${shotId}: eligible tail frame has no source_shot")
        }
    }
    $totalSlots = @($shot.static_reference_assets).Count + $tailSlots
    if ($totalSlots -gt $maxImages) {
        $errors.Add("${shotId}: requires $totalSlots images, exceeds limit $maxImages")
    }
}

Write-Output ("ASSETS={0} SHOTS={1} ERRORS={2} WARNINGS={3}" -f $assetProperties.Count, $shotProperties.Count, $errors.Count, $warnings.Count)
foreach ($warning in $warnings) { Write-Output "WARNING: $warning" }
foreach ($errorItem in $errors) { Write-Output "ERROR: $errorItem" }

if ($errors.Count -gt 0) { exit 1 }
exit 0
