param(
    [Parameter(Mandatory = $true)]
    [string]$ManifestPath,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^S\d{2}$')]
    [string]$ShotId,

    [string]$OutputPath,

    # The exact shot body. Supplying it enables immutable-body binding checks.
    [string]$PromptText
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) { throw "Manifest not found: $ManifestPath" }
$manifest = Get-Content -Raw -LiteralPath $ManifestPath | ConvertFrom-Json -Depth 100
$shotProperty = $manifest.shots.PSObject.Properties[$ShotId]
if ($null -eq $shotProperty) { throw "Shot not found in manifest: $ShotId" }

$shot = $shotProperty.Value
$requiredIdentityProperty = $shot.PSObject.Properties['required_identity_assets']
if ($null -eq $requiredIdentityProperty) {
    throw "$ShotId missing required_identity_assets. Build the core identity list before submission."
}
$requiredIdentityAssets = @($shot.required_identity_assets)
$identityReasons = $shot.identity_requirement_reasons
$identityWaivers = $shot.identity_waivers
$tailCoveredIdentityAssets = @()
if ($null -ne $shot.tail_frame -and $null -ne $shot.tail_frame.PSObject.Properties['covered_identity_assets']) {
    $tailCoveredIdentityAssets = @($shot.tail_frame.covered_identity_assets)
}
if ($requiredIdentityAssets.Count -gt 0 -and $null -eq $identityReasons) {
    throw "$ShotId missing identity_requirement_reasons."
}
$eligibleStatuses = @($manifest.reference_policy.eligible_statuses)
$maxImages = [int]$manifest.reference_policy.max_images_per_shot
if ($maxImages -lt 1 -or $maxImages -gt 10) { throw 'Image limit must be between 1 and 10.' }
$softMaxImages = 5
if ($null -ne $manifest.reference_policy.PSObject.Properties['soft_max_images_per_shot']) {
    $softMaxImages = [int]$manifest.reference_policy.soft_max_images_per_shot
}
if ($softMaxImages -lt 1 -or $softMaxImages -gt $maxImages) { throw 'Soft image limit must be between 1 and max_images_per_shot.' }
$continuityMode = ''
if ($null -ne $shot.PSObject.Properties['continuity_mode']) { $continuityMode = [string]$shot.continuity_mode }
$isHardContinuation = $continuityMode -in @('hard_continuation', 'tail_continuation')
if ($continuityMode -and $continuityMode -notin @('hard_continuation', 'soft_continuity', 'no_continuity', 'tail_continuation')) {
    throw "$ShotId has unsupported continuity_mode: $continuityMode"
}
if ($isHardContinuation -and $shot.tail_frame.eligible -ne $true) {
    throw "$ShotId is a hard continuation but has no eligible tail frame."
}
if ($continuityMode -in @('soft_continuity', 'no_continuity') -and $shot.tail_frame.eligible -eq $true) {
    throw "$ShotId continuity_mode=$continuityMode must not upload a tail frame."
}
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
if ($bindings.Count -gt $softMaxImages -and [string]::IsNullOrWhiteSpace([string]$shot.reference_budget_exception_reason)) {
    throw "$ShotId requires $($bindings.Count) images, exceeds soft limit $softMaxImages without reference_budget_exception_reason. Replan the shot instead of dropping bindings."
}
$assetIds = @($bindings | ForEach-Object { $_.asset_id })
if (@($assetIds | Select-Object -Unique).Count -ne $bindings.Count) { throw 'Duplicate upload asset IDs.' }
foreach ($assetId in $requiredIdentityAssets) {
    if ([string]::IsNullOrWhiteSpace([string]$assetId)) { throw "$ShotId has an empty required identity asset." }
    $assetProperty = $manifest.assets.PSObject.Properties[[string]$assetId]
    if ($null -eq $assetProperty) { throw "$ShotId required identity asset is unknown: $assetId" }
    if ([string]$assetProperty.Value.type -notmatch 'character|creature') {
        throw "$ShotId required identity asset is not a character/creature: $assetId"
    }
    if ($null -eq $identityReasons.PSObject.Properties[[string]$assetId] -or [string]::IsNullOrWhiteSpace([string]$identityReasons.PSObject.Properties[[string]$assetId].Value)) {
        throw "$ShotId required identity asset has no reason: $assetId"
    }
    if ([string]$assetId -notin $assetIds -and [string]$assetId -notin $tailCoveredIdentityAssets) {
        throw "$ShotId omits required identity asset from upload bindings: $assetId"
    }
}
$bodyTokens = @()
if ($PSBoundParameters.ContainsKey('PromptText')) {
    if ([string]::IsNullOrWhiteSpace($PromptText)) { throw 'PromptText cannot be empty.' }
    $bodyTokens = @([regex]::Matches($PromptText, '@image\d+\b') | ForEach-Object { $_.Value } | Select-Object -Unique)
    $map = $shot.body_reference_bindings
    $mapKeys = @()
    if ($null -ne $map) { $mapKeys = @($map.PSObject.Properties | ForEach-Object { $_.Name }) }
    if (@($bodyTokens | Where-Object { $_ -notin $mapKeys }).Count -or @($mapKeys | Where-Object { $_ -notin $bodyTokens }).Count) {
        throw 'body_reference_bindings must resolve exactly the image tokens present in this shot body.'
    }
    $speakerNames = @([regex]::Matches($PromptText, '【([^｜\]\r\n]+)｜') | ForEach-Object { $_.Groups[1].Value.Trim() } | Select-Object -Unique)
    foreach ($speakerName in $speakerNames) {
        $speakerWaived = $false
        if ($null -ne $identityWaivers -and $null -ne $identityWaivers.PSObject.Properties[$speakerName]) {
            $waiverReason = [string]$identityWaivers.PSObject.Properties[$speakerName].Value
            if ($waiverReason -notin @('offscreen_voice', 'unidentifiable_distance', 'background_only')) {
                throw "$ShotId speaking role '$speakerName' has unsupported identity waiver: $waiverReason"
            }
            $speakerWaived = $true
        }
        $matchingIdentityIds = @($manifest.assets.PSObject.Properties | Where-Object {
            $_.Value.type -match 'character|creature' -and (
                [string]$_.Value.name -eq $speakerName -or
                [string]$_.Value.name -like "$speakerName·*" -or
                [string]$_.Value.name -like "$speakerName-*"
            )
        } | ForEach-Object { $_.Name })
        if (-not $speakerWaived -and $matchingIdentityIds.Count -gt 0 -and @($matchingIdentityIds | Where-Object { $_ -in $assetIds -or $_ -in $tailCoveredIdentityAssets }).Count -eq 0) {
            throw "$ShotId speaking role '$speakerName' has an approved identity asset but none is included in upload bindings."
        }
    }
    $ordered = [object[]]::new($bindings.Count)
    $assigned = @{}
    foreach ($token in $bodyTokens) {
        $index = [int]$token.Substring(6) - 1
        if ($index -lt 0 -or $index -ge $bindings.Count -or $token -ne "@image$($index + 1)") { throw "Unfillable body image index: $token. Do not add filler assets or rewrite the body." }
        $assetId = [string]$map.PSObject.Properties[$token].Value
        if ($assetId -notin $assetIds -or $assigned.ContainsKey($assetId)) { throw "Invalid or duplicated body binding: $token -> $assetId" }
        $ordered[$index] = @($bindings | Where-Object { $_.asset_id -eq $assetId })[0]
        $assigned[$assetId] = $true
    }
    $remaining = @($bindings | Where-Object { !$assigned.ContainsKey($_.asset_id) })
    $next = 0
    for ($i=0; $i -lt $ordered.Count; $i++) {
        if ($null -eq $ordered[$i]) { $ordered[$i] = $remaining[$next]; $next++ }
    }
    $bindings.Clear()
    foreach ($item in $ordered) { $bindings.Add($item) }
}
if ($isHardContinuation -and ($bindings.Count -eq 0 -or $bindings[0].role -ne 'continuity_frame')) {
    throw "$ShotId hard-continuation tail frame must be @image1. Return to video-prompts-v12; do not renumber the body in production."
}

