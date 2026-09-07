# ChatGPT图片专用Playwright MCP

## 固定实现

- MCP名称：`chatgpt_image_playwright`，使用项目级STDIO MCP。
- 启动脚本：`D:\jimeng\novel-video-tools\chatgpt-image-playwright-mcp\start-mcp.cmd`。
- Chrome程序：`C:\Program Files\Google\Chrome\Application\chrome.exe`。
- 独立用户目录：`D:\jimeng\novel-video-browser\chatgpt-image-profile`。
- 浏览器产物目录：`D:\jimeng\novel-video-browser\chatgpt-image-artifacts`。
- 生图网站：`https://chatgpt.com/`。

该用户目录只供ChatGPT图片专用MCP使用，不与日常Chrome或豆包专用Chrome共用。由MCP启动有界面的Chrome并使用原持久化目录；不得同时启动两个使用同一目录的浏览器实例，不读取Cookie、密码、localStorage或其他浏览器存储。

本项目沿用原MCP链路，不自动改成worker、独立CDP服务、后台或无头浏览器。启动前核对Chrome进程所属Windows用户、交互会话和user-data-dir；专用Chrome应在持有该目录的原桌面用户下可见运行，不能用沙箱服务账号打开同一登录目录。不要因超时清空、复制替换或新建登录目录。配置目录存在不等于网站仍已登录，登录状态以可见页面为准。

页面应随实际窗口显示：启动配置使用 `browser.contextOptions.viewport: null` 和 `headless: false`，不固定小视口。已有窗口最小化时先恢复normal再最大化；只调整显示，不为修正灰边重启浏览器。配置文件更新只影响后续启动，当前窗口仍须核验。

## 首次连接

1. 确认 `chatgpt_image_playwright` MCP工具可用；已有页面时先列出标签页，不覆盖未完成任务。
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

- Codex重启或MCP传输关闭后，先检查现有MCP、Chrome和账本；保留仍运行的浏览器与原目录，不启动另一套控制器。工具恢复可用后，`submitted`、`generating`、`result_detected` 和 `result_unknown` 一律回到记录的原对话检查，不得创建新对话或重新提交。
- 下载阶段关闭、超时或未知时，重连独立Chrome并只恢复原对话下载；不增加生成次数。
- 只有登录失效、验证码、安全校验、订阅/额度页面或网页拒绝原始提示词时才设为 `blocked_user_action` 并请求用户处理。

## 安全锁

- 发送、生成、重新生成、创建变体均属于可能消耗额度的操作。
- 没有当前资产或当前批次的明确授权时不得点击。
- 登录、验证码、订阅购买、额度不足和账号切换交还用户处理。
- 网页只允许访问用户明确要求的ChatGPT生图相关页面。
