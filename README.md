# 小说转视频工作流

面向 Codex 的小说视频工作流 Skill 集合。图片通过 ChatGPT 网页生成，视频通过豆包网页生成；网页操作复用 Codex 当前已加载的两个 Playwright MCP，不部署仓库中的旧 MCP 副本。

当前分支包含 v13.1.1 规则源、配额检查器、规则源接线和小说转剧本流水线门禁。`SNAPSHOT.json` 记录当前归档文件的 SHA-256，可检查快照完整性。

## v13.1.1 规则源接线（当前分支 `v13.0-alpha`）

视频提示词阶段不在入口内联规则，而由 `video-prompts-v13` 定位并校验同一工作流包中的独立 `xiaojia-prompt-generator` v13.1.1 Skill，把工作流输入原样交给它、把唯一完整章节 Markdown 原样接回。安装到 `~/.codex/skills/` 后两个 Skill 保持同级；项目配置和环境变量仍可显式覆盖规则源路径。

要点：输出名为 `<章节名>_完整视频提示词.md`（要时间戳或多版本时追加 `_<YYYYMMDD_HHMM>`，**不绑规则版本号**）；入口禁止精简、禁止自创、禁止用摘要替代剧本；规则源缺失或版本不符时停机，不回落其他版本。总控、剧本桥接、图片提示词、豆包制作的引用已同步指向 v13 入口。

详见 [v13.1.1 规则源接线说明](docs/video-prompts-v13-rules-wiring.md)。本分支只保留 v13.1.1 这一套规则源入口与文档。

## 小说转剧本流水线门禁更新

`novel-to-screenplay` 已补充有效表演密度、关键动作可拆镜检查、跨场状态继承及原文歧义门禁；`novel-video-orchestrator` 会读取新版审计状态，阻止未解决的制作级歧义流入资产和逐镜阶段。详见 [novel-to-screenplay v2.1 变更说明](docs/novel-to-screenplay-v2.1-changes.md)。

## 流程与目录

小说 → 基准剧本 → 人物/场景/道具提示词 → ChatGPT 网页生图 → 资产登记 → 小家 v13.1.1 视频提示词（`video-prompts-v13` 委派同级规则 Skill）→ 豆包逐镜生成 → 下载、检查、尾帧、进度记录。

| 路径 | 用途 |
| --- | --- |
| `skills/novel-video-orchestrator` | 总控、依赖检查、分段审核和断点续做 |
| `skills/novel-to-screenplay` | 小说转完整基准剧本 |
| `skills/character-image-prompts` | 人物图片提示词与三视图模板 |
| `skills/scene-image-prompts` | 场景图片提示词 |
| `skills/prop-image-prompts` | 道具图片提示词 |
| `skills/chatgpt-image-production` | ChatGPT 网页图片生产、下载、命名、登记 |
| `skills/video-prompts-v13` | **当前视频提示词入口**：定位并校验小家 v13.1.1 Skill，委派执行 |
| `skills/xiaojia-prompt-generator` | v13.1.1 独立规则源，正文只读 |
| `skills/storyboard-quota-check` | 视频提示词出稿后的 A–I 配额检查 |
| `skills/doubao-video-production` | 豆包参考图映射、提交、下载、检查与尾帧登记 |
| `tools/*-playwright-mcp` | 历史 MCP 源码快照；Codex 适配版不部署、不启动 |
| `config/codex-mcp.example.toml` | 历史配置样例；不覆盖当前 Codex MCP 配置 |
| `scripts/` | 独立尾帧提取、指定时间抽帧与联系表脚本 |
| `shared/scripts/` | 历史共享资产校验；当前流程使用豆包 Skill 内支持 AssetsOnly/Production 的校验脚本 |

## Codex安装与运行

这是 Windows/PowerShell 工作流。运行脚本需要 PowerShell 7；配额检查需要 Codex 工作区依赖提供的 Python 或当前环境可用的 Python。

1. 覆盖任何当前 Skill 前先备份 `%USERPROFILE%\.codex\skills\` 中对应目录。
2. 将 `skills/` 下各 Skill 目录原样安装到 `%USERPROFILE%\.codex\skills\`，保持 `video-prompts-v13`、`xiaojia-prompt-generator` 和 `storyboard-quota-check` 同级。
3. 不安装 `tools/` 下的两个 MCP，不覆盖 Codex 配置；确认当前 Codex 会话已能调用 `chatgpt_image_playwright` 和 `doubao_playwright`。
4. 使用 `pwsh` 运行仓库测试。视频检查脚本如需 Playwright 模块，可通过 `CODEX_PLAYWRIGHT_PATH` 指向当前 Codex 依赖路径。
5. 首次网页生产时在 Codex 当前 MCP 打开的可见浏览器中由用户完成登录。登录、验证码和安全校验不由工作流绕过。

## 下载、命名与连续性

- 图片制作脚本在 `skills/chatgpt-image-production/scripts/`，完整资产规则见同 Skill 的 `references/asset-contract.md`。
- 图片执行器及恢复下载工具在 `tools/chatgpt-image-playwright-mcp/`。先查询原任务账本与原会话，再恢复下载，避免重复生成。
- 视频正式文件使用 `<章号>-Sxx.mp4`；候选使用 `<章号>-Sxx-候选NN.mp4`；重制使用 `<章号>-Sxx-重制-vN.mp4`。
- 合格尾帧使用 `<章号>-Sxx-tail.png`，经 `register_tail_frame.ps1` 登记后才可供下一镜映射。`resolve_shot_bindings.ps1` 根据真实资产分配参考图编号。
- 视频网页下载和扩展下载兼容流程完整保留在 `skills/doubao-video-production/references/workflow.md`。去水印助手属于用户另行安装的第三方扩展，本仓库不包含该扩展程序；需要扩展功能时自行安装原扩展。
- 进度由 `image_progress.ps1`、`video_progress.ps1`、`orchestrator_state.ps1` 管理。实际项目的进度、素材和成片留在章节工作目录，不提交此仓库。

## 归档范围与限制

包含 Skill 原文、当前配套脚本、依赖声明和锁文件、浏览器启动方式及 MCP 配置。Chrome/Edge 程序本体由官方安装包提供。

不包含账号凭据、Cookie、浏览器用户目录、任务账本、运行日志、截图、小说正文、生成图片视频、历史备份、第三方扩展和依赖二进制。

本次仅进行文件完整性、脚本语法、配置与提交内容检查；没有在新机器上进行登录或消耗额度的端到端生成测试。网页定位与平台功能可能变化，运行时仍需按当前页面检查。保留的规则文本可能含既有跨文件约定差异，归档本身不等于新增功能或规则修订。