$legend = [System.Collections.Generic.List[string]]::new()
$supplementalLegend = [System.Collections.Generic.List[string]]::new()
for ($i = 0; $i -lt $bindings.Count; $i++) {
    $token = "@image$($i + 1)"
    $bindings[$i] | Add-Member -NotePropertyName token -NotePropertyValue $token
    $legend.Add("$token = $($bindings[$i].name)")
    if ($token -notin $bodyTokens) { $supplementalLegend.Add("$token = $($bindings[$i].name)") }
}

$result = [ordered]@{
    schema_version = 'doubao-shot-bindings-v1'
    shot_id = $ShotId
    continuity_mode = $continuityMode
    image_count = $bindings.Count
    max_images = $maxImages
    soft_max_images = $softMaxImages
    reference_budget_status = $(if ($bindings.Count -le $softMaxImages) { 'within_soft_limit' } else { 'approved_exception' })
    bindings = @($bindings)
    legend = @($legend)
    supplemental_legend = @($supplementalLegend)
    body_checked = $PSBoundParameters.ContainsKey('PromptText')
}

if (-not [string]::IsNullOrWhiteSpace($OutputPath)) {
    $directory = Split-Path -Parent $OutputPath
    if (-not [string]::IsNullOrWhiteSpace($directory)) { [System.IO.Directory]::CreateDirectory($directory) | Out-Null }
    [System.IO.File]::WriteAllText([System.IO.Path]::GetFullPath($OutputPath), ($result | ConvertTo-Json -Depth 20), [System.Text.UTF8Encoding]::new($false))
}

if ($PSBoundParameters.ContainsKey('PromptText')) {
    $supplementalLegend | ForEach-Object { Write-Output $_ }
} else {
    # Legacy callers retain the old output, but this is not a production binding.
    $legend | ForEach-Object { Write-Output $_ }
    Write-Output "SHOT=$ShotId IMAGES=$($bindings.Count) LIMIT=$maxImages"
}
