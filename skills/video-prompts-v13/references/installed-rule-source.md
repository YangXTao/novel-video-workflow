# v13.1.1 规则源：定位、校验与只读纪律

本文件描述 `video-prompts-v13` 如何找到并校验小家 v13.1.1 规则源。规则正文不内联到适配层；当前分支把它作为独立的同级 Skill 随工作流一并交付。

## 1. 定位顺序（固定，先命中先用）

1. **项目配置**：项目根目录 `novel_video_production_config.json` 中的
   `video_prompt_generation.rule_source`（绝对路径或 `~` 开头）与可选 `rule_source_version`。
2. **环境变量**：`XIAOJIA_SKILL_DIR`。
3. **同一工作流包内置规则源**：`video-prompts-v13` 的同级目录 `../xiaojia-prompt-generator`。仓库检出和安装到 `~/.codex/skills/` 后均保持该相对关系。
4. **Codex 用户级位置**：`~/.codex/skills/xiaojia-prompt-generator`。
5. **兼容回退位置**：`~/.workbuddy/skills/xiaojia-prompt-generator`。只在前四项都未命中时使用，不能覆盖当前分支自带规则。

命中目录后，必须同时存在 `SKILL.md` 与 `references/` 目录，才算定位成功。
在 Codex 中可直接按名加载 `xiaojia-prompt-generator`，但仍须完成第 2 步校验并记录同一份 SHA-256。若同时存在多个副本，以以上解析顺序命中的实际路径为唯一执行源；不得混用其他副本。

## 2. 校验项（缺一即停机）

| 项 | 要求 |
|---|---|
| SKILL.md 存在 | 必须 |
| `metadata.version` | 等于 `13.1.1`（或用户当次明确指定的更高版本） |
| `references/` 目录 | 存在且含 00/01/02/03/10/11/12/13/20/30/35/37/40/41/50/60/61/70/80/90/91/92/93/94/95/96/97/99/100 共 29 个现行规则文件 |
| `references/96-规则执行契约与证据回执.md` | 必须存在（执行契约入口，缺它不得生成） |
| SHA-256 | 记录为 `rule_sha256`，供剧本阶段 `screenplay_trigger_audit.json` 证据使用 |

校验命令：

```powershell
pwsh -NoProfile -File scripts/verify_rule_source.ps1            # 用默认解析顺序
pwsh -NoProfile -File scripts/verify_rule_source.ps1 -RuleSource "D:\path\to\xiaojia-prompt-generator"
pwsh -NoProfile -File scripts/verify_rule_source.ps1 -Json      # 机器可读，供上游写入审计
```

> 脚本以 UTF-8 **带 BOM** 保存，Windows PowerShell 5.1 与 pwsh 7 均可运行。原因：5.1 会把**无 BOM**的 `.ps1` 按系统 ANSI 代码页解码，脚本里的中文随即乱码，本脚本会直接抛参数绑定异常并以退出码 1 结束。编辑后请确认 BOM 仍在（仓库内其余含中文的 `.ps1` 同理）。

校验失败时：**停机报告实际路径、版本、缺失项；不得回落到其他版本的规则源，不得凭记忆复述规则**。

## 3. 只读纪律

- 只读：读取 SKILL.md 与 96 号契约点名的 `references/` 子节。
- 禁改：不得修改规则源任何文件；不得在其中新建、改名或删除文件。
- 禁抄：不得把规则正文复制进适配层、生成物目录或任何中间摘要文件。
- 禁缓存替换：不得另建"摘要规则 + 哈希"来代替现场读取；升级后重新读取、重新计算哈希。
- 版本漂移防护：作者发布 v13.x 更新时，本层无需改动，只要 `metadata.version` 仍满足要求即自动跟随。

## 4. 为什么必须是委派形态

| 项 | 内联单文件（已废弃形态） | 委派已安装规则源（当前） |
|---|---|---|
| 形态 | 全量规则内联成单个 SKILL.md | 总控 19 KB + `references/` 29 个文件，按 96 号契约按需读取 |
| 截断风险 | 高：单文件过长会被压缩/截断，导致规则丢失、输出精简 | 低：渐进式披露，逐子节读取并留证据 |
| 依赖与验收 | 无独立执行契约文件 | 同级规则 Skill 的 96 号执行契约 + 事实账本 + 缺口账本 + 规则卡 + 证据回执 + 100 号最终覆盖 |

新章节一律走 v13 入口；工作副本内不并存两套规则。
