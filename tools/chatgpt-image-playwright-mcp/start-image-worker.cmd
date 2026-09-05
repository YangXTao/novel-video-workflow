@echo off
setlocal
set "TASK_NODE=C:\Users\Y\.cache\codex-runtimes\codex-primary-runtime\dependencies\node\bin\node.exe"
set "TASK_WORKER=D:\jimeng\novel-video-tools\chatgpt-image-playwright-mcp\image-worker.cjs"
if not exist "%TASK_NODE%" exit /b 2
if not exist "%TASK_WORKER%" exit /b 3
"%TASK_NODE%" "%TASK_WORKER%"
