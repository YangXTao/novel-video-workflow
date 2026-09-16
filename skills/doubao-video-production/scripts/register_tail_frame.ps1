param(
    [Parameter(Mandatory = $true)]
    [string]$ManifestPath,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^S\d{2}$')]
    [string]$SourceShotId,

    [Parameter(Mandatory = $true)]
    [string]$TailFilePath
)

$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) { throw "Manifest not found: $ManifestPath" }
if (-not (Test-Path -LiteralPath $TailFilePath -PathType Leaf)) { throw "Tail frame not found: $TailFilePath" }

$manifest = Get-Content -Raw -LiteralPath $ManifestPath | ConvertFrom-Json -Depth 100
$targets = @($manifest.shots.PSObject.Properties | Where-Object {
    $_.Value.tail_frame.eligible -eq $true -and $_.Value.tail_frame.source_shot -eq $SourceShotId
})
if ($targets.Count -eq 0) { throw "No tail-continuation shot depends on $SourceShotId." }

$assetId = "TAIL-$SourceShotId-V01"
$resolvedTailPath = (Resolve-Path -LiteralPath $TailFilePath).Path
$hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $resolvedTailPath).Hash

$existing = $manifest.assets.PSObject.Properties[$assetId]
if ($null -ne $existing -and $existing.Value.sha256 -ne $hash) {
    throw "$assetId already exists with a different hash. Preserve it and register a new version explicitly."
}

$tailAsset = [pscustomobject][ordered]@{
    name = "${SourceShotId}尾帧"
    type = 'continuity_frame'
    status = 'approved'
    file_path = $resolvedTailPath
    sha256 = $hash
    source_shot = $SourceShotId
    applicable_shots = @($targets.Name)
    qa_basis = '已生成视频的尾帧，经人工确认可用于直续'
}

if ($null -eq $existing) {
    $manifest.assets | Add-Member -NotePropertyName $assetId -NotePropertyValue $tailAsset
}
else {
    $existing.Value = $tailAsset
}

foreach ($target in $targets) {
    $target.Value.tail_frame.status = 'approved'
    $target.Value.tail_frame | Add-Member -Force -NotePropertyName file_path -NotePropertyValue $resolvedTailPath
    $target.Value.tail_frame | Add-Member -Force -NotePropertyName sha256 -NotePropertyValue $hash
}

$json = $manifest | ConvertTo-Json -Depth 100
[System.IO.File]::WriteAllText((Resolve-Path -LiteralPath $ManifestPath).Path, $json, [System.Text.UTF8Encoding]::new($false))
Write-Output "REGISTERED=$assetId TARGETS=$($targets.Name -join ',') FILE=$resolvedTailPath"
