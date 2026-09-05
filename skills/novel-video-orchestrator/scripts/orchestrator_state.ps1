param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('Init', 'SetStage', 'RegisterArtifact', 'SetShot', 'Validate', 'Summary')]
    [string]$Action,

    [Parameter(Mandatory = $true)]
    [string]$ChapterDirectory,

    [string]$ProjectName,
    [int]$ChapterNumber,

    [ValidateSet('screenplay', 'character_prompts', 'scene_prompts', 'prop_prompts', 'image_production', 'asset_manifest', 'v10_prompts', 'video_production', 'chapter_audit', 'editing')]
    [string]$Stage,

    [ValidateSet('pending', 'in_progress', 'completed', 'blocked', 'not_enabled')]
    [string]$Status,

    [string]$ArtifactPath,

    [ValidatePattern('^S\d{2}$')]
    [string]$ShotId,

    [ValidateSet('pending', 'generating', 'qa_approved', 'approved_with_minor_issues', 'retryable', 'dependency_recheck', 'blocked')]
    [string]$ShotStatus,

    [ValidateRange(0, 2)]
    [int]$Attempt,

    [ValidatePattern('^$|^S\d{2}$')]
    [string]$DependsOn,

    [ValidateSet('pending', 'passed', 'failed', 'not_applicable')]
    [string]$TechnicalQa,

    [ValidateSet('pending', 'passed', 'failed', 'not_applicable')]
    [string]$RiskQa,

    [ValidateSet('pending', 'passed', 'failed', 'not_applicable')]
    [string]$TailGate,

    [ValidateSet('pending', 'passed', 'failed', 'not_applicable')]
    [string]$BatchQa,

    [string]$DependencySignature,
    [string]$Message
)

$ErrorActionPreference = 'Stop'
$resolvedChapter = [System.IO.Path]::GetFullPath($ChapterDirectory)
if (-not (Test-Path -LiteralPath $resolvedChapter -PathType Container)) {
    throw "Chapter directory not found: $resolvedChapter"
}
$statePath = Join-Path $resolvedChapter 'chapter_pipeline_state.json'

function Get-Now {
    return [DateTimeOffset]::Now.ToString('o')
}

function New-StageState([string]$InitialStatus = 'pending') {
    return [pscustomobject][ordered]@{
        status = $InitialStatus
        artifacts = @()
        updated_at = $null
        message = $null
    }
}

