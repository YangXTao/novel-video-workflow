# 总控状态契约

## 文件位置

每章固定使用 `<章节目录>\chapter_pipeline_state.json`。它只负责跨 Skill 汇总，不替代 `image_progress.json`、`asset_manifest.json` 或 `video_progress.json`。

## 阶段

必须包含：

- `screenplay`
- `character_prompts`
- `scene_prompts`
- `prop_prompts`
- `image_production`
- `asset_manifest`
- `v10_prompts`
- `video_production`
- `chapter_audit`
- `editing`

普通阶段状态为 `pending`、`in_progress`、`completed` 或 `blocked`。新章 execution_policy.editing 默认 enabled、stages.editing.status 默认 pending；初始化传 -DisableEditing 则两者为 not_enabled。已有状态保持不变，明确启用旧章剪辑时使用 -Action EnableEditing，将政策设为 enabled 并仅把 not_enabled 阶段变为 pending；重复调用不重置已有进度。每个完成阶段至少登记一个能够证明完成的正式产物及其SHA-256。新版 screenplay 完成还要求登记 `screenplay-trigger-audit-v2` 审计且 `downstream_gate.status=ready`；有阻断歧义时使用 blocked，不由总控或下游自行补设定。

editing 的 in_progress/completed 要求 video_production 和 chapter_audit 已完成。completed 还必须登记哈希匹配的 jianying-editing-review-v1 报告，草稿名称/章节身份明确、检查全部实际通过、证据非空且无未解决问题；详见 sibling jianying-editing/references/state-contract.md。脚本验证记录，不能代替实际剪映和听音验收。

## 镜头状态

`shots.Sxx` 至少记录：

- `status`：`pending`、`generating`、`qa_approved`、`approved_with_minor_issues`、`retryable`、`dependency_recheck` 或 `blocked`；
- `attempt`：正式提交次数，最大为2；未知结果不得增加次数；
- `depends_on`：依赖的上一镜编号，没有则为空；
- `technical_qa`：技术检查；
- `risk_qa`：硬伤快检；
- `tail_gate`：尾帧门禁；
- `batch_qa`：分段完整审核；
- `dependency_signature`：人物身份、关键状态、站位/方向、机位构图和结尾状态的简明事实摘要；
- `message`：失败原因或小瑕疵说明。

状态文件不保存账号密码、Cookie、令牌、浏览器存储或网页私密信息。

豆包实际视频创建事件保存在video_progress.json，同时以项目doubao_account_usage.json跨章汇总账号套餐、入口、请求/实际模型、时长、额度池、可见余额及重置证据。仅对实际创建任务去重计数，不把各模型/时长统计格视为相互独立额度池；未知数量/重置时间为null。不能统一套每日3次，也不能到午夜或等待几小时后盲目清零。特殊账号列表只保存在项目级配置，不进入通用Skill。字段与迁移规则以视频制作Skill的generation-routes-and-quota.md为准。

`v10_prompts`完成时只要求登记一个存在、未变化且包含连续S编号的完整章节视频提示词Markdown。默认文件名为`<章节名>_完整视频提示词_v12.6.md`；用户要求候选版本或对比测试时可追加时间戳。历史`shot_production_plan.json`、`scene_shot_map.json`、逐镜文件和`video_prompt_validation.json`可以保留，但不再是阶段完成条件。

每镜的target_duration_seconds由视频制作阶段从完整Markdown标题和时间轴读取，并在镜头或视频事件中记录entry_mode、requested_model、actual_model、model_evidence、model_policy和continuity_group。actual_model无证据为null，不因云电脑接受指令而虚构实际模型。满足视频制作Skill中用户报告的30秒独占能力推定条件时，可记录2.5并明确证据为inferred，不与页面直接显示混淆。

## 脚本使用

初始化：

```powershell
./scripts/orchestrator_state.ps1 -Action Init -ChapterDirectory <章节目录> -ProjectName <项目名> -ChapterNumber 38
```

登记阶段产物后置为完成：

```powershell
./scripts/orchestrator_state.ps1 -Action RegisterArtifact -ChapterDirectory <章节目录> -Stage screenplay -ArtifactPath <剧本文件>
./scripts/orchestrator_state.ps1 -Action SetStage -ChapterDirectory <章节目录> -Stage screenplay -Status completed
```

记录镜头检查：

```powershell
./scripts/orchestrator_state.ps1 -Action SetShot -ChapterDirectory <章节目录> -ShotId S01 -ShotStatus approved_with_minor_issues -Attempt 2 -TechnicalQa passed -RiskQa passed -TailGate passed -Message <说明>
```

恢复前：

```powershell
./scripts/orchestrator_state.ps1 -Action Validate -ChapterDirectory <章节目录>
./scripts/orchestrator_state.ps1 -Action Summary -ChapterDirectory <章节目录>
```
