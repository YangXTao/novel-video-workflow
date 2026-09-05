param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('init', 'set', 'summary')]
    [string]$Action,

    [Parameter(Mandatory = $true)]
    [string]$JobsPath,

    [Parameter(Mandatory = $true)]
    [string]$ProgressPath,

    [string]$AssetId,

    [ValidateSet('pending', 'assets_ready', 'authorized', 'uploading', 'submitted', 'generating', 'downloaded', 'qa_approved', 'retryable', 'blocked', 'reuse_approved', 'failed')]
    [string]$Status,

    [string]$OutputFile,
    [string]$Account,
    [string]$Message
)

$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $JobsPath -PathType Leaf)) { throw "Jobs file not found: $JobsPath" }
$jobsDoc = Get-Content -Raw -LiteralPath $JobsPath -Encoding UTF8 | ConvertFrom-Json -Depth 100
if ($jobsDoc.schema_version -ne 'chatgpt-image-jobs-v1') { throw "Unsupported jobs schema: $($jobsDoc.schema_version)" }

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
    $assets = [ordered]@{}
    foreach ($job in @($jobsDoc.jobs)) {
        $initial = if ($job.action -eq 'reuse') { 'reuse_approved' } else { 'pending' }
        $assets[$job.asset_id] = [ordered]@{
            name = $job.name
            status = $initial
            attempts = 0
            output_file = if ($initial -eq 'reuse_approved') { $job.target_file_path } else { $null }
            updated_at = $null
            message = $null
        }
    }
    $progress = [ordered]@{
        schema_version = 'chatgpt-image-progress-v1'
        created_at = [DateTimeOffset]::Now.ToString('o')
        updated_at = [DateTimeOffset]::Now.ToString('o')
        assets = $assets
        events = @()
    }
    Save-Progress $progress
    Write-Output "INITIALIZED=$([System.IO.Path]::GetFullPath($ProgressPath)) ASSETS=$($assets.Count)"
    exit 0
}

if (-not (Test-Path -LiteralPath $ProgressPath -PathType Leaf)) { throw 'Progress file does not exist. Run init first.' }
$progress = Get-Content -Raw -LiteralPath $ProgressPath -Encoding UTF8 | ConvertFrom-Json -Depth 100

if ($Action -eq 'summary') {
    foreach ($property in $progress.assets.PSObject.Properties) {
        [pscustomobject]@{ Asset = $property.Name; Name = $property.Value.name; Status = $property.Value.status; Attempts = $property.Value.attempts; File = $property.Value.output_file }
    }
    exit 0
}

if ([string]::IsNullOrWhiteSpace($AssetId) -or [string]::IsNullOrWhiteSpace($Status)) { throw 'set requires -AssetId and -Status.' }
$assetProperty = $progress.assets.PSObject.Properties[$AssetId]
if ($null -eq $assetProperty) { throw "Asset not found in progress: $AssetId" }
$now = [DateTimeOffset]::Now.ToString('o')
$assetProperty.Value.status = $Status
$assetProperty.Value.updated_at = $now
if ($Status -eq 'submitted') { $assetProperty.Value.attempts = [int]$assetProperty.Value.attempts + 1 }
if (-not [string]::IsNullOrWhiteSpace($OutputFile)) { $assetProperty.Value.output_file = [System.IO.Path]::GetFullPath($OutputFile) }
if (-not [string]::IsNullOrWhiteSpace($Message)) { $assetProperty.Value.message = $Message }
$progress.updated_at = $now
$progress.events = @($progress.events) + [pscustomobject][ordered]@{ at = $now; asset = $AssetId; status = $Status; account = $Account; message = $Message }
Save-Progress $progress
Write-Output "UPDATED=$AssetId STATUS=$Status"

