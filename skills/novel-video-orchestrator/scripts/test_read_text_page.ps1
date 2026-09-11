$ErrorActionPreference = 'Stop'
$reader = Join-Path $PSScriptRoot 'read_text_page.ps1'
$testDir = Join-Path ([IO.Path]::GetTempPath()) ('read-page-test-' + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($testDir) | Out-Null
$fixture = Join-Path $testDir 'fixture.txt'
$receipt = Join-Path $testDir 'receipt.jsonl'
$plan = Join-Path $testDir 'plan.json'
[IO.File]::WriteAllText($fixture,'abcdefghij',[Text.UTF8Encoding]::new($false))
@{files=@(@{path=$fixture})} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $plan -Encoding UTF8
function Check([int]$expected,[int]$start=-1,[int]$end=-1) {
    $output = & pwsh -NoProfile -File $reader -CheckPlan $plan -ReceiptPath $receipt
    if ($LASTEXITCODE -ne $expected) { throw "Unexpected exit: $LASTEXITCODE; $output" }
    $result = ($output -join "`n") | ConvertFrom-Json
    if ($start -ge 0 -and ($result.missing.Count -ne 1 -or $result.missing[0].start -ne $start -or $result.missing[0].end -ne $end)) { throw "Wrong gap: $output" }
}
Check 2 0 10
& $reader -Path $fixture -Offset 0 -Count 3 -ReceiptPath $receipt | Out-Null
& $reader -Path $fixture -Offset 7 -Count 3 -ReceiptPath $receipt | Out-Null
Check 2 3 7
& $reader -Path $fixture -Offset 2 -Count 6 -ReceiptPath $receipt | Out-Null
Check 0
# A changed source must invalidate the old receipts.
[IO.File]::WriteAllText($fixture,'ABCDEFGHIJ',[Text.UTF8Encoding]::new($false))
Check 2 0 10
& $reader -Path $fixture -ReceiptPath $receipt | Out-Null
Check 0
# Selected subsection, and unrelated emitted ranges, must not expand the requirement.
@{files=@(@{path=$fixture;ranges=@(@{start=3;end=6})})} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $plan -Encoding UTF8
Check 0
# Legacy reads without a receipt remain supported.
$extra = Join-Path $testDir 'required.txt'
[IO.File]::WriteAllText($extra,'required',[Text.UTF8Encoding]::new($false))
$requiredResult = & pwsh -NoProfile -File $reader -CheckPlan $plan -ReceiptPath $receipt -RequiredPath $extra
if ($LASTEXITCODE -ne 2 -or (($requiredResult -join "`n") | ConvertFrom-Json).missing[0].path -ne $extra) { throw 'Missing required file was not detected.' }
$legacy = & $reader -Path $fixture -Offset 0 -Count 2
if (($legacy -join "`n") -notmatch 'READ_END next_offset=2 eof=false') { throw 'Legacy read failed.' }
Write-Output "PASS: missing-file, gap, overlap, changed-source, subsection, legacy. Fixtures: $testDir"
