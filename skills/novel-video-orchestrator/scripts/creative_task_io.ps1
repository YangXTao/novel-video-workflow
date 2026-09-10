# Text offsets are zero-based UTF-16 code units; end offsets are exclusive.
# Read receipts record text emitted by this helper, not comprehension or compliance.
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('Snapshot','Read','VerifyInputs','VerifyReads','Seal','VerifyOutput')][string]$Action,
    [string]$ManifestPath,
    [string[]]$InputPaths,
    [string]$Path,
    [string]$ReadLogPath,
    [string]$RequiredRangesPath,
    [ValidateRange(0,2147483647)][int]$StartOffset = 0,
    [ValidateRange(1,1000)][int]$MaxLines = 120,
    [ValidateRange(2,60000)][int]$MaxChars = 12000,
    [string[]]$OutputPaths,
    [string]$SealPath
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function ExistingFile([string]$Value) {
    if ([string]::IsNullOrWhiteSpace($Value)) { throw 'A file path is required.' }
    $item = Get-Item -LiteralPath $Value -ErrorAction Stop
    if ($item.PSIsContainer) { throw "Expected file: $Value" }
    return $item.FullName
}
function HashFile([string]$Value) { return (Get-FileHash -LiteralPath $Value -Algorithm SHA256).Hash }
function LoadJson([string]$Value) { return ([IO.File]::ReadAllText((ExistingFile $Value)) | ConvertFrom-Json) }
function SaveNewJson([string]$Value, $Object) {
    if ([string]::IsNullOrWhiteSpace($Value)) { throw 'A destination path is required.' }
    $full = [IO.Path]::GetFullPath($Value)
    $stream = [IO.File]::Open($full, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write)
    try {
        $bytes = [Text.UTF8Encoding]::new($false).GetBytes(($Object | ConvertTo-Json -Depth 12))
        $stream.Write($bytes, 0, $bytes.Length)
    } finally { $stream.Dispose() }
}
function FileEntries([string[]]$Paths) {
    if (!$Paths -or $Paths.Count -eq 0) { throw 'At least one file is required.' }
    $seen = @{}
    foreach ($p in $Paths) {
        $full = ExistingFile $p
        if ($seen.ContainsKey($full)) { continue }
        $seen[$full] = $true
        [pscustomobject]@{ path = $full; sha256 = HashFile $full }
    }
}
function CheckedManifest {
    $m = LoadJson $ManifestPath
    if ($m.schema -ne 'creative-input-snapshot/v1' -or @($m.files).Count -eq 0) { throw 'Invalid input snapshot.' }
    foreach ($f in $m.files) {
        $full = ExistingFile $f.path
        if ((HashFile $full) -ne $f.sha256) { throw "Input hash changed: $full" }
    }
    return $m
}

