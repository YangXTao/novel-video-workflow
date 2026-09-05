param(
    [Parameter(Mandatory = $true)]
    [string]$AssetIndexPath,

    [Parameter(Mandatory = $true)]
    [string]$AssetId,

    [Parameter(Mandatory = $true)]
    [string]$Name,

    [Parameter(Mandatory = $true)]
    [ValidateSet('character', 'scene', 'prop', 'vehicle', 'continuity_frame')]
    [string]$Type,

    [ValidateSet('approved', 'reuse_approved', 'generated_unreviewed', 'rejected', 'no_build')]
    [string]$Status = 'generated_unreviewed',

    [string]$FilePath,
    [string[]]$ApplicableShots,
    [string]$QaBasis
)

$ErrorActionPreference = 'Stop'
$isManifest = $false
if (Test-Path -LiteralPath $AssetIndexPath -PathType Leaf) {
    $index = Get-Content -Raw -LiteralPath $AssetIndexPath -Encoding UTF8 | ConvertFrom-Json -Depth 100
    $isManifest = $index.schema_version -eq 'novel-video-asset-manifest-v1'
    if (-not $isManifest -and $index.schema_version -ne 'image-production-registry-v1') { throw "Unsupported asset index schema: $($index.schema_version)" }
}
else {
    $index = [pscustomobject][ordered]@{
        schema_version = 'image-production-registry-v1'
        created_at = [DateTimeOffset]::Now.ToString('o')
        updated_at = [DateTimeOffset]::Now.ToString('o')
        assets = [pscustomobject]@{}
    }
}

$hasFile = $Status -in @('approved', 'reuse_approved', 'generated_unreviewed', 'rejected')
$resolvedPath = $null
$width = $null
$height = $null
$hash = $null
if ($hasFile) {
    if ([string]::IsNullOrWhiteSpace($FilePath) -or -not (Test-Path -LiteralPath $FilePath -PathType Leaf)) { throw "Status $Status requires an existing image file." }
    $resolvedPath = (Resolve-Path -LiteralPath $FilePath).Path
    Add-Type -AssemblyName System.Drawing
    $image = $null
    try {
        $image = [System.Drawing.Image]::FromFile($resolvedPath)
        $width = [int]$image.Width
        $height = [int]$image.Height
    }
    finally {
        if ($null -ne $image) { $image.Dispose() }
    }
    $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $resolvedPath).Hash
}

$existingProperty = $index.assets.PSObject.Properties[$AssetId]
if ($null -ne $existingProperty -and $existingProperty.Value.status -in @('approved', 'reuse_approved')) {
    $existingHash = [string]$existingProperty.Value.sha256
    if (-not [string]::IsNullOrWhiteSpace($hash) -and -not [string]::IsNullOrWhiteSpace($existingHash) -and $hash -ne $existingHash) {
        throw "$AssetId is already approved with a different hash. Use a new versioned asset ID."
    }
}

$asset = if ($null -ne $existingProperty) { $existingProperty.Value } else { [pscustomobject]@{} }
foreach ($pair in @(
    @('name', $Name), @('type', $Type), @('status', $Status), @('file_path', $resolvedPath),
    @('width', $width), @('height', $height), @('sha256', $hash),
    @('applicable_shots', @($ApplicableShots)), @('qa_basis', $QaBasis)
)) {
    $asset | Add-Member -Force -NotePropertyName $pair[0] -NotePropertyValue $pair[1]
}

if ($null -eq $existingProperty) { $index.assets | Add-Member -NotePropertyName $AssetId -NotePropertyValue $asset }
if (-not $isManifest) { $index.updated_at = [DateTimeOffset]::Now.ToString('o') }

$directory = Split-Path -Parent $AssetIndexPath
if (-not [string]::IsNullOrWhiteSpace($directory)) { [System.IO.Directory]::CreateDirectory($directory) | Out-Null }
[System.IO.File]::WriteAllText([System.IO.Path]::GetFullPath($AssetIndexPath), ($index | ConvertTo-Json -Depth 100), [System.Text.UTF8Encoding]::new($false))
Write-Output "REGISTERED=$AssetId STATUS=$Status FILE=$resolvedPath INDEX=$([System.IO.Path]::GetFullPath($AssetIndexPath))"

