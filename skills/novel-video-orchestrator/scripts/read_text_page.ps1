# Read an exact, bounded UTF-8 slice without changing the source.
[CmdletBinding()]
param(
    [string]$Path,
    [ValidateRange(0,2147483647)][int]$Offset = 0,
    [ValidateRange(1,6000)][int]$Count = 6000,
    [string]$ReceiptPath,
    [string]$CheckPlan,
    [string[]]$RequiredPath = @()
)
$ErrorActionPreference = 'Stop'
if ($CheckPlan) {
    if (!$ReceiptPath) { throw 'CheckPlan requires ReceiptPath.' }
    $plan = Get-Content -Raw -LiteralPath $CheckPlan -Encoding UTF8 | ConvertFrom-Json
    if (!$plan.files -or @($plan.files).Count -eq 0) { throw 'Plan requires nonempty files.' }
    $receipts = @()
    if (Test-Path -LiteralPath $ReceiptPath) {
        $receipts = @(Get-Content -LiteralPath $ReceiptPath -Encoding UTF8 | Where-Object { $_.Trim() } | ForEach-Object { $_ | ConvertFrom-Json })
    }
    $missing = @()
    $files = @($plan.files) + @($RequiredPath | ForEach-Object { [pscustomobject]@{path=$_} })
    foreach ($file in $files) {
        $item = Get-Item -LiteralPath $file.path
        $length = ([IO.File]::ReadAllText($item.FullName, [Text.Encoding]::UTF8)).Length
        $hash = (Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash
        $ranges = @($file.ranges)
        if (!$file.ranges) { $ranges = @([pscustomobject]@{start=0;end=$length}) }
        foreach ($range in $ranges) {
            if ($null -eq $range.start -or $null -eq $range.end -or $range.start -lt 0 -or $range.end -gt $length -or $range.end -le $range.start) { throw 'Invalid half-open UTF-16 range.' }
            $cursor = [int]$range.start
            foreach ($receipt in @($receipts | Where-Object { $_.path -eq $item.FullName -and $_.sha256 -eq $hash } | Sort-Object start,end)) {
                $start = [Math]::Max([int]$range.start,[int]$receipt.start)
                $end = [Math]::Min([int]$range.end,[int]$receipt.end)
                if ($start -ge $range.end -or $end -le $range.start) { continue }
                if ($end -le $cursor) { continue }
                if ($start -gt $cursor) { $missing += [pscustomobject]@{path=$item.FullName;start=$cursor;end=$start} }
                $cursor = $end
            }
            if ($cursor -lt $range.end) { $missing += [pscustomobject]@{path=$item.FullName;start=$cursor;end=[int]$range.end} }
        }
    }
    [pscustomobject]@{emitted_coverage_complete=($missing.Count -eq 0);missing=$missing;note='Emission coverage only; not proof of model reading, comprehension or output compliance.'} | ConvertTo-Json -Depth 6
    if ($missing.Count) { exit 2 }
    exit 0
}
if (!$Path) { throw 'Path is required for reading.' }
$item = Get-Item -LiteralPath $Path
if ($item.PSIsContainer) { throw 'Expected a file.' }
$body = [System.IO.File]::ReadAllText($item.FullName, [System.Text.Encoding]::UTF8)
if ($Offset -gt $body.Length) { throw 'Offset is past EOF.' }
$end = [Math]::Min($body.Length, $Offset + $Count)
# Do not split a UTF-16 surrogate pair.
if ($end -lt $body.Length -and $end -gt $Offset -and [char]::IsHighSurrogate($body[$end-1])) { $end-- }
if ($end -eq $Offset -and $Offset -lt $body.Length) { throw 'Count too small for this character.' }
$hash = (Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash
Write-Output ("READ path={0} sha256={1} offset={2} end={3} total={4}" -f $item.FullName,$hash,$Offset,$end,$body.Length)
Write-Output $body.Substring($Offset, $end-$Offset)
Write-Output ("READ_END next_offset={0} eof={1}" -f $end,($end -eq $body.Length).ToString().ToLowerInvariant())
if ($ReceiptPath) {
    # Log emitted ranges, never claim that the model consumed or understood them.
    $receipt = [pscustomobject]@{path=$item.FullName;sha256=$hash;start=$Offset;end=$end;total=$body.Length}
    Add-Content -LiteralPath $ReceiptPath -Value ($receipt | ConvertTo-Json -Compress) -Encoding UTF8
}
