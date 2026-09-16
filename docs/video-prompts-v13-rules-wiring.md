# v13.0 规则源接线说明（`v13.0-rules-wiring` 分支）

## 1. 目标

视频提示词阶段不再使用 v12.6 单文件母版，改为**委派已安装的小家 v13.0 skill**：

- 用户只需说"做第 N 章（或第 N–M 章）"，总控按依赖顺序调用各 Skill 与 MCP，产出剧本 → 三类图片提示词 → 图片与资产清单 → **完整章节视频提示词** → 逐镜视频。
- 视频提示词的规则来源是安装版 skill，**严格按 v13.0 执行，不精简、不自创、不替换**。
- 本仓库不含任何规则副本；安装版 skill 由作者维护，工作流自动跟随其升级。

## 2. 为什么必须换掉 v12.6

| | v12.6（旧入口） | v13.0（新入口） |
|---|---|---|
| 形态 | 781 KB 单文件母版直接作为 SKILL.md | 总控 SKILL.md（19 KB）+ `references/` 29 个规则文件 |
| 加载 | 超长必被压缩/截断 → 规则静默丢失、输出被精简 | 渐进式披露：按其 96 号执行契约先建依赖清单，再逐子节读取并留证据 |
| 执行保证 | 无独立契约文件，读到多少算多少 | 96 号执行契约 + 事实账本 + 缺口账本 + 规则卡 + 证据回执，最后读 100 号最终覆盖 |
| 打戏口径 | 12.9.2 之前 | v13.0 打戏句法对齐九处（曲线制呼吸点、张力铺垫三选一、四类功能母版、阶梯拉远计一次 EWS 等） |

## 3. 结构

```
skills/video-prompts-v13/                 ← 新增入口（薄适配层，不含规则）
├── SKILL.md                              定位/校验/执行流程/禁止事项/异常处理
├── references/installed-rule-source.md   规则源三步定位、校验项、只读纪律、与 v12.6 差异
├── references/output-and-handoff-contract.md  交付物命名、逐镜自包含、图号与参考图预算、连续性三分类
├── scripts/verify_rule_source.ps1        校验规则源并输出路径/版本/哈希（JSON 可用）
└── agents/openai.yaml                    入口默认提示词
```

> 旧入口 `skills/video-prompts-v12/`（781 KB 单文件母版）已从本分支移除；历史完整留存在 git 的 `v12.6-reference-budget` 分支，需要回退时从该分支取回。

## 4. 规则源定位顺序

1. 项目根 `novel_video_production_config.json` → `video_prompt_generation.rule_source`（可加 `rule_source_version`）
2. 环境变量 `XIAOJIA_SKILL_DIR`
3. 默认 `~/.workbuddy/skills/xiaojia-prompt-generator`

校验：`SKILL.md` 存在、`metadata.version` 达标（默认 `13.0`）、`references/` 含 29 个现行规则文件、96 号契约文件存在；输出 `rule_sha256` 供 `screenplay_trigger_audit.json` 使用。校验失败**停机**，不回落 v12.6。

```powershell
pwsh -NoProfile -File skills/video-prompts-v13/scripts/verify_rule_source.ps1 -Json
```

## 5. 已同步的耦合点

| 文件 | 改动 |
|---|---|
| `skills/novel-video-orchestrator/SKILL.md` | 调用顺序、输入直交、附加创作要求、接口说明、交付命名 → v13 入口 / `_完整视频提示词_v13.0.md` |
| `.../references/workflow.md` | 固定调用模板 `使用 $video-prompts-v13`、输入清单与交付说明中的版本标识 |
| `.../references/state-contract.md` | `v10_prompts` 阶段的默认文件名 |
| `.../references/duration-and-model-planning.md` | 规划权归属、命名、重拆回退对象 |
| `.../references/isolated-creative-tasks.md` | 独立上下文子任务适配的 Skill 列表 |
| `skills/novel-to-screenplay/SKILL.md`、`references/v12-trigger-bridge.md`、`scripts/test_screenplay_validator.ps1` | 触发桥接改读 v13 入口 + 规则源哈希；测试脚本改为调用 `verify_rule_source.ps1` 动态解析路径与版本 |
| `skills/character-image-prompts` / `scene-image-prompts` / `prop-image-prompts` | 下游规划方指向 v13 入口 |
| `skills/doubao-video-production`（SKILL + error-recovery-log + resolve_shot_bindings.ps1） | 超预算回交对象、恢复路径、错误提示 |
| `README.md`、`SNAPSHOT.json` | 分支说明、目录表、快照哈希 |

