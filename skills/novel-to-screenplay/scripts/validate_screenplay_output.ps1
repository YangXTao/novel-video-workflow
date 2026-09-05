param(
    [Parameter(Mandatory = $true)]
    [string]$Output
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $Output -PathType Leaf)) {
    throw "找不到剧本输出：$Output"
}

$text = Get-Content -LiteralPath $Output -Raw
$issues = [System.Collections.Generic.List[object]]::new()

function Add-Issue {
    param([string]$Code, [string]$Shot, [string]$Message)
    $issues.Add([pscustomobject]@{ Code = $Code; Shot = $Shot; Message = $Message })
}

if ($text -notmatch 'SCRIPT-GATE-v1\.3-IND-S10') {
    Add-Issue 'VERSION' '-' '缺少当前执行版本指纹SCRIPT-GATE-v1.3-IND-S10。'
}
if ($text -notmatch '【V10\.1工业句法版完整交接剧本') {
    Add-Issue 'OPEN_MARKER' '-' '缺少V10.1工业句法版完整交接剧本开头。'
}
if ($text -notmatch '【V10\.1工业句法版完整交接剧本结束】') {
    Add-Issue 'CLOSE_MARKER' '-' '缺少V10.1工业句法版完整交接剧本结束标记。'
}
if ($text -notmatch '工业句法触发总览：') {
    Add-Issue 'INDUSTRIAL_OVERVIEW' '-' '章节总控缺少工业句法触发总览。'
}
if ($text -match '同上|同前镜|沿用前文|此处略|下略') {
    Add-Issue 'ABBREVIATION' '-' '发现跨镜省写表达。'
}

$header = [regex]::new('(?m)^S(?<id>\d{2})（')
$matches = $header.Matches($text)
if ($matches.Count -eq 0) {
    Add-Issue 'NO_SHOTS' '-' '未识别到Sxx镜头。'
}

for ($i = 0; $i -lt $matches.Count; $i++) {
    $shotId = "S$($matches[$i].Groups['id'].Value)"
    $start = $matches[$i].Index
    $end = if ($i + 1 -lt $matches.Count) { $matches[$i + 1].Index } else { $text.Length }
    $block = $text.Substring($start, $end - $start)
    $typeMatch = [regex]::Match($block, '(?m)^镜头类型：(?<type>[^\r\n]+)')
    $shotType = if ($typeMatch.Success) { $typeMatch.Groups['type'].Value.Trim() } else { '' }

    foreach ($field in @('所属场景：', '镜头类型：', '【上一镜尾帧衔接】', '【空间锁定】', '【时间轴·10秒】', '【对话与声音】', '【特效锁定】', '【禁止项】')) {
        if ($block -notmatch [regex]::Escape($field)) {
            Add-Issue 'FIELD_MISSING' $shotId "缺少字段：$field"
        }
    }

    $isIndustrial = $shotType -match '打戏|法术大场面'
    if ($isIndustrial) {
        if ($block -notmatch '【工业句法事实交接】') {
            Add-Issue 'INDUSTRIAL_BLOCK' $shotId '打戏/法术镜头缺少工业句法事实交接。'
        }
        foreach ($field in @('能量形态事实：', '目标—轨迹—结果：', '法阵活周期事实：', '瞬移空间事实：', '大招规模与破坏事实：')) {
            if ($block -notmatch [regex]::Escape($field)) {
                Add-Issue 'INDUSTRIAL_FIELD' $shotId "工业句法事实交接缺少：$field"
            }
        }
        $nodes = [regex]::Matches($block, '(?m)^00:(?:00|02|04|06|08)—00:(?:02|04|06|08|10)[，,：:]').Count
        if ($shotType -match '打戏' -and $nodes -lt 5) {
            Add-Issue 'ACTION_NODES' $shotId "打戏必须包含5个连续2秒节点，实际识别=$nodes。"
        }
        $storyBody = [regex]::Split($block, '【特效锁定】')[0]
        $hasEffect = $storyBody -match '法术|灵力|真元|剑气|刀气|枪芒|拳气|法阵|剑阵|领域|光柱|雷光|火焰|寒气|星幕|符文|附刃|贴刃'
        if ($hasEffect -and $block -notmatch '特效三层跨色锚点：(?!\s*无)') {
            Add-Issue 'CROSS_HUE' $shotId '有超自然特效但未填写三层跨色锚点。'
        }
    }
}

if ($issues.Count -gt 0) {
    $issues | Format-Table -AutoSize | Out-String | Write-Host
}

$errorCount = $issues.Count
Write-Host "剧本校验结果：ERROR=$errorCount 镜头=$($matches.Count)"
if ($errorCount -gt 0) { exit 1 }
exit 0
