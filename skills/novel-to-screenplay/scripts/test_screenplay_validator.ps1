$ErrorActionPreference='Stop'
$dir=Join-Path ([System.IO.Path]::GetTempPath()) ('screenplay-test-'+[guid]::NewGuid())
New-Item -ItemType Directory -Path $dir | Out-Null
$validator=Join-Path $PSScriptRoot 'validate_screenplay_output.ps1'
$rule=Join-Path $PSScriptRoot '../../video-prompts-v12/references/rule-bundle.json'
$verified=& (Join-Path $PSScriptRoot '../../video-prompts-v12/scripts/validate_rule_bundle.ps1')
$hash=$verified.sha256
$source='林舟从半空摔下，落在桥面。他爬起身，说：“我没事。”'
$phrase='林舟从半空坠落，落在桥面，随后爬起身。'
$body=@"
# 测试章节
版本：SCREENPLAY-SCENE-v2
## 本章基础信息
目标时长：20秒
整体基调：紧张
## 人物与场景简表
人物：林舟，男，固定声线：清朗男声。
场景：石桥，日，外。
## 分场剧本
### SC01｜石桥｜日｜外
出场人物：林舟
场景与开场状态：林舟位于桥面上方。
动作：
$phrase
对白：
林舟［清朗男声｜强作镇定｜开口］：“我没事。”
收束：林舟站在桥上，无新伤势说明。
"@
$audit=[ordered]@{schema_version='screenplay-trigger-audit-v2';rule_version='12.4.0';rule_sha256=$hash;scenes=@(@{scene_id='SC01';events=@(@{source_quote='林舟从半空摔下，落在桥面';content_type='动作';event='坠落';rule_locator='10/事件运镜速查表/坠落';screenplay_phrase=$phrase;reason='被动从高处落下，不是主动俯冲；起身不映射权力反转'})});downstream_gate=[ordered]@{status='ready';blocking_ambiguities=@();nonblocking_notes=@()}}
$src=Join-Path $dir 'source.txt'
$out=Join-Path $dir 'screenplay.md'
$aud=Join-Path $dir 'screenplay_trigger_audit.json'
[IO.File]::WriteAllText($src,$source)
$cases=@(
 @{name='valid';text=$body;quote='林舟从半空摔下，落在桥面';expected=0},
 @{name='missing_voice';text=$body.Replace('清朗男声｜强作镇定｜开口','强作镇定｜开口');quote='林舟从半空摔下，落在桥面';expected=1},
 @{name='invented_evidence';text=$body;quote='林舟瞬移到桥头';expected=1},
 @{name='legacy_structure';text=$body+" SCRIPT-GATE-v1";quote='林舟从半空摔下，落在桥面';expected=1},
 @{name='scene_mismatch';text=$body.Replace('SC01','SC02');quote='林舟从半空摔下，落在桥面';expected=1},
 @{name='missing_phrase';text=$body.Replace($phrase,'林舟飞走了。');quote='林舟从半空摔下，落在桥面';expected=1}
)
$cases += @{name='wrong_rule_version';text=$body;quote='林舟从半空摔下，落在桥面';expected=1;rule_version='0.0.0'}
foreach($case in $cases){
 $audit.rule_version=if($case.ContainsKey('rule_version')){$case.rule_version}else{$verified.version}
 [IO.File]::WriteAllText($out,$case.text)
 $audit.scenes[0].events[0].source_quote=$case.quote
 [IO.File]::WriteAllText($aud,($audit|ConvertTo-Json -Depth 10))
 & (Get-Process -Id $PID).Path -NoProfile -File $validator -Output $out -AuditPath $aud -SourcePath $src -RulePath $rule | Out-Null
 if($LASTEXITCODE -ne $case.expected){throw "FAIL $($case.name): $LASTEXITCODE"}
 Write-Host "PASS $($case.name)"
}
$audit.rule_version=$verified.version
$audit.scenes[0].events[0].source_quote='林舟从半空摔下，落在桥面'
$audit.downstream_gate=[ordered]@{status='ready';blocking_ambiguities=@([ordered]@{id='AMB-01';source_evidence=@('林舟从半空摔下');issue='落点材质不明';downstream_impact='会影响落地参考图';resolution_required='确认桥面材质'});nonblocking_notes=@()}
[IO.File]::WriteAllText($out,$body)
[IO.File]::WriteAllText($aud,($audit|ConvertTo-Json -Depth 10))
& (Get-Process -Id $PID).Path -NoProfile -File $validator -Output $out -AuditPath $aud -SourcePath $src -RulePath $rule | Out-Null
if($LASTEXITCODE -ne 1){throw "FAIL ready_with_blocker: $LASTEXITCODE"}
Write-Host 'PASS ready_with_blocker'
$audit.downstream_gate.status='needs-resolution'
[IO.File]::WriteAllText($aud,($audit|ConvertTo-Json -Depth 10))
& (Get-Process -Id $PID).Path -NoProfile -File $validator -Output $out -AuditPath $aud -SourcePath $src -RulePath $rule | Out-Null
if($LASTEXITCODE -ne 0){throw "FAIL valid_blocked_gate: $LASTEXITCODE"}
Write-Host 'PASS valid_blocked_gate'
$audit.downstream_gate.blocking_ambiguities[0].source_evidence=@('原文没有这句话')
[IO.File]::WriteAllText($aud,($audit|ConvertTo-Json -Depth 10))
& (Get-Process -Id $PID).Path -NoProfile -File $validator -Output $out -AuditPath $aud -SourcePath $src -RulePath $rule | Out-Null
if($LASTEXITCODE -ne 1){throw "FAIL invented_ambiguity_evidence: $LASTEXITCODE"}
Write-Host 'PASS invented_ambiguity_evidence'
Write-Host "Fixtures retained: $dir"
Write-Host 'These tests validate structure/provenance only, not model semantic behavior.'
