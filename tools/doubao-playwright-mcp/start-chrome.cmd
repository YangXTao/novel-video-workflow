@echo off
setlocal

set "TASK_CHROME=C:\Program Files\Google\Chrome\Application\chrome.exe"
set "TASK_PROFILE=D:\jimeng\novel-video-browser\doubao-profile"
set "TASK_PORT=9223"

if not exist "%TASK_CHROME%" exit /b 4
if not exist "%TASK_PROFILE%" mkdir "%TASK_PROFILE%"

powershell -NoProfile -ExecutionPolicy Bypass -Command "$ready=Test-NetConnection -ComputerName 127.0.0.1 -Port %TASK_PORT% -InformationLevel Quiet -WarningAction SilentlyContinue; if(-not $ready){Start-Process -FilePath '%TASK_CHROME%' -ArgumentList '--remote-debugging-port=%TASK_PORT%','--user-data-dir=%TASK_PROFILE%','--mute-audio','--new-window','https://www.doubao.com/chat/' -WindowStyle Hidden; for($i=0;$i -lt 12 -and -not $ready;$i++){Start-Sleep -Milliseconds 500; $ready=Test-NetConnection -ComputerName 127.0.0.1 -Port %TASK_PORT% -InformationLevel Quiet -WarningAction SilentlyContinue}}; if($ready){exit 0}else{exit 1}"
if errorlevel 1 exit /b 1
exit /b 0
