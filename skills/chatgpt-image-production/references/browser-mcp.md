# ChatGPT图片专用可恢复Playwright执行器

## 固定实现

- 执行器：`chatgpt-image-worker`，本地回环地址 `127.0.0.1:34191`，不得暴露到局域网或公网。
- 控制脚本：`D:\jimeng\novel-video-tools\chatgpt-image-playwright-mcp\image-worker-control.ps1`。
- 启动脚本：`D:\jimeng\novel-video-tools\chatgpt-image-playwright-mcp\start-image-worker.cmd`。
- Chrome程序：`C:\Program Files\Google\Chrome\Application\chrome.exe`。
- 独立用户目录：`D:\jimeng\novel-video-browser\chatgpt-image-profile`。
- 浏览器产物目录：`D:\jimeng\novel-video-browser\chatgpt-image-artifacts`。
- 生图网站：`https://chatgpt.com/`。

该用户目录只供ChatGPT图片制作执行器使用，不与日常Chrome或豆包专用Chrome共用。执行器以独立Chrome进程和CDP连接工作：Codex、MCP或执行器断开时只断控制连接，不关闭专用Chrome，不读取Cookie、密码、localStorage或其他浏览器存储。不得同时启动两个使用同一用户目录的浏览器实例。

## 首次连接

1. 调用控制脚本 `-Command start`，确认本地健康检查通过。
2. 打开 `https://chatgpt.com/`；第一次会出现独立Chrome窗口。
3. 如果未登录、出现验证码或安全校验，停止自动操作，让用户亲自完成。
4. 登录成功后只读取可见页面，确认账号和图片生成入口；不得读取、导出或保存密码、Cookie、localStorage、令牌或其他敏感浏览器存储。
5. 首次测试只选择一个非敏感资产，做到提交前预览；用户明确授权后再生成。

## 页面适配

每次操作使用当次可访问性快照和可见文本定位控件，不把未经验证的CSS选择器写入长期规则，不凭屏幕坐标猜测。

提交前核对：

- 当前位于新对话；
- 当前账号正确；
- 已上传参考图数量和文件正确；
- 输入框包含该资产完整原始提示词；
- 页面回读文本与任务中的提示词一致；
- 当前资产没有状态未知的重复任务。

生成完成后只在已打开的结果查看器内确认原图下载控件；不得点击页面中不具备明确下载语义的泛用“保存”按钮。下载事件出现后立即保存到稳定资产目录。

## 断线恢复

每个任务在任何外部点击前必须写入本地账本，至少包含原始提示词哈希、参考图真实路径、目标文件、任务状态和原ChatGPT对话地址。状态顺序为 `authorized → submitting → submitted → generating → result_detected → downloaded`。

- Codex重启、MCP传输关闭或执行器进程退出后，先启动执行器并查询账本；`submitted`、`generating`、`result_detected` 和 `result_unknown` 一律回到记录的原对话检查，不得创建新对话或重新提交。
- 下载阶段关闭、超时或未知时，重连独立Chrome并只恢复原对话下载；不增加生成次数。
- 只有登录失效、验证码、安全校验、订阅/额度页面或网页拒绝原始提示词时才设为 `blocked_user_action` 并请求用户处理。

## 安全锁

- 发送、生成、重新生成、创建变体均属于可能消耗额度的操作。
- 没有当前资产或当前批次的明确授权时不得点击。
- 登录、验证码、订阅购买、额度不足和账号切换交还用户处理。
- 网页只允许访问用户明确要求的ChatGPT生图相关页面。
