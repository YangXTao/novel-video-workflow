<#
.SYNOPSIS
  校验 video-prompts-v13 使用的规则源（同一工作流包或 Codex 用户目录中的小家 v13.1.1 skill）。

.DESCRIPTION
  按 项目配置 → 环境变量 → 默认安装位置 的顺序解析规则源目录，校验：
    SKILL.md 存在、metadata.version 达标、references/ 含 29 个现行规则文件、
    references/96-规则执行契约与证据回执.md 存在。
  输出规则源路径、版本、references 数量与 SKILL.md 的 SHA-256（供 screenplay_trigger_audit.json 使用）。
  校验失败以退出码 1 结束；调用方不得回落到其他版本规则源。

.EXAMPLE
  pwsh -NoProfile -File scripts/verify_rule_source.ps1
  pwsh -NoProfile -File scripts/verify_rule_source.ps1 -RuleSource "D:\skills\xiaojia-prompt-generator" -Json
#>
[CmdletBinding()]
param(
  [string]$RuleSource,
  [string]$RequiredVersion = '13.1.1',
  [string]$ProjectRoot,
  [switch]$Json
)
$ErrorActionPreference = 'Stop'

$expectedRefs = @('00','01','02','03','10','11','12','13','20','30','35','37','40','41','50','60','61','70','80','90','91','92','93','94','95','96','97','99','100')

function Resolve-RuleSourceDir {
  param([string]$Explicit, [string]$Root)
  if ($Explicit) { return (Resolve-Path -LiteralPath $Explicit).Path }
  $r = if ($Root) { $Root } else { (Get-Location).Path }
  $cfg = Join-Path $r 'novel_video_production_config.json'
  if (Test-Path -LiteralPath $cfg) {
    try {
      $j = Get-Content -LiteralPath $cfg -Raw -Encoding UTF8 | ConvertFrom-Json
      $p = $j.video_prompt_generation.rule_source
      if ($p) { return (Resolve-Path -LiteralPath $p).Path }
    } catch { }
  }
  if ($env:XIAOJIA_SKILL_DIR) { return (Resolve-Path -LiteralPath $env:XIAOJIA_SKILL_DIR).Path }

  # Self-contained workflow bundle: prefer the sibling rule-source skill in
  # this checkout/install so a stale WorkBuddy copy cannot mask this branch.
  $bundled = Join-Path $PSScriptRoot '../../xiaojia-prompt-generator'
  if (Test-Path -LiteralPath $bundled) { return (Resolve-Path -LiteralPath $bundled).Path }

  $h = if ($env:USERPROFILE) { $env:USERPROFILE } else { $HOME }
  foreach ($relative in @(
    '.codex/skills/xiaojia-prompt-generator',
    '.workbuddy/skills/xiaojia-prompt-generator'
  )) {
    $candidate = Join-Path $h $relative
    if (Test-Path -LiteralPath $candidate) { return (Resolve-Path -LiteralPath $candidate).Path }
  }
  return (Join-Path $h '.codex/skills/xiaojia-prompt-generator')
}

function Test-LowerVersion {
  param([string]$Have, [string]$Need)
  $h = @(); $n = @()
  foreach ($x in ($Have -split '\.')) { if ($x -match '^\d+$') { $h += [int]$x } else { $h += 0 } }
  foreach ($x in ($Need -split '\.')) { if ($x -match '^\d+$') { $n += [int]$x } else { $n += 0 } }
  while ($h.Count -lt $n.Count) { $h += 0 }
  for ($i = 0; $i -lt $n.Count; $i++) {
    if ($h[$i] -lt $n[$i]) { return $true }
    if ($h[$i] -gt $n[$i]) { return $false }
  }
  return $false
}

$problems = @()
$path = $null; $version = $null; $sha = $null; $found = @(); $missingRefs = @()

try {
  $path = Resolve-RuleSourceDir -Explicit $RuleSource -Root $ProjectRoot
  $skillMd = Join-Path $path 'SKILL.md'
  $refsDir = Join-Path $path 'references'

  if (-not (Test-Path -LiteralPath $skillMd)) { $problems += "缺少 SKILL.md：$skillMd" }
  if (-not (Test-Path -LiteralPath $refsDir)) { $problems += "缺少 references/：$refsDir" }

  if (Test-Path -LiteralPath $skillMd) {
    $sha = (Get-FileHash -LiteralPath $skillMd -Algorithm SHA256).Hash
    $head = Get-Content -LiteralPath $skillMd -TotalCount 40 -Encoding UTF8
    foreach ($line in $head) {
      if ($line -match '^\s*version:\s*"?([0-9][^"\s]*)"?\s*$') { $version = $Matches[1]; break }
    }
    if (-not $version) { $problems += 'SKILL.md 未声明 metadata.version' }
    elseif (Test-LowerVersion -Have $version -Need $RequiredVersion) { $problems += "规则源版本 $version 低于要求 $RequiredVersion" }
  }

  if (Test-Path -LiteralPath $refsDir) {
    $found = @(Get-ChildItem -LiteralPath $refsDir -Filter '*.md' | ForEach-Object { ($_.Name -split '-')[0] })
    $missingRefs = @($expectedRefs | Where-Object { $found -notcontains $_ })
    if ($missingRefs.Count -gt 0) { $problems += "references/ 缺少规则文件：$($missingRefs -join ', ')" }
    if (-not (Test-Path -LiteralPath (Join-Path $refsDir '96-规则执行契约与证据回执.md'))) {
      $problems += '缺少 references/96-规则执行契约与证据回执.md'
    }
  }
} catch {
  $problems += "校验异常：$($_.Exception.Message)"
}

$ok = ($problems.Count -eq 0)
$result = [ordered]@{
  ok                 = $ok
  rule_source        = $path
  skill_md_sha256    = $sha
  version            = $version
  required_version   = $RequiredVersion
  references_count   = @($found | Where-Object { $_ }).Count
  missing_references = @($missingRefs)
  problems           = @($problems)
}

if ($Json) {
  Write-Output ($result | ConvertTo-Json -Depth 6)
} else {
  Write-Output "rule_source      : $path"
  Write-Output "version          : $version (required $RequiredVersion)"
  Write-Output "references       : $($result.references_count)"
  Write-Output "skill_md_sha256  : $sha"
  foreach ($pb in $problems) { Write-Output "PROBLEM: $pb" }
}
if (-not $ok) { exit 1 } else { exit 0 }
