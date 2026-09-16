param(
    [Parameter(Mandatory = $true)][string]$Output,
    [string]$AuditPath,
    [string]$SourcePath,
    [string]$RulePath
)
$ErrorActionPreference = 'Stop'
$text = Get-Content -LiteralPath $Output -Raw -Encoding utf8
$issues = [System.Collections.Generic.List[string]]::new()
foreach ($token in @('SCREENPLAY-SCENE-v2','## 本章基础信息','目标时长：','整体基调：','## 人物与场景简表','## 分场剧本')) {
    if (!$text.Contains($token)) { $issues.Add("缺少：$token") }
}
if ($text -match 'SCRIPT-GATE-v1|V10\.1工业句法版完整交接剧本|【时间轴·10秒】|【工业句法事实交接】') { $issues.Add('混入旧工业交接结构') }
$scenes = [regex]::Matches($text, '(?m)^### (?<id>SC\d{2,})｜[^\r\n]+')
if (!$scenes.Count) { $issues.Add('没有SC场次') }
$ids = @($scenes | ForEach-Object { $_.Groups['id'].Value })
for ($i=0; $i -lt $scenes.Count; $i++) {
    $id=$ids[$i]
    if ($id -ne ('SC{0:D2}' -f ($i+1))) { $issues.Add("场次不连续：$id") }
    $end=if ($i+1 -lt $scenes.Count) {$scenes[$i+1].Index} else {$text.Length}
    $block=$text.Substring($scenes[$i].Index,$end-$scenes[$i].Index)
    foreach ($field in @('出场人物：','场景与开场状态：','动作：','对白：','收束：')) {
        if (!$block.Contains($field)) { $issues.Add("$id 缺少 $field") }
    }
    foreach($line in ($block -split '\r?\n')) {
        if ($line -match '^\s*[^\[［\r\n]+[［\[](?<tag>[^］\]]*)[］\]]\s*[:：]') {
            $parts = $Matches.tag -split '[｜|]'
            if ($parts.Count -lt 3 -or @($parts | Where-Object {![string]::IsNullOrWhiteSpace($_)}).Count -lt 3) {
                $issues.Add("$id 声音标签缺少声线/情绪/嘴部状态")
            }
        } elseif ($line -match '^\s*[^：]{1,30}：“') {
            $issues.Add("$id 发现未标注声音的对白：$line")
        }
    }
}
if (!$AuditPath) { $AuditPath=Join-Path (Split-Path -Parent (Resolve-Path -LiteralPath $Output).Path) 'screenplay_trigger_audit.json' }
if (!(Test-Path -LiteralPath $AuditPath)) { $issues.Add('缺少独立触发审计') }
else {
    $audit=Get-Content -LiteralPath $AuditPath -Raw -Encoding utf8 | ConvertFrom-Json
    if ($audit.schema_version -ne 'screenplay-trigger-audit-v2') {$issues.Add('审计版本错误')}
    if ($audit.rule_version -notmatch '^\d+\.\d+\.\d+$' -or $audit.rule_sha256 -notmatch '^[A-Fa-f0-9]{64}$') {$issues.Add('母版版本/哈希缺失')}
    if($RulePath) {
        if ((Split-Path -Leaf $RulePath) -eq 'rule-bundle.json') {
            $ruleRoot=Split-Path -Parent (Split-Path -Parent (Resolve-Path -LiteralPath $RulePath).Path)
            $verified=& (Join-Path $ruleRoot 'scripts/validate_rule_bundle.ps1') -SkillDirectory $ruleRoot
            $actualRuleHash=$verified.sha256
            if($audit.rule_version -ne $verified.version) {$issues.Add('母版版本不匹配')}
        } else {
            $actualRuleHash=(Get-FileHash -LiteralPath $RulePath -Algorithm SHA256).Hash
            $ruleText = Get-Content -LiteralPath $RulePath -Raw -Encoding utf8
            $versionMatch = [regex]::Match($ruleText, '(?m)^\s*version:\s*["\x27]?(\d+\.\d+\.\d+)')
            if ($versionMatch.Success) {
                if ($audit.rule_version -ne $versionMatch.Groups[1].Value) { $issues.Add('母版版本不匹配') }
            } elseif ((Split-Path -Leaf $RulePath) -match 'v(?<major>\d+)\.(?<minor>\d+)') {
                $expectedRuleVersion="$($Matches.major).$($Matches.minor).0"
                if($audit.rule_version -ne $expectedRuleVersion) {$issues.Add('母版版本不匹配')}
            }
        }
        if($audit.rule_sha256 -ne $actualRuleHash) {$issues.Add('母版哈希不匹配')}
    }
    $source=if($SourcePath){Get-Content -LiteralPath $SourcePath -Raw -Encoding utf8}else{$null}
    $auditIds=@($audit.scenes | ForEach-Object {$_.scene_id})
    if(($ids -join ',') -ne ($auditIds -join ',')) {$issues.Add('审计场次与正文不一致')}
    foreach($scene in $audit.scenes) {
        $idx=[Array]::IndexOf($ids,[string]$scene.scene_id)
        if($idx -lt 0){continue}
        $end=if($idx+1 -lt $scenes.Count){$scenes[$idx+1].Index}else{$text.Length}
        $block=$text.Substring($scenes[$idx].Index,$end-$scenes[$idx].Index)
        if ($null -eq $scene.events) {$issues.Add("$($scene.scene_id) 缺少events数组"); continue}
        foreach($event in $scene.events) {
            foreach($field in @('source_quote','content_type','event','rule_locator','screenplay_phrase','reason')) {
                if([string]::IsNullOrWhiteSpace([string]$event.$field)) {$issues.Add("事件缺少 $field")}
            }
            if(!$block.Contains([string]$event.screenplay_phrase)) {$issues.Add('触发动作未出现在对应场次')}
            if($SourcePath -and !$source.Contains([string]$event.source_quote)) {$issues.Add('原文证据不存在')}
        }
    }
    if($null -eq $audit.downstream_gate) {$issues.Add('缺少下游门禁')}
    else {
        $gate=$audit.downstream_gate
        if([string]$gate.status -notin @('ready','needs-resolution')) {$issues.Add('下游门禁状态错误')}
        if($null -eq $gate.blocking_ambiguities) {$issues.Add('缺少 blocking_ambiguities 数组')}
        if($null -eq $gate.nonblocking_notes) {$issues.Add('缺少 nonblocking_notes 数组')}
        $blocking=@($gate.blocking_ambiguities)
        if($gate.status -eq 'ready' -and $blocking.Count -gt 0) {$issues.Add('ready 状态仍有阻断歧义')}
        if($gate.status -eq 'needs-resolution' -and $blocking.Count -eq 0) {$issues.Add('needs-resolution 状态没有阻断歧义')}
        foreach($ambiguity in $blocking) {
            foreach($field in @('id','issue','downstream_impact','resolution_required')) {
                if([string]::IsNullOrWhiteSpace([string]$ambiguity.$field)) {$issues.Add("阻断歧义缺少 $field")}
            }
            $evidence=@($ambiguity.source_evidence)
            if($evidence.Count -eq 0 -or @($evidence | Where-Object {![string]::IsNullOrWhiteSpace([string]$_)}).Count -eq 0) {
                $issues.Add('阻断歧义缺少 source_evidence')
            } elseif($SourcePath) {
                foreach($quote in $evidence) {
                    if(!$source.Contains([string]$quote)) {$issues.Add('歧义原文证据不存在')}
                }
            }
        }
    }
}
$issues | ForEach-Object { Write-Host $_ }
Write-Host "结构检查：ERROR=$($issues.Count) 场次=$($scenes.Count)。剧情保真、语义匹配与声音一致性仍需人工语义复核。"
if($issues.Count){exit 1}
exit 0
