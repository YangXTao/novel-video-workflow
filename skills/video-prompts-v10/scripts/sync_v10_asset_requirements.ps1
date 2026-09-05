param(
    [Parameter(Mandatory = $true)]
    [string]$InputPath,

    [Parameter(Mandatory = $true)]
    [string]$OutputPath,

    [Parameter(Mandatory = $true)]
    [string]$AssetManifestPath
)

$ErrorActionPreference = 'Stop'
foreach ($path in @($InputPath, $AssetManifestPath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Input file not found: $path" }
}
if (Test-Path -LiteralPath $OutputPath) { throw "Output already exists; preserve it and choose a new version: $OutputPath" }

$resolvedInputPath = (Resolve-Path -LiteralPath $InputPath).Path
$resolvedManifestPath = (Resolve-Path -LiteralPath $AssetManifestPath).Path
$resolvedOutputPath = [System.IO.Path]::GetFullPath($OutputPath)
$text = [System.IO.File]::ReadAllText($resolvedInputPath, [System.Text.Encoding]::UTF8)
$manifest = Get-Content -LiteralPath $resolvedManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 100

$headerPattern = [regex]::new('(?m)^##\s+(?:【第(?<id1>\d+)镜|S(?<id2>\d{2})\b)')
$requirementPattern = [regex]::new('(?m)^\*\*参考资产需求\*\*：[^\r\n]*$')
$numberedReferencePattern = [regex]::new('严格参考图\s*\d+')
$headers = $headerPattern.Matches($text)
if ($headers.Count -eq 0) { throw 'No V10 shot headers were found.' }

$requirementsUpdated = 0
$numberedLocksUpdated = 0
for ($i = $headers.Count - 1; $i -ge 0; $i--) {
    $header = $headers[$i]
    $idText = if ($header.Groups['id1'].Success) { $header.Groups['id1'].Value } else { $header.Groups['id2'].Value }
    $shotId = 'S{0:D2}' -f [int]$idText
    $shotProperty = $manifest.shots.PSObject.Properties[$shotId]
    if ($null -eq $shotProperty) { throw "Manifest shot not found: $shotId" }

    $start = $header.Index
    $end = if ($i + 1 -lt $headers.Count) { $headers[$i + 1].Index } else { $text.Length }
    $block = $text.Substring($start, $end - $start)
    $requirementMatches = $requirementPattern.Matches($block)
    if ($requirementMatches.Count -ne 1) { throw "$shotId must contain exactly one reference asset requirement line; found $($requirementMatches.Count)." }

    $items = [System.Collections.Generic.List[string]]::new()
    foreach ($assetId in @($shotProperty.Value.static_reference_assets)) {
        $assetProperty = $manifest.assets.PSObject.Properties[[string]$assetId]
        if ($null -eq $assetProperty) { throw "$shotId references missing asset: $assetId" }
        $asset = $assetProperty.Value
        if ($asset.status -notin @($manifest.reference_policy.eligible_statuses)) { throw "$shotId references ineligible asset $assetId with status $($asset.status)." }
        if ([string]::IsNullOrWhiteSpace([string]$asset.file_path) -or -not (Test-Path -LiteralPath $asset.file_path -PathType Leaf)) {
            throw "$shotId references an asset without a real file: $assetId"
        }
        $items.Add("$assetId=$($asset.name)")
    }

    $replacement = '**参考资产需求**：' + ($items -join '；') + '。本字段只声明语义资产，实际图片编号由视频制作Skill在上传前按真实文件、尾帧状态和10图上限分配。'
    $block = $requirementPattern.Replace($block, $replacement, 1)
    $requirementsUpdated++

    $lockCount = $numberedReferencePattern.Matches($block).Count
    if ($lockCount -gt 0) {
        $block = $numberedReferencePattern.Replace($block, '严格参考已上传的对应角色资产')
        $numberedLocksUpdated += $lockCount
    }

    $text = $text.Substring(0, $start) + $block + $text.Substring($end)
}

if ($numberedReferencePattern.IsMatch($text)) { throw 'Numbered reference locks remain after synchronization.' }

function Normalize-MutableReferenceText([string]$Value) {
    $normalized = $requirementPattern.Replace($Value, '<REFERENCE_ASSET_REQUIREMENTS>')
    $normalized = $numberedReferencePattern.Replace($normalized, '<SEMANTIC_REFERENCE_LOCK>')
    $normalized = $normalized.Replace('严格参考已上传的对应角色资产', '<SEMANTIC_REFERENCE_LOCK>')
    return $normalized
}

$beforeNormalized = Normalize-MutableReferenceText ([System.IO.File]::ReadAllText($resolvedInputPath, [System.Text.Encoding]::UTF8))
$afterNormalized = Normalize-MutableReferenceText $text
if ($beforeNormalized -ne $afterNormalized) { throw 'Content outside the permitted reference fields changed; output was not written.' }

$outputDirectory = Split-Path -Parent $resolvedOutputPath
if (-not [string]::IsNullOrWhiteSpace($outputDirectory)) { [System.IO.Directory]::CreateDirectory($outputDirectory) | Out-Null }
[System.IO.File]::WriteAllText($resolvedOutputPath, $text, [System.Text.UTF8Encoding]::new($false))
$hash = (Get-FileHash -LiteralPath $resolvedOutputPath -Algorithm SHA256).Hash
Write-Output "OUTPUT=$resolvedOutputPath SHOTS=$requirementsUpdated NUMBERED_LOCKS=$numberedLocksUpdated SHA256=$hash"
