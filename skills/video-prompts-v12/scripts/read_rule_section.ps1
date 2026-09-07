param([string]$Section)
$ErrorActionPreference='Stop'
$refs=Join-Path $PSScriptRoot '../references'
$m=Get-Content -LiteralPath (Join-Path $refs 'rule-bundle.json') -Raw -Encoding utf8|ConvertFrom-Json
if(!$Section){$m.parts|ForEach-Object{$_.file};return}
if($Section -ne 'control' -and $Section -notmatch '^\d{2}$'){throw 'Section must be control or a two-digit ID'}
$found=@($m.parts|Where-Object{if($Section -eq 'control'){$_.file -eq 'control.md'}else{$_.file.StartsWith($Section+'-')}})
if($found.Count -ne 1){throw 'Unknown or duplicate section'}
$path=Join-Path $refs $found[0].file
if((Get-FileHash -LiteralPath $path).Hash -ne $found[0].sha256){throw 'Section hash mismatch'}
Get-Content -LiteralPath $path -Raw -Encoding utf8