function Write-State($State) {
    $State.updated_at = Get-Now
    $json = $State | ConvertTo-Json -Depth 100
    $tempPath = "$statePath.tmp"
    [System.IO.File]::WriteAllText($tempPath, $json, [System.Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $tempPath -Destination $statePath -Force
}

function Read-State {
    if (-not (Test-Path -LiteralPath $statePath -PathType Leaf)) {
        throw "State file not found. Run Init first: $statePath"
    }
    return Get-Content -LiteralPath $statePath -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 100
}

function Add-Event($State, [string]$Kind, [string]$Target, [string]$EventMessage) {
    $event = [pscustomobject][ordered]@{
        at = Get-Now
        kind = $Kind
        target = $Target
        message = $EventMessage
    }
    $State.events = @($State.events) + @($event)
}

if ($Action -eq 'Init') {
    if (Test-Path -LiteralPath $statePath -PathType Leaf) {
        Write-Output "EXISTS=$statePath"
        return
    }
    if ([string]::IsNullOrWhiteSpace($ProjectName)) { throw 'ProjectName is required for Init.' }
    if (-not $PSBoundParameters.ContainsKey('ChapterNumber')) { throw 'ChapterNumber is required for Init.' }

    $state = [pscustomobject][ordered]@{
        schema_version = 'novel-video-orchestrator-state-v1'
        project = $ProjectName
        chapter = $ChapterNumber
        chapter_directory = $resolvedChapter
        created_at = Get-Now
        updated_at = Get-Now
        execution_policy = [pscustomobject][ordered]@{
            per_submission_confirmation = $false
            max_attempts_per_asset = 2
            max_attempts_per_shot = 2
            full_qa_batch_size = 3
            minor_issues = 'accept_and_record'
            editing = 'not_enabled'
        }
        stages = [pscustomobject][ordered]@{
            screenplay = (New-StageState)
            character_prompts = (New-StageState)
            scene_prompts = (New-StageState)
            prop_prompts = (New-StageState)
            image_production = (New-StageState)
            asset_manifest = (New-StageState)
            v10_prompts = (New-StageState)
            video_production = (New-StageState)
            chapter_audit = (New-StageState)
            editing = (New-StageState 'not_enabled')
        }
        shots = [pscustomobject]@{}
        events = @()
    }
    Add-Event $state 'init' 'chapter' '初始化章节总控状态。'
    Write-State $state
    Write-Output "CREATED=$statePath"
    return
}

$state = Read-State

if ($Action -eq 'SetStage') {
    if ([string]::IsNullOrWhiteSpace($Stage) -or [string]::IsNullOrWhiteSpace($Status)) {
        throw 'Stage and Status are required for SetStage.'
    }
    if ($Stage -eq 'editing' -and $Status -ne 'not_enabled') {
        throw 'Editing is not enabled in the current workflow.'
    }
    $stageState = $state.stages.$Stage
    $stageState.status = $Status
    $stageState.updated_at = Get-Now
    if ($PSBoundParameters.ContainsKey('Message')) { $stageState.message = $Message }
    $eventMessage = ("status=$Status $Message").Trim()
    Add-Event $state 'stage' $Stage $eventMessage
    Write-State $state
    Write-Output "STAGE=$Stage STATUS=$Status"
    return
}

if ($Action -eq 'RegisterArtifact') {
    if ([string]::IsNullOrWhiteSpace($Stage) -or [string]::IsNullOrWhiteSpace($ArtifactPath)) {
        throw 'Stage and ArtifactPath are required for RegisterArtifact.'
    }
    $resolvedArtifact = [System.IO.Path]::GetFullPath($ArtifactPath)
    if (-not (Test-Path -LiteralPath $resolvedArtifact -PathType Leaf)) {
        throw "Artifact not found: $resolvedArtifact"
    }
    $artifact = [pscustomobject][ordered]@{
        path = $resolvedArtifact
        sha256 = (Get-FileHash -LiteralPath $resolvedArtifact -Algorithm SHA256).Hash
        registered_at = Get-Now
    }
    $existing = @($state.stages.$Stage.artifacts | Where-Object { $_.path -ne $resolvedArtifact })
    $state.stages.$Stage.artifacts = $existing + @($artifact)
    if ($state.stages.$Stage.status -eq 'pending') { $state.stages.$Stage.status = 'in_progress' }
    $state.stages.$Stage.updated_at = Get-Now
    Add-Event $state 'artifact' $Stage $resolvedArtifact
    Write-State $state
    Write-Output "ARTIFACT=$resolvedArtifact SHA256=$($artifact.sha256)"
    return
}

if ($Action -eq 'SetShot') {
    if ([string]::IsNullOrWhiteSpace($ShotId)) { throw 'ShotId is required for SetShot.' }
    $property = $state.shots.PSObject.Properties[$ShotId]
    if ($null -eq $property) {
        $shot = [pscustomobject][ordered]@{
            status = 'pending'
            attempt = 0
            depends_on = $null
            technical_qa = 'pending'
            risk_qa = 'pending'
            tail_gate = 'pending'
            batch_qa = 'pending'
            dependency_signature = $null
            message = $null
            updated_at = $null
        }
        $state.shots | Add-Member -NotePropertyName $ShotId -NotePropertyValue $shot
    }
    else {
        $shot = $property.Value
    }

    if ($PSBoundParameters.ContainsKey('ShotStatus')) { $shot.status = $ShotStatus }
    if ($PSBoundParameters.ContainsKey('Attempt')) { $shot.attempt = $Attempt }
    if ($PSBoundParameters.ContainsKey('DependsOn')) { $shot.depends_on = if ($DependsOn -eq '') { $null } else { $DependsOn } }
    if ($PSBoundParameters.ContainsKey('TechnicalQa')) { $shot.technical_qa = $TechnicalQa }
    if ($PSBoundParameters.ContainsKey('RiskQa')) { $shot.risk_qa = $RiskQa }
    if ($PSBoundParameters.ContainsKey('TailGate')) { $shot.tail_gate = $TailGate }
    if ($PSBoundParameters.ContainsKey('BatchQa')) { $shot.batch_qa = $BatchQa }
    if ($PSBoundParameters.ContainsKey('DependencySignature')) { $shot.dependency_signature = $DependencySignature }
    if ($PSBoundParameters.ContainsKey('Message')) { $shot.message = $Message }
    $shot.updated_at = Get-Now
    $eventMessage = ("status=$($shot.status) attempt=$($shot.attempt) $Message").Trim()
    Add-Event $state 'shot' $ShotId $eventMessage
    Write-State $state
    Write-Output "SHOT=$ShotId STATUS=$($shot.status) ATTEMPT=$($shot.attempt)"
    return
}

if ($Action -eq 'Validate') {
    $errors = [System.Collections.Generic.List[string]]::new()
    if ($state.schema_version -ne 'novel-video-orchestrator-state-v1') { $errors.Add('Unsupported schema_version.') }
    foreach ($stageProperty in $state.stages.PSObject.Properties) {
        $stageName = $stageProperty.Name
        $stageState = $stageProperty.Value
        if ($stageName -eq 'editing' -and $stageState.status -ne 'not_enabled') {
            $errors.Add('editing must remain not_enabled.')
        }
        if ($stageState.status -eq 'completed' -and @($stageState.artifacts).Count -eq 0) {
            $errors.Add("$stageName is completed but has no registered artifact.")
        }
        foreach ($artifact in @($stageState.artifacts)) {
            if (-not (Test-Path -LiteralPath $artifact.path -PathType Leaf)) {
                $errors.Add("$stageName artifact missing: $($artifact.path)")
                continue
            }
            $actual = (Get-FileHash -LiteralPath $artifact.path -Algorithm SHA256).Hash
            if ($actual -ne $artifact.sha256) { $errors.Add("$stageName artifact hash mismatch: $($artifact.path)") }
        }
    }
    foreach ($shotProperty in $state.shots.PSObject.Properties) {
        if ([int]$shotProperty.Value.attempt -gt [int]$state.execution_policy.max_attempts_per_shot) {
            $errors.Add("$($shotProperty.Name) exceeds max_attempts_per_shot.")
        }
    }
    Write-Output "STATE=$statePath ERRORS=$($errors.Count)"
    foreach ($errorMessage in $errors) { Write-Output "ERROR: $errorMessage" }
    if ($errors.Count -gt 0) { throw 'State validation failed.' }
    return
}

if ($Action -eq 'Summary') {
    Write-Output "PROJECT=$($state.project) CHAPTER=$($state.chapter)"
    foreach ($stageProperty in $state.stages.PSObject.Properties) {
        Write-Output "STAGE=$($stageProperty.Name) STATUS=$($stageProperty.Value.status) ARTIFACTS=$(@($stageProperty.Value.artifacts).Count)"
    }
    foreach ($shotProperty in $state.shots.PSObject.Properties | Sort-Object Name) {
        $shot = $shotProperty.Value
        Write-Output "SHOT=$($shotProperty.Name) STATUS=$($shot.status) ATTEMPT=$($shot.attempt) TECH=$($shot.technical_qa) RISK=$($shot.risk_qa) TAIL=$($shot.tail_gate) BATCH=$($shot.batch_qa)"
    }
    return
}
