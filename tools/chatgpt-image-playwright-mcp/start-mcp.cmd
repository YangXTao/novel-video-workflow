@echo off
setlocal

set "TASK_NODE=C:\Users\Y\.cache\codex-runtimes\codex-primary-runtime\dependencies\node\bin\node.exe"
set "TASK_SERVER=D:\jimeng\novel-video-tools\chatgpt-image-playwright-mcp\node_modules\@playwright\mcp\cli.js"
set "TASK_OUTPUT=D:\jimeng\novel-video-browser\chatgpt-image-artifacts"

if not exist "%TASK_NODE%" (
  echo Bundled Node.js not found: %TASK_NODE% 1>&2
  exit /b 2
)
if not exist "%TASK_SERVER%" (
  echo Playwright MCP not installed: %TASK_SERVER% 1>&2
  exit /b 3
)

if not exist "%TASK_OUTPUT%" mkdir "%TASK_OUTPUT%"

rem MCP initialization only registers tools. Explicit image work starts Chrome separately.

"%TASK_NODE%" "%TASK_SERVER%" ^
  --cdp-endpoint "http://127.0.0.1:34192" ^
  --output-dir "%TASK_OUTPUT%" ^
  --config "D:\jimeng\novel-video-tools\chatgpt-image-playwright-mcp\display-config.json" ^
  --timeout-action 10000 ^
  --timeout-navigation 90000 ^
  --timeout-settle 1000
