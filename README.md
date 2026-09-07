# 小说转视频工作流

当前实际使用的 8 个 Skill、专用 Chrome 启动配置、Playwright MCP 执行工具及图片/视频文件处理脚本的完整快照。图片通过 ChatGPT 网页生成，视频通过豆包网页生成，暂不包含剪辑流程。

Skill 来自当前已安装目录；当前分支包含已记录的 v12.6 更新及小说转剧本流水线门禁优化。`SNAPSHOT.json` 记录归档文件的 SHA-256，可检查快照完整性。

## v12.6 更新说明

本分支已将视频提示词生成器更新为 `video-prompts-v12` 12.6.0，并同步了与它配合的剧本、图片、豆包制作、总控 Skill 及 Playwright MCP 工具。详细变更、与旧版的差异及验证结果见 [v12.6 变更说明](docs/video-prompts-v12.6-changes.md)。

## 小说转剧本流水线门禁更新

`novel-to-screenplay` 已补充有效表演密度、关键动作可拆镜检查、跨场状态继承及原文歧义门禁；`novel-video-orchestrator` 会读取新版审计状态，阻止未解决的制作级歧义流入资产和逐镜阶段。详见 [novel-to-screenplay v2.1 变更说明](docs/novel-to-screenplay-v2.1-changes.md)。

## 流程与目录

小说 → 基准剧本 → 人物/场景/道具提示词 → ChatGPT 网页生图 → 资产登记 → 小家 v12.6 视频提示词 → 豆包逐镜生成 → 下载、检查、尾帧、进度记录。

| 路径 | 用途 |
| --- | --- |
| `skills/novel-video-orchestrator` | 总控、依赖检查、分段审核和断点续做 |
| `skills/novel-to-screenplay` | 小说转完整基准剧本 |
| `skills/character-image-prompts` | 人物图片提示词与三视图模板 |
| `skills/scene-image-prompts` | 场景图片提示词 |
| `skills/prop-image-prompts` | 道具图片提示词 |
| `skills/chatgpt-image-production` | ChatGPT 网页图片生产、下载、命名、登记 |
| `skills/video-prompts-v12` | 当前小家 v12.6 完整多文件规则及校验脚本 |
| `skills/doubao-video-production` | 豆包参考图映射、提交、下载、检查与尾帧登记 |
| `tools/doubao-playwright-mcp` | 豆包 MCP 启动脚本、连接测试、依赖及锁文件 |
| `tools/chatgpt-image-playwright-mcp` | ChatGPT MCP、可恢复图片执行器、下载恢复及页面诊断工具 |
| `config/codex-mcp.example.toml` | 当前两套 MCP 的项目配置样例 |
| `scripts/` | 独立尾帧提取、指定时间抽帧与联系表脚本 |
| `shared/scripts/` | 共享资产清单校验 |

## 环境和恢复部署

这是 Windows/PowerShell 工作流快照，不是免配置安装包。需要 PowerShell 7、Node.js、pnpm、Google Chrome；视频检查后端还使用 Microsoft Edge。可选的 Python 联系表脚本需要 Pillow。

1. 将 `skills/` 下的 8 个文件夹复制到目标 AI 客户端的 Skill 目录。Codex 默认为用户目录下 `.codex/skills/`。覆盖已有版本前先备份。
2. 原机器的工具部署位置是 `D:\jimeng\novel-video-tools`，将 `tools/` 下两个目录部署到该处；浏览器运行数据根目录是 `D:\jimeng\novel-video-browser`，首次启动时创建。
3. 在两个工具目录分别运行 `pnpm install --frozen-lockfile`，恢复锁定的依赖。Playwright MCP 版本为 `0.0.80`，依赖源码和 `node_modules` 不在仓库中。
4. 把 `config/codex-mcp.example.toml` 中对应的两个 MCP 配置段合并进项目 `.codex/config.toml`，不要覆盖其他服务配置；其他支持 STDIO MCP 的客户端使用相同启动脚本注册服务。
5. 检查脚本中的 Node.js、Chrome 和工作目录路径。原始快照保留了 `C:\Users\Y\...` 和 `D:\jimeng\...`；换机器时必须调整，特别是 `start-mcp.cmd`、`start-image-worker.cmd`、`image-worker.cjs`、`image-worker-control.ps1` 和图片下载恢复脚本。Skill 文档中的绝对部署路径也需对应更新。
6. `playwright_video_backend.cjs` 可通过环境变量 `CODEX_PLAYWRIGHT_PATH` 指向已安装的 Playwright 模块目录；默认使用原机器的 Codex 依赖路径。其他独立抽帧脚本也保留了原始模块路径。
7. 重新加载客户端 MCP 后打开对应专用浏览器，首次在新机器上由用户手工登录。两个专用用户目录分别为 `doubao-profile`、`chatgpt-image-profile`，以后保留在本机即可复用登录状态。

ChatGPT 图片执行器使用本机 `127.0.0.1:34191`，Chrome CDP 使用 `127.0.0.1:34192`。MCP 直连模式与图片执行器不可同时争用同一 Chrome 用户目录。连接测试会真实启动浏览器，应在没有生产任务占用该目录时运行。

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
