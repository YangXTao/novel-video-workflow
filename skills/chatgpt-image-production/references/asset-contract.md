# 图片资产契约

## 任务文件

`image_jobs.json` 使用 `chatgpt-image-jobs-v1`。每项至少包含：

- `asset_id`：原提示词中的资产编号；
- `name`：资产中文名；
- `type`：`character`、`scene` 或 `prop`；
- `applicable_shots`：原文件声明的适用分镜；
- `prompt`：从原Markdown逐字提取的完整提示词；
- `prompt_sha256`：UTF-8提示词哈希；
- `reference_paths`：实际存在的参考图路径；
- `action`：`generate` 或 `reuse`；
- `target_file_path`：正式图片的稳定目标路径。

禁止人工复制提示词后再重新概括。提交前重新计算哈希；不一致时停止。

## 状态

- `pending`：尚未取得生成授权；
- `assets_ready`：提示词、参考图和目标路径已核对；
- `authorized`：用户已授权本次一次生成；
- `uploading`：正在上传参考图；
- `submitted`：网页已确认创建任务；
- `generating`：正在等待结果；
- `downloaded`：结果已进入稳定路径，尚未完成质检；
- `qa_approved`：文件和视觉质检均通过；
- `retryable`：结果已知失败；有有效章节级运行授权且尚未达到2次上限时可以自动重试一次，否则等待处理；
- `blocked`：需要用户登录、验证码、付费、修订或其他外部处理；
- `reuse_approved`：现有资产文件和哈希已核验；
- `failed`：不可恢复失败。

## 登记规则

已有 `asset_manifest.json` 时直接更新其中同名资产节点，不改写无关资产和镜头。没有完整资产清单时登记到章节 `image_asset_registry.json`；总控在资产阶段把已审核条目合并为只有资产也可成立的asset_manifest.json，不交给视频提示词Skill合并。此时applicable_shots可为空，SC关联另行保留；视频制作阶段收到最终章节Markdown后才建立shots、body_reference_bindings和尾帧依赖。

只有 `qa_approved` 的生成结果才能登记为 `approved`。仅下载但未视觉检查的结果为 `generated_unreviewed`。复用资产必须验证文件存在且哈希一致后登记为 `reuse_approved`。

已存在的 `approved` 或 `reuse_approved` 资产如果哈希不同，禁止静默覆盖；为新结果分配新的版本化资产编号和文件名。

## 文件角色与命名

- 新建正式图：`<资产编号>-<资产名称>.png`；这是清单引用的稳定路径。
- 同次生成候选：`<资产编号>-<资产名称>-候选NN.png`；所有原始候选均保留。
- 选中候选：复制到正式路径后登记哈希，不删除原始候选。
- 内容更新：提升资产编号中的版本号后生成新的正式文件，旧版本继续保留。
- 历史复用资产：保持现有文件名，清单记录真实路径，不因新命名规范强制改名。

`image_jobs.json.target_file_path` 只能指向稳定正式路径，不能指向 `-候选NN` 文件。`image_progress.json` 可以另外记录候选路径，但 `qa_approved` 的 `output_file` 必须是正式路径。
