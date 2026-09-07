@echo off
setlocal

set "TASK_NODE=C:\Users\Y\.cache\codex-runtimes\codex-primary-runtime\dependencies\node\bin\node.exe"
set "TASK_SERVER=D:\jimeng\novel-video-tools\doubao-playwright-mcp\node_modules\@playwright\mcp\cli.js"
set "TASK_CHROME=C:\Program Files\Google\Chrome\Application\chrome.exe"
set "TASK_PROFILE=D:\jimeng\novel-video-browser\doubao-profile"
set "TASK_OUTPUT=D:\jimeng\novel-video-browser\artifacts"

if not exist "%TASK_NODE%" (
  echo Bundled Node.js not found: %TASK_NODE% 1>&2
  exit /b 2
)
if not exist "%TASK_SERVER%" (
  echo Playwright MCP not installed: %TASK_SERVER% 1>&2
  exit /b 3
)
if not exist "%TASK_CHROME%" (
  echo Google Chrome not found: %TASK_CHROME% 1>&2
  exit /b 4
)
if not exist "%TASK_PROFILE%" mkdir "%TASK_PROFILE%"
if not exist "%TASK_OUTPUT%" mkdir "%TASK_OUTPUT%"

"%TASK_NODE%" "%TASK_SERVER%" ^
  --executable-path "%TASK_CHROME%" ^
  --user-data-dir "%TASK_PROFILE%" ^
  --output-dir "%TASK_OUTPUT%" ^
  --config "D:\jimeng\novel-video-tools\doubao-playwright-mcp\display-config.json" ^
  --timeout-action 10000 ^
  --timeout-navigation 90000 ^
  --timeout-settle 1000
