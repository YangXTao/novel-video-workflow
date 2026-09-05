param(
  [Parameter(Mandatory=$true)][ValidateSet('start','health','jobs','enqueue','run','download','stop')][string]$Command,
  [string]$JobFile,
  [string]$JobId
)

$ErrorActionPreference = 'Stop'
$base = 'http://127.0.0.1:34191'
$root = 'D:\jimeng\novel-video-tools\chatgpt-image-playwright-mcp'
$launcher = Join-Path $root 'start-image-worker.cmd'
function Invoke-Worker([string]$Method, [string]$Path, $Body = $null) {
  $args = @{ Method = $Method; Uri = "$base$Path"; TimeoutSec = 15 }
  if ($null -ne $Body) { $args.ContentType = 'application/json; charset=utf-8'; $args.Body = ($Body | ConvertTo-Json -Depth 20 -Compress) }
  Invoke-RestMethod @args
}
function Ensure-Worker {
  try { return Invoke-Worker 'GET' '/health' } catch {}
  Start-Process -FilePath $launcher -WorkingDirectory $root -WindowStyle Hidden
  for ($i = 0; $i -lt 20; $i++) { Start-Sleep -Milliseconds 500; try { return Invoke-Worker 'GET' '/health' } catch {} }
  throw 'ChatGPT image worker did not become healthy within 10 seconds.'
}
switch ($Command) {
  'start' { Ensure-Worker | ConvertTo-Json -Depth 10 }
  'health' { Ensure-Worker | ConvertTo-Json -Depth 10 }
  'jobs' { Ensure-Worker | Out-Null; Invoke-Worker 'GET' '/jobs' | ConvertTo-Json -Depth 30 }
  'enqueue' {
    if (-not $JobFile) { throw '-JobFile is required for enqueue.' }
    $job = Get-Content -LiteralPath $JobFile -Raw | ConvertFrom-Json
    Ensure-Worker | Out-Null; Invoke-Worker 'POST' '/jobs' $job | ConvertTo-Json -Depth 30
  }
  'run' { if (-not $JobId) { throw '-JobId is required.' }; Ensure-Worker | Out-Null; Invoke-Worker 'POST' "/jobs/$([uri]::EscapeDataString($JobId))/run" | ConvertTo-Json -Depth 10 }
  'download' { if (-not $JobId) { throw '-JobId is required.' }; Ensure-Worker | Out-Null; Invoke-Worker 'POST' "/jobs/$([uri]::EscapeDataString($JobId))/download" | ConvertTo-Json -Depth 10 }
  'stop' { try { Invoke-Worker 'POST' '/shutdown' | ConvertTo-Json } catch { '{"stopping":false,"message":"worker not running"}' } }
}
