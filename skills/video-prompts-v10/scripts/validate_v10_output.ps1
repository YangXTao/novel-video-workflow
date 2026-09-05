param(
    [Parameter(Mandatory = $true)]
    [string]$Screenplay,

    [Parameter(Mandatory = $true)]
    [string]$Output,

    [switch]$RequireReferenceMapping,

    [string]$AssetManifest,

    [switch]$RequireSemanticAssetRequirements
)

$ErrorActionPreference = 'Stop'

function Add-Issue {
    param(
        [System.Collections.Generic.List[object]]$List,
        [string]$Level,
        [string]$Code,
        [string]$Shot,
        [string]$Message
    )

    $List.Add([pscustomobject]@{
        Level   = $Level
        Code    = $Code
        Shot    = $Shot
        Message = $Message
    })
}

function Get-ShotBlocks {
    param(
        [string]$Text,
        [regex]$HeaderPattern
    )

    $matches = $HeaderPattern.Matches($Text)
    $result = [ordered]@{}

    for ($i = 0; $i -lt $matches.Count; $i++) {
        $match = $matches[$i]
        $idText = if ($match.Groups['id1'].Success) {
            $match.Groups['id1'].Value
        }
        else {
            $match.Groups['id2'].Value
        }

        $id = '{0:D2}' -f [int]$idText
        $start = $match.Index
        $end = if ($i + 1 -lt $matches.Count) {
            $matches[$i + 1].Index
        }
        else {
            $Text.Length
        }

        $result[$id] = $Text.Substring($start, $end - $start)
    }

    return $result
}

if (-not (Test-Path -LiteralPath $Screenplay -PathType Leaf)) {
    throw "找不到基准剧本：$Screenplay"
}

if (-not (Test-Path -LiteralPath $Output -PathType Leaf)) {
    throw "找不到V10输出：$Output"
}

$screenplayText = Get-Content -LiteralPath $Screenplay -Raw
$outputText = Get-Content -LiteralPath $Output -Raw
$issues = [System.Collections.Generic.List[object]]::new()
$manifest = $null

if ($RequireSemanticAssetRequirements) {
    if ([string]::IsNullOrWhiteSpace($AssetManifest) -or -not (Test-Path -LiteralPath $AssetManifest -PathType Leaf)) {
        Add-Issue $issues 'ERROR' 'ASSET_MANIFEST' '-' '要求语义资产需求时必须提供有效的asset_manifest.json。'
    }
    else {
        try {
            $manifest = Get-Content -LiteralPath $AssetManifest -Raw | ConvertFrom-Json -Depth 100
        }
        catch {
            Add-Issue $issues 'ERROR' 'ASSET_MANIFEST_JSON' '-' "asset_manifest.json无法解析：$($_.Exception.Message)"
        }
    }
}

$screenplayHeader = [regex]::new('(?m)^S(?<id1>\d{2})（')
$outputHeader = [regex]::new('(?m)^##\s+(?:【第(?<id1>\d+)镜|S(?<id2>\d{2})\b)')

$screenplayShots = Get-ShotBlocks -Text $screenplayText -HeaderPattern $screenplayHeader
$outputShots = Get-ShotBlocks -Text $outputText -HeaderPattern $outputHeader

if ($screenplayShots.Count -eq 0) {
    Add-Issue $issues 'ERROR' 'NO_SCREENPLAY_SHOTS' '-' '基准剧本中没有识别到Sxx镜头。'
}

if ($outputShots.Count -eq 0) {
    Add-Issue $issues 'ERROR' 'NO_OUTPUT_SHOTS' '-' '输出中没有识别到逐镜标题。'
}

if ($screenplayShots.Count -ne $outputShots.Count) {
    Add-Issue $issues 'ERROR' 'SHOT_COUNT' '-' "镜头数不一致：剧本=$($screenplayShots.Count)，输出=$($outputShots.Count)。"
}

