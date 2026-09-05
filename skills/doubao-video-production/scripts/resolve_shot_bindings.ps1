param(
    [Parameter(Mandatory = $true)]
    [string]$ManifestPath,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^S\d{2}$')]
    [string]$ShotId,

    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) { throw "Manifest not found: $ManifestPath" }
$manifest = Get-Content -Raw -LiteralPath $ManifestPath | ConvertFrom-Json -Depth 100
$shotProperty = $manifest.shots.PSObject.Properties[$ShotId]
if ($null -eq $shotProperty) { throw "Shot not found in manifest: $ShotId" }

$shot = $shotProperty.Value
$eligibleStatuses = @($manifest.reference_policy.eligible_statuses)
$maxImages = [int]$manifest.reference_policy.max_images_per_shot
$bindings = [System.Collections.Generic.List[object]]::new()

if ($shot.tail_frame.eligible -eq $true) {
    if ($shot.tail_frame.status -ne 'approved') {
        throw "$ShotId is blocked: tail frame from $($shot.tail_frame.source_shot) is not approved."
    }
    if ([string]::IsNullOrWhiteSpace([string]$shot.tail_frame.file_path) -or -not (Test-Path -LiteralPath $shot.tail_frame.file_path -PathType Leaf)) {
        throw "$ShotId is blocked: approved tail frame file is missing."
    }
    if (-not [string]::IsNullOrWhiteSpace([string]$shot.tail_frame.sha256)) {
        $actualTailHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $shot.tail_frame.file_path).Hash
        if ($actualTailHash -ne $shot.tail_frame.sha256) { throw "$ShotId tail frame SHA256 mismatch." }
    }
    $bindings.Add([pscustomobject]@{
        asset_id = [string]$shot.tail_frame.asset_id_when_created
        name = "$($shot.tail_frame.source_shot)尾帧"
        role = 'continuity_frame'
        file_path = [string]$shot.tail_frame.file_path
    })
}

foreach ($assetId in @($shot.static_reference_assets)) {
    $assetProperty = $manifest.assets.PSObject.Properties[$assetId]
    if ($null -eq $assetProperty) { throw "$ShotId references unknown asset: $assetId" }
    $asset = $assetProperty.Value
    if (-not ($eligibleStatuses -contains $asset.status)) { throw "$ShotId asset $assetId has ineligible status: $($asset.status)" }
    if ([string]::IsNullOrWhiteSpace([string]$asset.file_path) -or -not (Test-Path -LiteralPath $asset.file_path -PathType Leaf)) {
        throw "$ShotId asset file missing: $assetId"
    }
    if (-not [string]::IsNullOrWhiteSpace([string]$asset.sha256)) {
        $actualHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $asset.file_path).Hash
        if ($actualHash -ne $asset.sha256) { throw "$ShotId asset SHA256 mismatch: $assetId" }
    }
    $role = switch -Regex ([string]$asset.type) {
        'character|creature|crowd' { 'character'; break }
        'scene|vehicle' { 'scene'; break }
        default { 'prop' }
    }
    if ([string]$asset.type -match '^character$' -and (
        [string]$assetId -match '-FRONT-' -or
        [string]$asset.name -match '正面单人' -or
        [string]$asset.file_path -match '正面单人'
    )) {
        throw "$ShotId character asset $assetId is a front-only reference; use the approved three-view asset instead."
    }
    $bindings.Add([pscustomobject]@{
        asset_id = [string]$assetId
        name = [string]$asset.name
        role = $role
        file_path = [string]$asset.file_path
    })
}

if ($bindings.Count -gt $maxImages) { throw "$ShotId requires $($bindings.Count) images, exceeds limit $maxImages." }

$legend = [System.Collections.Generic.List[string]]::new()
for ($i = 0; $i -lt $bindings.Count; $i++) {
    $token = "@image$($i + 1)"
    $bindings[$i] | Add-Member -NotePropertyName token -NotePropertyValue $token
    $legend.Add("$token = $($bindings[$i].name)")
}

$result = [ordered]@{
    schema_version = 'doubao-shot-bindings-v1'
    shot_id = $ShotId
    image_count = $bindings.Count
    max_images = $maxImages
    bindings = @($bindings)
    legend = @($legend)
}

if (-not [string]::IsNullOrWhiteSpace($OutputPath)) {
    $directory = Split-Path -Parent $OutputPath
    if (-not [string]::IsNullOrWhiteSpace($directory)) { [System.IO.Directory]::CreateDirectory($directory) | Out-Null }
    [System.IO.File]::WriteAllText([System.IO.Path]::GetFullPath($OutputPath), ($result | ConvertTo-Json -Depth 20), [System.Text.UTF8Encoding]::new($false))
}

$legend | ForEach-Object { Write-Output $_ }
Write-Output "SHOT=$ShotId IMAGES=$($bindings.Count) LIMIT=$maxImages"
