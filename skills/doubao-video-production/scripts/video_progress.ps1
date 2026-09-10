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
    [ValidateSet('extension_unwatermarked', 'user_authorized_alternative')]
    [string]$DownloadSource,
    [string]$DownloadEvidence,
    [ValidateSet('passed', 'watermark_present_user_authorized')]
    [string]$WatermarkCheck,
    [string]$WatermarkEvidence,
    [string]$UserAuthorization,
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
        $shots[$property.Name] = [ordered]@{
            status = 'pending'
            video_path = $null
            download_source = $null
            download_evidence = $null
            watermark_check = $null
            watermark_evidence = $null
            user_authorization = $null
            updated_at = $null
            message = $null
        }
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
$currentDownloadSource = if ($PSBoundParameters.ContainsKey('DownloadSource')) { $DownloadSource } else { [string]$shotProperty.Value.download_source }
$currentDownloadEvidence = if ($PSBoundParameters.ContainsKey('DownloadEvidence')) { $DownloadEvidence } else { [string]$shotProperty.Value.download_evidence }
$currentWatermarkCheck = if ($PSBoundParameters.ContainsKey('WatermarkCheck')) { $WatermarkCheck } else { [string]$shotProperty.Value.watermark_check }
$currentWatermarkEvidence = if ($PSBoundParameters.ContainsKey('WatermarkEvidence')) { $WatermarkEvidence } else { [string]$shotProperty.Value.watermark_evidence }
$currentUserAuthorization = if ($PSBoundParameters.ContainsKey('UserAuthorization')) { $UserAuthorization } else { [string]$shotProperty.Value.user_authorization }

if ($Status -eq 'qa_approved') {
    if ($currentDownloadSource -eq 'extension_unwatermarked') {
        if ([string]::IsNullOrWhiteSpace($currentDownloadEvidence) -or
            $currentWatermarkCheck -ne 'passed' -or
            [string]::IsNullOrWhiteSpace($currentWatermarkEvidence)) {
            throw 'qa_approved requires both bottom-right resource evidence and a passed multi-frame visual watermark check.'
        }
    }
    elseif ($currentDownloadSource -eq 'user_authorized_alternative') {
        if ([string]::IsNullOrWhiteSpace($currentDownloadEvidence) -or
            [string]::IsNullOrWhiteSpace($currentUserAuthorization) -or
            [string]::IsNullOrWhiteSpace($currentWatermarkCheck) -or
            [string]::IsNullOrWhiteSpace($currentWatermarkEvidence)) {
            throw 'Alternative download requires explicit user authorization, source evidence, and an honest visual watermark result.'
        }
    }
    else {
        throw 'qa_approved requires DownloadSource=extension_unwatermarked unless the user explicitly authorizes an alternative.'
    }
}

$shotProperty.Value.status = $Status
$shotProperty.Value.updated_at = $now
if (-not [string]::IsNullOrWhiteSpace($VideoPath)) {
    $resolvedVideoPath = [System.IO.Path]::GetFullPath($VideoPath)
    if ($null -eq $shotProperty.Value.PSObject.Properties['video_path']) {
        $shotProperty.Value | Add-Member -NotePropertyName video_path -NotePropertyValue $resolvedVideoPath
    } else {
        $shotProperty.Value.video_path = $resolvedVideoPath
    }
}
foreach ($field in @(
    @{ Name = 'download_source'; Value = $currentDownloadSource; Supplied = $PSBoundParameters.ContainsKey('DownloadSource') },
    @{ Name = 'download_evidence'; Value = $currentDownloadEvidence; Supplied = $PSBoundParameters.ContainsKey('DownloadEvidence') },
    @{ Name = 'watermark_check'; Value = $currentWatermarkCheck; Supplied = $PSBoundParameters.ContainsKey('WatermarkCheck') },
    @{ Name = 'watermark_evidence'; Value = $currentWatermarkEvidence; Supplied = $PSBoundParameters.ContainsKey('WatermarkEvidence') },
    @{ Name = 'user_authorization'; Value = $currentUserAuthorization; Supplied = $PSBoundParameters.ContainsKey('UserAuthorization') }
)) {
    if (-not $field.Supplied) { continue }
    if ($null -eq $shotProperty.Value.PSObject.Properties[$field.Name]) {
        $shotProperty.Value | Add-Member -NotePropertyName $field.Name -NotePropertyValue $field.Value
    } else {
        $shotProperty.Value.($field.Name) = $field.Value
    }
}
if (-not [string]::IsNullOrWhiteSpace($Message)) {
    if ($null -eq $shotProperty.Value.PSObject.Properties['message']) {
        $shotProperty.Value | Add-Member -NotePropertyName message -NotePropertyValue $Message
    } else {
        $shotProperty.Value.message = $Message
    }
}
$progress.updated_at = $now
$event = [pscustomobject][ordered]@{ at = $now; shot = $ShotId; status = $Status; account = $Account; message = $Message }
$progress.events = @($progress.events) + $event
Save-Progress $progress
Write-Output "UPDATED=$ShotId STATUS=$Status"
