param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('init', 'set', 'summary')]
    [string]$Action,

    [Parameter(Mandatory = $true)]
    [string]$ManifestPath,

    [Parameter(Mandatory = $true)]
    [string]$ProgressPath,

    [ValidatePattern('^S\d{2}$')]
    [string]$ShotId,

    [ValidateSet('pending', 'assets_ready', 'uploading', 'submitted', 'generating', 'downloaded', 'qa_approved', 'retryable', 'blocked', 'failed')]
    [string]$Status,

    [string]$VideoPath,
    [string]$Account,
    [string]$Message
)

$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) { throw "Manifest not found: $ManifestPath" }
$manifest = Get-Content -Raw -LiteralPath $ManifestPath | ConvertFrom-Json -Depth 100

function Save-Progress([object]$Progress) {
    $directory = Split-Path -Parent $ProgressPath
    if (-not [string]::IsNullOrWhiteSpace($directory)) { [System.IO.Directory]::CreateDirectory($directory) | Out-Null }
    [System.IO.File]::WriteAllText([System.IO.Path]::GetFullPath($ProgressPath), ($Progress | ConvertTo-Json -Depth 100), [System.Text.UTF8Encoding]::new($false))
}

if ($Action -eq 'init') {
    if (Test-Path -LiteralPath $ProgressPath -PathType Leaf) {
        Write-Output "EXISTS=$([System.IO.Path]::GetFullPath($ProgressPath))"
        exit 0
    }
    $shots = [ordered]@{}
    foreach ($property in $manifest.shots.PSObject.Properties) {
        $shots[$property.Name] = [ordered]@{ status = 'pending'; video_path = $null; updated_at = $null; message = $null }
    }
    $progress = [ordered]@{
        schema_version = 'doubao-video-progress-v1'
        project = $manifest.project
        chapter = $manifest.chapter.number
        created_at = [DateTimeOffset]::Now.ToString('o')
        updated_at = [DateTimeOffset]::Now.ToString('o')
        shots = $shots
        events = @()
    }
    Save-Progress $progress
    Write-Output "INITIALIZED=$([System.IO.Path]::GetFullPath($ProgressPath)) SHOTS=$($shots.Count)"
    exit 0
}

if (-not (Test-Path -LiteralPath $ProgressPath -PathType Leaf)) { throw 'Progress file does not exist. Run init first.' }
$progress = Get-Content -Raw -LiteralPath $ProgressPath | ConvertFrom-Json -Depth 100

if ($Action -eq 'summary') {
    $rows = foreach ($property in $progress.shots.PSObject.Properties) {
        [pscustomobject]@{ Shot = $property.Name; Status = $property.Value.status; Video = $property.Value.video_path }
    }
    $rows | Format-Table -AutoSize
    exit 0
}

if ([string]::IsNullOrWhiteSpace($ShotId) -or [string]::IsNullOrWhiteSpace($Status)) { throw 'set requires -ShotId and -Status.' }
$shotProperty = $progress.shots.PSObject.Properties[$ShotId]
if ($null -eq $shotProperty) { throw "Shot not found in progress: $ShotId" }

$now = [DateTimeOffset]::Now.ToString('o')
$shotProperty.Value.status = $Status
$shotProperty.Value.updated_at = $now
if (-not [string]::IsNullOrWhiteSpace($VideoPath)) { $shotProperty.Value.video_path = [System.IO.Path]::GetFullPath($VideoPath) }
if (-not [string]::IsNullOrWhiteSpace($Message)) { $shotProperty.Value.message = $Message }
$progress.updated_at = $now
$event = [pscustomobject][ordered]@{ at = $now; shot = $ShotId; status = $Status; account = $Account; message = $Message }
$progress.events = @($progress.events) + $event
Save-Progress $progress
Write-Output "UPDATED=$ShotId STATUS=$Status"
