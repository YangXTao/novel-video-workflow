$ErrorActionPreference = 'Stop'
$helper = Join-Path $PSScriptRoot 'creative_task_io.ps1'
$testDir = Join-Path $PSScriptRoot ('io-test-' + [Guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $testDir
$source = Join-Path $testDir 'input.txt'
$output = Join-Path $testDir 'output.txt'
$manifest = Join-Path $testDir 'inputs.json'
$log = Join-Path $testDir 'reads.jsonl'
$seal = Join-Path $testDir 'seal.json'
$ranges = Join-Path $testDir 'required-ranges.json'
$emptySeal = Join-Path $testDir 'empty-seal.json'
function Assert($Condition, [string]$Message) { if (!$Condition) { throw $Message } }
function MustReject([scriptblock]$Operation, [string]$Pattern) {
    $rejected = $false
    try { & $Operation | Out-Null } catch {
        if ($_.Exception.Message -notmatch $Pattern) { throw }
        $rejected = $true
    }
    Assert $rejected "Expected rejection: $Pattern"
}
try {
    MustReject { & $helper -Action Snapshot -ManifestPath $manifest -InputPaths (Join-Path $testDir 'missing.txt') } 'does not exist|Cannot find path'
    [IO.File]::WriteAllText($source, "first line`nsecond line`nthird line")
    [IO.File]::WriteAllText($output, 'draft output')
    & $helper -Action Snapshot -ManifestPath $manifest -InputPaths $source | Out-Null
    $page = & $helper -Action Read -ManifestPath $manifest -Path $source -ReadLogPath $log -MaxLines 1 -MaxChars 8 | ConvertFrom-Json
    Assert ($page.content -eq 'first li') 'Character page cap failed.'
    Assert (!$page.receipt.fullFileInThisPage -and $page.receipt.remainingCharsAfterPage -gt 0) 'Partial page misreported as full.'
    $status = & $helper -Action VerifyReads -ManifestPath $manifest -ReadLogPath $log | ConvertFrom-Json
    Assert (!$status.allTextEmitted) 'Partial read coverage misreported as full.'
    [IO.File]::WriteAllText($ranges, (ConvertTo-Json -InputObject @(@{ path=$source; startOffset=0; endOffset=8 })))
    $status = & $helper -Action VerifyReads -ManifestPath $manifest -ReadLogPath $log -RequiredRangesPath $ranges | ConvertFrom-Json
    Assert ($status.allRequiredTextEmitted -and !$status.allTextEmitted) 'Selected range incorrectly implies full coverage or is not satisfied.'
    [IO.File]::WriteAllText($ranges, (ConvertTo-Json -InputObject @(@{ path=$source; startOffset=0; endOffset=12 })))
    $status = & $helper -Action VerifyReads -ManifestPath $manifest -ReadLogPath $log -RequiredRangesPath $ranges | ConvertFrom-Json
    Assert (!$status.allRequiredTextEmitted -and $status.files[0].remainingRequiredRanges[0].startOffset -eq 8 -and $status.files[0].remainingRequiredRanges[0].endOffsetExclusive -eq 12) 'Selected range gap was not reported accurately.'
    [IO.File]::WriteAllText($ranges, (ConvertTo-Json -InputObject @(@{ path=$source; startOffset=0; endOffset=9000 })))
    MustReject { & $helper -Action VerifyReads -ManifestPath $manifest -ReadLogPath $log -RequiredRangesPath $ranges } 'out of bounds'
    [IO.File]::WriteAllText($ranges, (ConvertTo-Json -InputObject @(@{ path=$source; startOffset=0 })))
    MustReject { & $helper -Action VerifyReads -ManifestPath $manifest -ReadLogPath $log -RequiredRangesPath $ranges } 'missing'
    [IO.File]::WriteAllText($ranges, (ConvertTo-Json -InputObject @(@{ path=$source; startOffset=0; endOffset=8; sha256='wrong' })))
    MustReject { & $helper -Action VerifyReads -ManifestPath $manifest -ReadLogPath $log -RequiredRangesPath $ranges } 'hash does not match'
    $offset = $page.receipt.nextOffset
    do {
        $page = & $helper -Action Read -ManifestPath $manifest -Path $source -ReadLogPath $log -StartOffset $offset -MaxLines 1 -MaxChars 8 | ConvertFrom-Json
        Assert ($page.content.Length -le 8) 'Page exceeds cap.'
        $offset = $page.receipt.nextOffset
    } while (!$page.receipt.reachedEof)
    $status = & $helper -Action VerifyReads -ManifestPath $manifest -ReadLogPath $log | ConvertFrom-Json
    Assert $status.allTextEmitted 'Full cumulative coverage not recognized.'
    $sourceHash = (Get-FileHash -LiteralPath $source).Hash
    $outputHash = (Get-FileHash -LiteralPath $output).Hash
    MustReject { & $helper -Action Seal -ManifestPath $manifest -OutputPaths $output -SealPath $source } 'already exists'
    MustReject { & $helper -Action Seal -ManifestPath $manifest -OutputPaths $output -SealPath $output } 'already exists'
    Assert ((Get-FileHash -LiteralPath $source).Hash -eq $sourceHash -and (Get-FileHash -LiteralPath $output).Hash -eq $outputHash) 'Seal collision changed a source or output.'
    [IO.File]::WriteAllText($emptySeal, '{"schema":"creative-output-seal/v1","files":[]}')
    MustReject { & $helper -Action VerifyOutput -SealPath $emptySeal } 'Invalid output seal'
    & $helper -Action Seal -ManifestPath $manifest -OutputPaths $output -SealPath $seal | Out-Null
    $verified = & $helper -Action VerifyOutput -SealPath $seal | ConvertFrom-Json
    Assert $verified.verified 'Unchanged output did not verify.'
    [IO.File]::AppendAllText($output, 'tamper')
    MustReject { & $helper -Action VerifyOutput -SealPath $seal } 'Sealed output changed'
    [IO.File]::AppendAllText($source, 'tamper')
    MustReject { & $helper -Action Read -ManifestPath $manifest -Path $source -ReadLogPath $log } 'Input hash changed'
    MustReject { & $helper -Action VerifyReads -ManifestPath $manifest -ReadLogPath $log } 'Input hash changed'
    'PASS: missing input; bounded pagination; partial/full coverage; selected range satisfied and gap; invalid range bounds/fields/hash rejected; seal source/output overwrite rejected; empty seal rejected; unchanged seal; sealed output tamper; changed input rejection.'
} finally {
    # Only remove the uniquely created fixture directory after verifying containment.
    $resolvedTestDir = [IO.Path]::GetFullPath($testDir)
    $allowedParent = [IO.Path]::GetFullPath($PSScriptRoot).TrimEnd('\') + '\'
    if (!$resolvedTestDir.StartsWith($allowedParent, [StringComparison]::OrdinalIgnoreCase) -or (Split-Path -Leaf $resolvedTestDir) -notmatch '^io-test-[0-9a-f]{32}$') { throw 'Unsafe fixture cleanup target.' }
    Remove-Item -LiteralPath $resolvedTestDir -Recurse -Force
}
