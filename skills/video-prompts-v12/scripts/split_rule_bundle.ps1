param([Parameter(Mandatory=$true)][string]$Source,[Parameter(Mandatory=$true)][string]$SkillDirectory)
$ErrorActionPreference='Stop'
$raw=[IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $Source).Path)
$utf8=[Text.UTF8Encoding]::new($false,$true)
$text=$utf8.GetString($raw)
$marks=[regex]::Matches($text,'(?m)^(?:===== 文件来源：references/(?<file>\d{2}-[^\r\n]+\.md) =====|【规则层】references/(?<file>\d{2}-[^\r\n]+\.md))\r?$')
if($marks.Count -eq 0){throw 'No numbered rule sections found'}
$versionMatch=[regex]::Match($text,'(?m)^\s+version:\s*"(?<version>\d+\.\d+\.\d+)"')
if(!$versionMatch.Success){throw 'Missing source version'}
$routed=@([regex]::Matches($text.Substring(0,$marks[0].Index),'references/(?<file>\d{2}-[^`\r\n/]+\.md)')|ForEach-Object{$_.Groups['file'].Value}|Sort-Object -Unique)
$marked=@($marks|ForEach-Object{$_.Groups['file'].Value}|Sort-Object -Unique)
if($marked.Count -ne $marks.Count -or (Compare-Object $routed $marked)){throw 'Source route/section mismatch'}
$parts=[Collections.Generic.List[object]]::new()
$chunks=@(@{name='control.md';text=$text.Substring(0,$marks[0].Index)})
for($i=0;$i -lt $marks.Count;$i++){
 $end=if($i+1 -lt $marks.Count){$marks[$i+1].Index}else{$text.Length}
 $chunks+=@{name=$marks[$i].Groups['file'].Value;text=$text.Substring($marks[$i].Index,$end-$marks[$i].Index)}
}
$refs=Join-Path $SkillDirectory 'references'
New-Item -ItemType Directory -Path $refs -Force | Out-Null
foreach($chunk in $chunks){
 if($chunk.name -match '[/\\]' -or (Test-Path -LiteralPath (Join-Path $refs $chunk.name))){throw 'Unsafe or existing destination'}
}
if(Test-Path -LiteralPath (Join-Path $refs 'rule-bundle.json')){throw 'Manifest exists'}
foreach($chunk in $chunks){
 $bytes=$utf8.GetBytes($chunk.text)
 [IO.File]::WriteAllBytes((Join-Path $refs $chunk.name),$bytes)
 $parts.Add(@{file=$chunk.name;bytes=$bytes.Length;sha256=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes))})
}
$manifest=[ordered]@{schema_version='v12-rule-bundle-v1';version=$versionMatch.Groups['version'].Value;source_sha256=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($raw));source_bytes=$raw.Length;parts=@($parts)}
[IO.File]::WriteAllText((Join-Path $refs 'rule-bundle.json'),($manifest|ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))
Write-Host "Split into $($parts.Count) exact byte segments; packaging markers retained for lossless reconstruction."
