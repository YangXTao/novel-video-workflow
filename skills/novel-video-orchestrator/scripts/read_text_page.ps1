# Read an exact, bounded UTF-8 slice without changing the source.
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$Path,
    [ValidateRange(0,2147483647)][int]$Offset = 0,
    [ValidateRange(1,6000)][int]$Count = 6000
)
$ErrorActionPreference = 'Stop'
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