$firstOutputShot = $outputHeader.Match($outputText)
if ($firstOutputShot.Success) {
    $prefix = $outputText.Substring(0, $firstOutputShot.Index)
    $internalTerms = @('技能升级阶梯', '交付校验', '模块0', '内部事实表', '核心因果链：', 'A级剧情锚点：')
    foreach ($term in $internalTerms) {
        if ($prefix.Contains($term)) {
            Add-Issue $issues 'ERROR' 'INTERNAL_PLAN' '-' "输出了内部规划内容：$term"
        }
    }
}

if ([regex]::IsMatch($outputText, '同上|同前镜|画质同前|沿用前镜|此处略|下略')) {
    Add-Issue $issues 'ERROR' 'ABBREVIATION' '-' '发现“同上/同前镜/略”等省写表达。'
}

foreach ($shotId in $screenplayShots.Keys) {
    if (-not $outputShots.Contains($shotId)) {
        Add-Issue $issues 'ERROR' 'MISSING_SHOT' $shotId '输出缺少该镜头。'
        continue
    }

    $sourceBlock = [string]$screenplayShots[$shotId]
    $outputBlock = [string]$outputShots[$shotId]

    $typeMatch = [regex]::Match($sourceBlock, '(?m)^镜头类型：(?<type>[^\r\n]+)')
    $shotType = if ($typeMatch.Success) { $typeMatch.Groups['type'].Value.Trim() } else { '未知' }
    $isAction = $shotType -match '打戏|法术大场面'
    $compactLength = ([regex]::Replace($outputBlock, '\s+', '')).Length
    if ($isAction -and $compactLength -lt 2200) {
        Add-Issue $issues 'ERROR' 'DETAIL_DENSITY' $shotId "打戏/法术镜头疑似被压缩：非空白字符=$compactLength，严格下限=2200。四段式只能压缩栏目，不能压缩时间轴内容。"
    }

    if ($RequireReferenceMapping) {
        $hasLegacyReferenceMapping = $outputBlock -match '参考图映射'
        $hasRuntimeSemanticMapping = (
            $outputBlock -match '(?m)^\*\*参考资产需求\*\*：[^\r\n]+$' -and
            $outputBlock -match '实际图片编号由视频制作Skill在上传前按真实文件、尾帧状态和10图上限分配'
        )
        if (-not ($hasLegacyReferenceMapping -or $hasRuntimeSemanticMapping)) {
            Add-Issue $issues 'ERROR' 'REFERENCE_MAPPING' $shotId '缺少逐镜参考图映射或运行时语义资产映射声明。'
        }
    }

    if ($RequireSemanticAssetRequirements) {
        $requirementMatch = [regex]::Match($outputBlock, '(?m)^\*\*参考资产需求\*\*：(?<body>[^\r\n]+)$')
        if (-not $requirementMatch.Success) {
            Add-Issue $issues 'ERROR' 'SEMANTIC_ASSET_REQUIREMENTS' $shotId '缺少逐镜参考资产需求。'
        }
        if ($outputBlock -match '@image\d+|@图片\d+') {
            Add-Issue $issues 'ERROR' 'PREMATURE_IMAGE_TOKEN' $shotId 'V10阶段禁止提前分配@imageN。'
        }
        if ($outputBlock -match '严格参考图\s*\d+') {
            Add-Issue $issues 'ERROR' 'PREMATURE_REFERENCE_NUMBER' $shotId 'V10阶段禁止写死“严格参考图N”；应使用无编号语义资产锁。'
        }
        if ($null -ne $manifest) {
            $manifestShotId = "S$shotId"
            $shotProperty = $manifest.shots.PSObject.Properties[$manifestShotId]
            if ($null -eq $shotProperty) {
                Add-Issue $issues 'ERROR' 'MANIFEST_SHOT_MISSING' $shotId '资产清单缺少该镜头。'
            }
            else {
                $expectedAssetIds = @($shotProperty.Value.static_reference_assets | ForEach-Object { [string]$_ })
                $actualAssetIds = @()
                if ($requirementMatch.Success) {
                    # Asset IDs are commonly followed immediately by a Chinese display name,
                    # e.g. "CHAR-01-V02沈青梧". Unicode word boundaries treat both the
                    # trailing digit and the Chinese character as word characters, so \b
                    # fails here. Limit the boundary check to ASCII ID characters instead.
                    $actualAssetIds = @([regex]::Matches($requirementMatch.Groups['body'].Value, '(?<![A-Z0-9-])[A-Z][A-Z0-9]*(?:-[A-Z0-9]+)+-V\d{2}(?![A-Z0-9-])') | ForEach-Object { $_.Value } | Select-Object -Unique)
                }
                foreach ($assetId in $expectedAssetIds) {
                    if ($assetId -notin $actualAssetIds) {
                        Add-Issue $issues 'ERROR' 'ASSET_ID_MISSING' $shotId "参考资产需求缺少：$assetId"
                    }
                }
                foreach ($assetId in $actualAssetIds) {
                    if ($assetId -notin $expectedAssetIds) {
                        Add-Issue $issues 'ERROR' 'ASSET_ID_EXTRA' $shotId "参考资产需求包含清单未要求的资产：$assetId"
                    }
                }
            }
        }
    }

    if ($RequireReferenceMapping -or $RequireSemanticAssetRequirements) {
        if ($outputBlock -notmatch '严格参考(?:图|已上传的对应角色资产|已审核角色资产)') {
            Add-Issue $issues 'ERROR' 'REFERENCE_LOCK' $shotId '提供参考图时角色字段缺少严格参考资产锁。'
        }
        if ($outputBlock -notmatch '不描述长相服饰') {
            Add-Issue $issues 'WARNING' 'ZERO_APPEARANCE' $shotId '提供参考图时未明确写“不描述长相服饰”，请人工确认没有重复展开外观。'
        }
    }

    foreach ($token in @('Lumen', 'HDR', 'Kodak')) {
        if ($outputBlock -notmatch [regex]::Escape($token)) {
            Add-Issue $issues 'ERROR' 'QUALITY_SELF_CONTAINED' $shotId "画质基准缺少：$token"
        }
    }

    if ($isAction) {
        $positiveBlock = [regex]::Split($outputBlock, '(?m)^###\s*④\s*负面提示词')[0]
        foreach ($field in @('① 画质基准', '② 角色·场景·核心设定', '③ 时间轴', '④ 负面提示词')) {
            if ($outputBlock -notmatch [regex]::Escape($field)) {
                Add-Issue $issues 'ERROR' 'ACTION_FORMAT' $shotId "打戏/法术镜头缺少四段式字段：$field"
            }
        }

        foreach ($token in @('Path Tracing', 'Nanite', 'fps')) {
            if ($outputBlock -notmatch [regex]::Escape($token)) {
                Add-Issue $issues 'ERROR' 'ACTION_QUALITY' $shotId "打戏/法术画质缺少：$token"
            }
        }

        if ($outputBlock -match '(?<![A-Z0-9])(?:J0|J1|J2|B6|O1|N0|Q族|L1|L2|M0|M1|M2|M3|M4|M5|M6|M7)(?![A-Z0-9])|附着八法|工业句法审计') {
            Add-Issue $issues 'ERROR' 'INDUSTRIAL_INTERNAL_LEAK' $shotId '正式正文泄露了工业句法内部族编号、规则名或审计名；必须改写成自然画面语言。'
        }

        $hasFantasyEffect = $sourceBlock -match '特效三层跨色锚点：(?!\s*无)[^\r\n]+' -or $positiveBlock -match '法术|灵力|真元|剑气|刀气|枪芒|拳气|法阵|剑阵|领域|光柱|雷光|火焰|寒气|星幕|符文|附刃|贴刃'
        if ($hasFantasyEffect) {
            foreach ($layerTerm in @('核心', '中层', '外层')) {
                if ($positiveBlock -notmatch $layerTerm) {
                    Add-Issue $issues 'ERROR' 'CROSS_HUE_LAYER' $shotId "超自然特效缺少三层跨色可见结构：$layerTerm"
                }
            }
            $colorTerms = @('白', '银', '金', '红', '橙', '黄', '绿', '翠', '青', '蓝', '紫', '黑', '灰', '褐', '玄')
            $presentColors = @($colorTerms | Where-Object { $positiveBlock -match [regex]::Escape($_) } | Select-Object -Unique)
            if ($presentColors.Count -lt 3) {
                Add-Issue $issues 'ERROR' 'CROSS_HUE_COUNT' $shotId "超自然特效可辨颜色不足三种：$($presentColors -join '、')"
            }
            if ($positiveBlock -notmatch '跨色|对比色|三色|三层') {
                Add-Issue $issues 'ERROR' 'CROSS_HUE_DECLARATION' $shotId '缺少三层跨色相或等价三色分层声明。'
            }
        }

        $hasAttachedState = $sourceBlock -match '能量形态事实：[^\r\n]*附刃' -or $positiveBlock -match '附刃|贴刃|不离刃'
        if ($hasAttachedState) {
            foreach ($pattern in @('剑脊|刀槽|主脉', '刃缘|开刃', '螺旋|攀附|沿纹路', '回流|手.*尖|柄.*尖', '不离刃|贴住刃|根部.*刃')) {
                if ($positiveBlock -notmatch $pattern) {
                    Add-Issue $issues 'ERROR' 'ATTACHED_BLADE_DETAIL' $shotId "附刃状态缺少附着八法对应的自然画面信息：$pattern"
                }
            }
        }

        $hasDetachedState = $sourceBlock -match '能量形态事实：[^\r\n]*离体' -or $positiveBlock -match '离体攻击|脱体成形|脱离.*刃|飞出.*光刃'
        if ($hasDetachedState) {
            foreach ($pattern in @('离手|离体|脱体|飞出', '轨迹|沿.*方向|沿.*轴线', '命中|击中|格挡|躲开|击空', '消散|衰减|余波|残留|回流')) {
                if ($positiveBlock -notmatch $pattern) {
                    Add-Issue $issues 'ERROR' 'DETACHED_LIFECYCLE' $shotId "离体攻击缺少完整生命周期信息：$pattern"
                }
            }
        }

        $hasActiveArray = $sourceBlock -match '法阵活周期事实：(?!\s*无)[^\r\n]+' -or $positiveBlock -match '法阵|剑阵|领域'
        $arrayExplicitlyInactive = $sourceBlock -match '法阵活周期事实：[^\r\n]*(沉寂|损坏|停止|未启动)' -and $sourceBlock -notmatch '法阵活周期事实：[^\r\n]*(展开|运转|启动|点亮)'
        if ($hasActiveArray -and -not $arrayExplicitlyInactive) {
            foreach ($pattern in @('反向.*旋转|旋转.*反向', '点亮|明灭', '外扩.*回收|回收.*外扩', '穿梭|流动|游走')) {
                if ($positiveBlock -notmatch $pattern) {
                    Add-Issue $issues 'ERROR' 'ARRAY_LIFECYCLE' $shotId "运转中的法阵/剑阵/领域缺少活周期信息：$pattern"
                }
            }
        }

        $hasTeleport = $sourceBlock -match '事件类型：[^\r\n]*瞬移|瞬移空间事实：(?!\s*无)[^\r\n]+' -or $positiveBlock -match '瞬移|闪现|瞬身|空间跳跃'
        if ($hasTeleport) {
            foreach ($pattern in @('残影', 'Whip Pan|甩镜', '落定|落点|新位置')) {
                if ($positiveBlock -notmatch $pattern) {
                    Add-Issue $issues 'ERROR' 'TELEPORT_WHIP_CHAIN' $shotId "瞬移缺少高速残影—甩镜—落定起手链：$pattern"
                }
            }
        }

        $hasBigMove = $sourceBlock -match '大招规模与破坏事实：(?!\s*无)[^\r\n]+' -or $sourceBlock -match '打击等级[^\r\n]*(终结|灭世)'
        if ($hasBigMove) {
            foreach ($pattern in @('EWS|大远景|超远景|超宏观', '全貌|完整.*轮廓|特效.*轮廓', '爆炸|爆点|冲击波', '崩裂|塌陷|地貌|地形|山体|建筑.*塌|裂谷')) {
                if ($positiveBlock -notmatch $pattern) {
                    Add-Issue $issues 'ERROR' 'BIG_MOVE_EWS' $shotId "大绝招缺少大远景展招同框信息：$pattern"
                }
            }
        }

        $actionTimeMatches = [regex]::Matches($outputBlock, '(?m)^(?:\*\*)?(?:\d{2}:\d{2}(?:\.\d+)?[—-]\d{2}:\d{2}(?:\.\d+)?|\d+(?:\.\d+)?至\d+(?:\.\d+)?秒)[，,：:]?(?<body>[^\r\n]+)')
        $timeNodes = $actionTimeMatches.Count
        if ($timeNodes -lt 5) {
            Add-Issue $issues 'ERROR' 'ACTION_TIME_NODES' $shotId "打戏/法术时间轴少于5个节点：实际=$timeNodes。"
        }

        foreach ($timeMatch in $actionTimeMatches) {
            $nodeBody = [regex]::Replace($timeMatch.Groups['body'].Value, '\s+', '')
            if ($nodeBody.Length -lt 130) {
                Add-Issue $issues 'ERROR' 'ACTION_NODE_DENSITY' $shotId "时间节点疑似被摘要化：非空白字符=$($nodeBody.Length)，下限=130。"
            }
            foreach ($pattern in @('\d{2,3}mm', '镜头|机位|推|拉|摇|移|环绕|跟|俯|仰|切|冲', '占画面|画面上|画面下|画面左|画面右|前景|中景|后景', '碎|尘|光|雾|风|地面|锁链|衣|发|声|震|纸|台|石|空气')) {
                if ($nodeBody -notmatch $pattern) {
                    Add-Issue $issues 'ERROR' 'ACTION_NODE_COMPONENT' $shotId "时间节点缺少必填可见信息：$pattern"
                }
            }
            if ($nodeBody -notmatch '隐形剪辑点|擦镜|糊镜|白闪|爆闪|甩镜模糊|烟尘.*镜头|碎片.*镜头|前景.*遮') {
                Add-Issue $issues 'ERROR' 'ACTION_NODE_CUT' $shotId '每个2秒工业句法节点必须提供可执行的隐形剪辑点。'
            }
        }

        foreach ($wovenRequirement in @('空间|轴线|站位', '承接|尾帧|衔接', '环境音|声音|音效', '穿模|穿过|肢体')) {
            if ($outputBlock -notmatch $wovenRequirement) {
                Add-Issue $issues 'ERROR' 'ACTION_WOVEN_REQUIREMENT' $shotId "四段式遗漏应织入的信息：$wovenRequirement"
            }
        }

        $negativeStart = [regex]::Match($outputBlock, '(?ms)###\s*④\s*负面提示词\s*\r?\n+\s*(?<body>[^\r\n]+)')
        if (-not $negativeStart.Success -or -not $negativeStart.Groups['body'].Value.StartsWith('禁止背景音乐！！！')) {
            Add-Issue $issues 'ERROR' 'ACTION_NO_BGM_PREFIX' $shotId '打戏/法术第④段必须以“禁止背景音乐！！！”开头。'
        }
        $withoutRequiredPrefix = $outputBlock -replace '禁止背景音乐！！！', ''
        if ($withoutRequiredPrefix -match 'BGM|背景音乐|配乐|战斗主题|旋律') {
            Add-Issue $issues 'ERROR' 'ACTION_BGM_PRESENT' $shotId '打戏/法术正文仍包含背景音乐或配乐安排。'
        }

        foreach ($forbiddenField in @('**空间锁定**', '**上镜衔接**', '**隐形剪辑点**', '**环境音**', '**穿模检查**')) {
            if ($outputBlock.Contains($forbiddenField)) {
                Add-Issue $issues 'ERROR' 'ACTION_EXTRA_SECTION' $shotId "打戏/法术四段式出现独立板块：$forbiddenField"
            }
        }
    }
    else {
        foreach ($field in @('画质基准', '场景', '角色', '空间锁定', '上镜衔接', '隐形剪辑点', '环境音', '穿模检查', '负面提示词')) {
            if ($outputBlock -notmatch [regex]::Escape($field)) {
                Add-Issue $issues 'ERROR' 'DRAMA_FORMAT' $shotId "文戏镜头缺少字段：$field"
            }
        }

        $timeNodes = [regex]::Matches($outputBlock, '(?m)^(?:\*\*)?\d{2}:\d{2}(?:\.\d+)?[—-]\d{2}:\d{2}(?:\.\d+)?|^\d+(?:\.\d+)?至\d+(?:\.\d+)?秒').Count
        if ($timeNodes -lt 3) {
            Add-Issue $issues 'ERROR' 'DRAMA_TIME_NODES' $shotId "文戏时间轴少于3个节点：实际=$timeNodes。"
        }
    }

    $dialogueMatches = [regex]::Matches(
        $sourceBlock,
        '\[(?<voiceTag>[^\]\r\n]+｜开口)\]：[“"](?<dialogue>[^”"]+)[”"]'
    )

    $seenDialogue = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($dialogueMatch in $dialogueMatches) {
        $dialogue = $dialogueMatch.Groups['dialogue'].Value
        if (-not $seenDialogue.Add($dialogue)) {
            continue
        }
        if (-not $outputBlock.Contains($dialogue)) {
            Add-Issue $issues 'ERROR' 'DIALOGUE_MISMATCH' $shotId "对白未逐字保留：$dialogue"
        }
        $voiceTag = $dialogueMatch.Groups['voiceTag'].Value
        $requiredVoiceLabel = "[$voiceTag]"
        if (-not $outputBlock.Contains($requiredVoiceLabel)) {
            Add-Issue $issues 'ERROR' 'DIALOGUE_VOICE_LABEL' $shotId "对白缺少基准剧本中的完整声音标签：$requiredVoiceLabel"
        }
    }

    if ($outputBlock -notmatch '负面提示词') {
        Add-Issue $issues 'ERROR' 'NEGATIVE_PROMPT' $shotId '缺少本镜负面提示词。'
    }

    $focalCount = [regex]::Matches($outputBlock, '\d{2,3}mm').Count
    if ($focalCount -lt 3) {
        Add-Issue $issues 'WARNING' 'LOW_CAMERA_DENSITY' $shotId "焦段/镜头描述偏少：仅$focalCount处。"
    }
}

$errorCount = @($issues | Where-Object Level -eq 'ERROR').Count
$warningCount = @($issues | Where-Object Level -eq 'WARNING').Count

if ($issues.Count -gt 0) {
    $table = $issues | Sort-Object Level, Shot, Code | Format-Table -AutoSize | Out-String
    Write-Host $table
}

Write-Host ''
Write-Host "V10校验结果：ERROR=$errorCount WARNING=$warningCount 剧本镜头=$($screenplayShots.Count) 输出镜头=$($outputShots.Count)"

if ($errorCount -gt 0) {
    exit 1
}

exit 0
