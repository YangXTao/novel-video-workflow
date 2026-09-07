param(
    [Parameter(Mandatory = $true)]
    [string]$InputPath,

    [Parameter(Mandatory = $true)]
    [string]$AssetManifest,

    [Parameter(Mandatory = $true)]
    [string]$Output
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $InputPath -PathType Leaf)) { throw "Input not found: $InputPath" }
if (-not (Test-Path -LiteralPath $AssetManifest -PathType Leaf)) { throw "Manifest not found: $AssetManifest" }
if ((Resolve-Path -LiteralPath $InputPath).Path -eq [System.IO.Path]::GetFullPath($Output)) { throw 'Output must differ from Input.' }

$text = Get-Content -Raw -LiteralPath $InputPath
$manifest = Get-Content -Raw -LiteralPath $AssetManifest | ConvertFrom-Json -Depth 100
$headerRegex = [regex]::new('(?m)^##\s+(?:S(?<id1>\d{2})\b|【第(?<id2>\d+)镜)')
$matches = $headerRegex.Matches($text)
if ($matches.Count -eq 0) { throw 'No Sxx shot headers found.' }

$builder = [System.Text.StringBuilder]::new()
$cursor = 0
for ($i = 0; $i -lt $matches.Count; $i++) {
    $match = $matches[$i]
    $idText = if ($match.Groups['id1'].Success) { $match.Groups['id1'].Value } else { $match.Groups['id2'].Value }
    $shotId = 'S{0:D2}' -f [int]$idText
    $end = if ($i + 1 -lt $matches.Count) { $matches[$i + 1].Index } else { $text.Length }
    [void]$builder.Append($text.Substring($cursor, $match.Index - $cursor))
    $block = $text.Substring($match.Index, $end - $match.Index)

    $shotProperty = $manifest.shots.PSObject.Properties[$shotId]
    if ($null -eq $shotProperty) { throw "Manifest has no shot: $shotId" }

    $parts = foreach ($assetId in @($shotProperty.Value.static_reference_assets)) {
        $assetProperty = $manifest.assets.PSObject.Properties[$assetId]
        if ($null -eq $assetProperty) { throw "$shotId references unknown asset: $assetId" }
        "$assetId=$($assetProperty.Value.name)"
    }
    $semanticLine = '**参考资产需求**：' + ($parts -join '；') + '。本字段只声明语义资产，实际图片编号由视频制作Skill在上传前按真实文件、尾帧状态和10图上限分配。'

    $oldMappingRegex = [regex]::new('\*\*参考图映射\*\*：[^\r\n]*')
    $semanticMappingRegex = [regex]::new('\*\*参考资产需求\*\*：[^\r\n]*')
    if ($oldMappingRegex.IsMatch($block)) {
        $block = $oldMappingRegex.Replace($block, $semanticLine, 1)
    }
    elseif ($semanticMappingRegex.IsMatch($block)) {
        $block = $semanticMappingRegex.Replace($block, $semanticLine, 1)
    }
    else {
        $lineEnd = $block.IndexOf("`n")
        if ($lineEnd -lt 0) { throw "$shotId header has no following line." }
        $block = $block.Insert($lineEnd + 1, "`r`n$semanticLine`r`n")
    }

    $block = [regex]::Replace($block, '@image\d+', '对应已审核角色资产')
    [void]$builder.Append($block)
    $cursor = $end
}

if ($cursor -lt $text.Length) { [void]$builder.Append($text.Substring($cursor)) }
$result = $builder.ToString()
$remainingToken = [regex]::Match($result, '@image\d+|@图片\d+')
if ($remainingToken.Success) {
    $contextStart = [Math]::Max(0, $remainingToken.Index - 80)
    $contextLength = [Math]::Min(200, $result.Length - $contextStart)
    throw "Premature image token remains after linking: $($result.Substring($contextStart, $contextLength))"
}

$outputDirectory = Split-Path -Parent $Output
if (-not [string]::IsNullOrWhiteSpace($outputDirectory)) { [System.IO.Directory]::CreateDirectory($outputDirectory) | Out-Null }
[System.IO.File]::WriteAllText([System.IO.Path]::GetFullPath($Output), $result, [System.Text.UTF8Encoding]::new($false))
Write-Output "LINKED_SHOTS=$($matches.Count) OUTPUT=$([System.IO.Path]::GetFullPath($Output))"
