param([string]$SkillDirectory=(Split-Path -Parent $PSScriptRoot))
$ErrorActionPreference='Stop'
$refs=Join-Path $SkillDirectory 'references'
$m=Get-Content -LiteralPath (Join-Path $refs 'rule-bundle.json') -Raw -Encoding utf8|ConvertFrom-Json
if($m.schema_version -ne 'v12-rule-bundle-v1' -or $m.parts.Count -lt 2 -or $m.parts[0].file -ne 'control.md'){throw 'Invalid manifest'}
$stream=[IO.MemoryStream]::new()
try{
 $names=@()
 foreach($part in $m.parts){
  if($part.file -notmatch '^(control|\d{2}-[^/\\]+)\.md$' -or $part.file -in $names){throw 'Invalid/duplicate part path'}
  $names+= $part.file
  $bytes=[IO.File]::ReadAllBytes((Join-Path $refs $part.file))
  $hash=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes))
  if($hash -ne $part.sha256 -or $bytes.Length -ne $part.bytes){throw "Part changed: $($part.file)"}
  $stream.Write($bytes,0,$bytes.Length)
 }
 $all=$stream.ToArray()
 $hash=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($all))
 if($hash -ne $m.source_sha256 -or $all.Length -ne $m.source_bytes){throw 'Reconstruction mismatch'}
 $control=Get-Content -LiteralPath (Join-Path $refs 'control.md') -Raw -Encoding utf8
 $version=[regex]::Match($control,'(?m)^\s+version:\s*"(?<version>\d+\.\d+\.\d+)"').Groups['version'].Value
 if($version -ne $m.version){throw 'Source version mismatch'}
 $routed=@([regex]::Matches($control,'references/(?<file>\d{2}-[^`\r\n/]+\.md)')|ForEach-Object{$_.Groups['file'].Value}|Sort-Object -Unique)
 $numbered=@($names|Where-Object{$_ -ne 'control.md'}|Sort-Object)
 if(Compare-Object $routed $numbered){throw 'Routing mismatch'}
 [pscustomobject]@{status='verified';version=$m.version;sha256=$hash;bytes=$all.Length;parts=$m.parts.Count}
}finally{$stream.Dispose()}
