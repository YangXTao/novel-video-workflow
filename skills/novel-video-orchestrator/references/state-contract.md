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

普通阶段状态为 `pending`、`in_progress`、`completed` 或 `blocked`；`editing` 当前固定为 `not_enabled`。每个完成阶段至少登记一个能够证明完成的正式产物及其SHA-256。

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

豆包账号每日已确认创建次数记录在 `video_progress.json` 的账号用量节点和事件中。只有官方确认任务创建才递增；达到项目配置的每日上限后标记为当日已用完。特殊账号列表只保存在项目级配置，不进入通用 Skill。

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