## 6. 不变项（刻意保持）

- 总控**不预写分镜、不锁秒数、不扫描资产目录**；分镜与秒数仍由视频提示词规则源独立规划。
- 完整正式剧本、已有设定、真实资产清单、时长/模型要求、项目级 `additional_directive` 仍是"完整输入直交"。
- 图片阶段仍不等 `scene_shot_map.json`；资产绑定仍由豆包阶段按真实上传顺序完成。
- 历史锁定章节沿用其既有产物，不自动追溯重写；需要按 v12.6 规则补做时，从 `v12.6-reference-budget` 分支取回旧入口，不在本分支并存两套规则。

## 7. 使用方式

新章节无需任何额外命令，仍是一句话：

```text
使用 $novel-video-orchestrator 制作第 12 章的视频
```

总控会自动走到视频提示词阶段并调用 v13 入口；若需指定其他章节范围、时长口径或模型，按原模板传入即可。规则源路径不在默认位置时，优先写进项目配置，而不是改 Skill。

## 8. 出稿后强制配额自检（工作流侧，不动规则源）

规则源只保证「规则怎么读、怎么落稿」，**不负责在出稿后回头数一遍**。因此本工作流在交付侧加了一道机械自检：

| 项 | 内容 |
|---|---|
| 合同 | `skills/video-prompts-v13/references/quota-selfcheck.md` |
| 脚本 | `storyboard-quota-check/scripts/quota_check.py`（已装为独立用户级 Skill，**不在本仓库内**） |
| 定位顺序 | 项目配置 `video_prompt_generation.quota_checker` → 环境变量 `XIAOJIA_QUOTA_CHECK` → 默认 `~/.workbuddy/skills/...`（WorkBuddy）/ `~/.codex/skills/...`（Codex） |
| 触发器 | 视频提示词阶段**出稿后必跑**；硬项非空不得交付，改完须重跑 |

已接入的耦合点（共 7 个文件）：

- `video-prompts-v13/SKILL.md`：执行流程新增第 7 步；输出合同与异常处理补条目；版本升 `13.0.0-wiring.2`
- `video-prompts-v13/references/output-and-handoff-contract.md`：交接检查增加「附自检结果」项 + 配额自检门禁
- `video-prompts-v13/references/quota-selfcheck.md`：**新增**，自检合同全文
- `novel-video-orchestrator/SKILL.md`：外围交接检查与唯一交付两条各补门禁
- `novel-video-orchestrator/references/workflow.md`：`v10_prompts` 阶段完成条件 + 固定调用模板新增「出稿后自检」行
- `novel-video-orchestrator/references/isolated-creative-tasks.md`：独立创作子任务的交付要求
- `novel-video-orchestrator/references/state-contract.md`：`v10_prompts` 阶段完成条件

**两道防线**：本层出稿后自己跑并把结果附在交付说明（流程契约）；总控接回后**独立重跑同一脚本**作门禁，两次结果应一致（机械校验，不是逐拍内容审计）。

**自检管不到的**：运镜动机闸、戏成立终审、剧本逐句映射、画质词是否真为 10 号 2.1 原文、正文是否泄漏内部口径——这些仍由本层按规则源 70 号与 96 号完成。自检通过不等于内容合规。