switch ($Action) {
    'Snapshot' {
        $entries = @(FileEntries $InputPaths)
        $result = [ordered]@{ schema='creative-input-snapshot/v1'; createdUtc=[DateTime]::UtcNow.ToString('o'); files=$entries }
        SaveNewJson $ManifestPath $result
    }
    'VerifyInputs' {
        $m = CheckedManifest
        $result = @{ verified=$true; fileCount=@($m.files).Count; manifestSha256=HashFile (ExistingFile $ManifestPath) }
    }
    'Read' {
        $m = CheckedManifest
        $full = ExistingFile $Path
        $entry = @($m.files | Where-Object { $_.path -eq $full })
        if ($entry.Count -ne 1) { throw "File is not in input snapshot: $full" }
        if ([string]::IsNullOrWhiteSpace($ReadLogPath)) { throw 'ReadLogPath is required.' }
        $logFull = [IO.Path]::GetFullPath($ReadLogPath)
        if ($logFull -eq [IO.Path]::GetFullPath($ManifestPath) -or @($m.files | Where-Object { $_.path -eq $logFull }).Count -gt 0) { throw 'Read log cannot overwrite inputs or manifest.' }
        $body = [IO.File]::ReadAllText($full)
        if ((HashFile $full) -ne $entry[0].sha256) { throw "Input changed during read: $full" }
        if ($StartOffset -gt $body.Length) { throw 'StartOffset is beyond EOF.' }
        if ($StartOffset -gt 0 -and $StartOffset -lt $body.Length -and [char]::IsLowSurrogate($body[$StartOffset])) { throw 'StartOffset splits a surrogate pair.' }
        $end = $StartOffset
        $lineBreaks = 0
        while ($end -lt $body.Length -and ($end - $StartOffset) -lt $MaxChars -and $lineBreaks -lt $MaxLines) {
            if ($body[$end] -eq "`n") { $lineBreaks++ }
            $end++
        }
        if ($end -lt $body.Length -and $end -gt $StartOffset -and [char]::IsHighSurrogate($body[$end-1])) { $end-- }
        $startLine = 1
        for ($i=0; $i -lt $StartOffset; $i++) { if ($body[$i] -eq "`n") { $startLine++ } }
        $endLine = $startLine
        for ($i=$StartOffset; $i -lt $end; $i++) { if ($body[$i] -eq "`n") { $endLine++ } }
        $receipt = [ordered]@{
            schema='creative-read-receipt/v1'; utc=[DateTime]::UtcNow.ToString('o')
            manifestSha256=HashFile (ExistingFile $ManifestPath); path=$full; sha256=$entry[0].sha256
            startOffset=$StartOffset; endOffsetExclusive=$end; totalChars=$body.Length
            startLine=$startLine; endLineAtExclusiveOffset=$endLine
            reachedEof=($end -eq $body.Length); fullFileInThisPage=($StartOffset -eq 0 -and $end -eq $body.Length)
            remainingCharsAfterPage=($body.Length-$end); nextOffset=$end
            meaning='Text emitted by helper; not evidence of understanding or rule compliance.'
        }
        [IO.File]::AppendAllText($logFull, (($receipt | ConvertTo-Json -Compress) + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))
        $result = [ordered]@{ receipt=$receipt; content=$body.Substring($StartOffset, $end-$StartOffset) }
    }
    'VerifyReads' {
        $m = CheckedManifest
        $manifestHash = HashFile (ExistingFile $ManifestPath)
        $selected = @()
        $selectionHash = $null
        if ($RequiredRangesPath) {
            $selectionFile = ExistingFile $RequiredRangesPath
            $selectionHash = HashFile $selectionFile
            $selectionText = [IO.File]::ReadAllText($selectionFile)
            if (!$selectionText.TrimStart().StartsWith('[')) { throw 'Required ranges must be a JSON array.' }
            $selected = @($selectionText | ConvertFrom-Json)
            if ($selected.Count -eq 0) { throw 'Required ranges array must not be empty.' }
            foreach ($r in $selected) {
                if ($null -eq $r -or @('path','startOffset','endOffset' | Where-Object { $_ -notin $r.PSObject.Properties.Name }).Count -gt 0) { throw 'Required range is missing path, startOffset, or endOffset.' }
                if ($r.path -isnot [string] -or [string]::IsNullOrWhiteSpace($r.path)) { throw 'Required range path must be a nonempty string.' }
                if (($r.startOffset -isnot [int] -and $r.startOffset -isnot [long]) -or ($r.endOffset -isnot [int] -and $r.endOffset -isnot [long])) { throw 'Required range offsets must be integers.' }
                $r.path = ExistingFile $r.path
                $inputEntry = @($m.files | Where-Object { $_.path -eq $r.path })
                if ($inputEntry.Count -ne 1) { throw 'Required range file is not in input snapshot.' }
                $rangeLength = ([IO.File]::ReadAllText($r.path)).Length
                if ($r.startOffset -lt 0 -or $r.endOffset -lt $r.startOffset -or $r.endOffset -gt $rangeLength -or ($r.endOffset -eq $r.startOffset -and $rangeLength -gt 0)) { throw 'Required range is out of bounds or empty.' }
                # Optional explicit digest must match the manifest; the manifest always binds every selection.
                if ('sha256' -in $r.PSObject.Properties.Name -and $r.sha256 -ne $inputEntry[0].sha256) { throw 'Required range hash does not match input snapshot.' }
            }
        }
        $receipts = @([IO.File]::ReadAllLines((ExistingFile $ReadLogPath)) | Where-Object { $_.Trim() } | ForEach-Object { $_ | ConvertFrom-Json })
        $coverage = @(
            foreach ($f in $m.files) {
                $length = ([IO.File]::ReadAllText($f.path)).Length
                $pages = @($receipts | Where-Object { $_.path -eq $f.path })
                foreach ($p in $pages) {
                    if ($p.schema -ne 'creative-read-receipt/v1' -or $p.sha256 -ne $f.sha256 -or $p.manifestSha256 -ne $manifestHash -or $p.totalChars -ne $length) { throw "Stale or mismatched receipt: $($f.path)" }
                    if ($p.startOffset -lt 0 -or $p.endOffsetExclusive -lt $p.startOffset -or $p.endOffsetExclusive -gt $length) { throw 'Invalid receipt range.' }
                }
                $cursor = 0
                $gaps = @(
                    foreach ($p in ($pages | Sort-Object startOffset,endOffsetExclusive)) {
                        if ($p.startOffset -gt $cursor) { @{ startOffset=$cursor; endOffsetExclusive=$p.startOffset } }
                        $cursor = [Math]::Max($cursor, $p.endOffsetExclusive)
                    }
                    if ($cursor -lt $length) { @{ startOffset=$cursor; endOffsetExclusive=$length } }
                )
                $required = @($selected | Where-Object { $_.path -eq $f.path })
                $explicitSelection = $required.Count -gt 0
                if (!$explicitSelection) { $required = @([pscustomobject]@{ startOffset=0; endOffset=$length }) }
                $requiredGaps = @(
                    foreach ($r in $required) {
                        foreach ($gap in $gaps) {
                            $gapStart = [Math]::Max($r.startOffset, $gap.startOffset)
                            $gapEnd = [Math]::Min($r.endOffset, $gap.endOffsetExclusive)
                            if ($gapEnd -gt $gapStart) { @{ startOffset=$gapStart; endOffsetExclusive=$gapEnd } }
                        }
                    }
                )
                [pscustomobject]@{ path=$f.path; sha256=$f.sha256; fullTextEmitted=($gaps.Count -eq 0 -and $pages.Count -gt 0); remainingRanges=$gaps; receiptCount=$pages.Count; explicitSelection=$explicitSelection; requiredRanges=@($required | ForEach-Object { @{ startOffset=$_.startOffset; endOffsetExclusive=$_.endOffset } }); requiredTextEmitted=($requiredGaps.Count -eq 0 -and $pages.Count -gt 0); remainingRequiredRanges=$requiredGaps }
            }
        )
        $null = CheckedManifest
        if ($RequiredRangesPath -and (HashFile $selectionFile) -ne $selectionHash) { throw 'Required ranges file changed during verification.' }
        $result = @{ files=$coverage; allTextEmitted=(@($coverage | Where-Object { !$_.fullTextEmitted }).Count -eq 0); allRequiredTextEmitted=(@($coverage | Where-Object { !$_.requiredTextEmitted }).Count -eq 0); requiredRangesSha256=$selectionHash; manifestSha256=$manifestHash; meaning='Coverage of helper output only; selected ranges never imply full-file coverage, comprehension, compliance, or artistic quality. Files without explicit selections require full coverage.' }
    }
    'Seal' {
        $m = CheckedManifest
        $entries = @(FileEntries $OutputPaths)
        $result = [ordered]@{ schema='creative-output-seal/v1'; createdUtc=[DateTime]::UtcNow.ToString('o'); manifestPath=ExistingFile $ManifestPath; manifestSha256=HashFile (ExistingFile $ManifestPath); files=$entries; meaning='Integrity baseline, not an authenticity signature or quality approval.' }
        SaveNewJson $SealPath $result
    }
    'VerifyOutput' {
        $seal = LoadJson $SealPath
        if ($seal.schema -ne 'creative-output-seal/v1' -or @($seal.files).Count -eq 0) { throw 'Invalid output seal.' }
        if ((HashFile (ExistingFile $seal.manifestPath)) -ne $seal.manifestSha256) { throw 'Input snapshot manifest changed since output seal.' }
        $ManifestPath = $seal.manifestPath
        $null = CheckedManifest
        foreach ($f in $seal.files) {
            if ((HashFile (ExistingFile $f.path)) -ne $f.sha256) { throw "Sealed output changed: $($f.path)" }
        }
        $result = @{ verified=$true; fileCount=@($seal.files).Count; sealSha256=HashFile (ExistingFile $SealPath) }
    }
}
$result | ConvertTo-Json -Depth 12
