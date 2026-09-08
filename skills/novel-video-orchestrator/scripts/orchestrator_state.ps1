param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('Init', 'EnableEditing', 'SetStage', 'RegisterArtifact', 'SetShot', 'Validate', 'Summary')]
    [string]$Action,

    [Parameter(Mandatory = $true)]
    [string]$ChapterDirectory,

    [string]$ProjectName,
    [int]$ChapterNumber,

    [switch]$DisableEditing,

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

function Assert-ScreenplayReady($State) {
    $audit = $null
    foreach ($artifact in @($State.stages.screenplay.artifacts)) {
        if (-not (Test-Path -LiteralPath $artifact.path -PathType Leaf)) { continue }
        if ((Get-FileHash -LiteralPath $artifact.path -Algorithm SHA256).Hash -ne $artifact.sha256) { continue }
        try { $candidate = Get-Content -LiteralPath $artifact.path -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 100 }
        catch { continue }
        if ($candidate.schema_version -eq 'screenplay-trigger-audit-v2') { $audit = $candidate; break }
    }
    if ($null -eq $audit) { throw 'Screenplay completion requires a registered, unchanged screenplay-trigger-audit-v2 artifact.' }
    if ($null -eq $audit.downstream_gate) { throw 'Screenplay audit is missing downstream_gate.' }
    $blocking = @($audit.downstream_gate.blocking_ambiguities)
    if ($audit.downstream_gate.status -ne 'ready' -or $blocking.Count -gt 0) {
        $ids = @($blocking | ForEach-Object { [string]$_.id }) -join ', '
        throw "Screenplay downstream gate is not ready. Resolve blocking ambiguities first: $ids"
    }
}

function Assert-VideoPromptReady($State) {
    if ($State.execution_policy.video_prompt_validation -ne 'required') { return }

    $auditArtifact = $null
    $reportArtifact = $null
    foreach ($artifact in @($State.stages.v10_prompts.artifacts)) {
        if (-not (Test-Path -LiteralPath $artifact.path -PathType Leaf)) { continue }
        if ((Get-FileHash -LiteralPath $artifact.path -Algorithm SHA256).Hash -ne $artifact.sha256) { continue }
        if ([System.IO.Path]::GetFileName($artifact.path) -eq 'video_prompt_compliance_audit.json') { $auditArtifact = $artifact }
        if ([System.IO.Path]::GetFileName($artifact.path) -eq 'video_prompt_validation.json') { $reportArtifact = $artifact }
    }
    if ($null -eq $auditArtifact -or $null -eq $reportArtifact) {
        throw 'Video prompt completion requires registered, unchanged compliance-audit and validation-report artifacts.'
    }

    try { $audit = Get-Content -LiteralPath $auditArtifact.path -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 100 }
    catch { throw 'Video prompt compliance audit is not valid JSON.' }
    try { $report = Get-Content -LiteralPath $reportArtifact.path -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 100 }
    catch { throw 'Video prompt validation report is not valid JSON.' }

    if ($audit.schema_version -ne 'video-prompt-compliance-audit-v1' -or $audit.rule_version -ne '12.6.0') {
        throw 'Video prompt compliance audit must use schema video-prompt-compliance-audit-v1 and rule_version 12.6.0.'
    }
    if ($report.schema_version -ne 'video-prompt-validation-v1' -or $report.rule_version -ne '12.6.0' -or
        $report.status -ne 'passed' -or @($report.errors).Count -ne 0) {
        throw 'Video prompt validation report must be v12.6, passed, and contain zero errors.'
    }
    if ([string]::IsNullOrWhiteSpace([string]$report.prompt_directory) -or
        -not (Test-Path -LiteralPath $report.prompt_directory -PathType Container)) {
        throw 'Video prompt validation report points to a missing prompt directory.'
    }
    if ([string]::IsNullOrWhiteSpace([string]$report.chapter_prompt_path) -or
        -not (Test-Path -LiteralPath $report.chapter_prompt_path -PathType Leaf) -or
        [System.IO.Path]::GetExtension([string]$report.chapter_prompt_path) -ne '.md') {
        throw 'Video prompt validation report points to a missing complete chapter Markdown file.'
    }
    $chapterPromptArtifact = $null
    foreach ($artifact in @($State.stages.v10_prompts.artifacts)) {
        if ([System.IO.Path]::GetFullPath([string]$artifact.path) -eq [System.IO.Path]::GetFullPath([string]$report.chapter_prompt_path)) {
            $chapterPromptArtifact = $artifact
            break
        }
    }
    if ($null -eq $chapterPromptArtifact) { throw 'Complete chapter video-prompt Markdown must be registered as a stage artifact.' }
    $chapterPromptHash = (Get-FileHash -LiteralPath $report.chapter_prompt_path -Algorithm SHA256).Hash
    if ($chapterPromptHash -ne [string]$chapterPromptArtifact.sha256 -or
        $chapterPromptHash -ne [string]$report.chapter_prompt_sha256) {
        throw 'Complete chapter video-prompt Markdown changed after validation or registration.'
    }
    if ([System.IO.Path]::GetFullPath([string]$report.audit_path) -ne [System.IO.Path]::GetFullPath([string]$auditArtifact.path)) {
        throw 'Video prompt validation report does not reference the registered compliance audit.'
    }

    $reportShots = @($report.shots)
    if ($reportShots.Count -eq 0) { throw 'Video prompt validation report contains no shots.' }
    foreach ($shot in $reportShots) {
        if ([string]$shot.shot_id -notmatch '^S\d{2}$') { throw 'Video prompt validation report contains an invalid shot id.' }
        $promptPath = Join-Path ([string]$report.prompt_directory) ("$($shot.shot_id).txt")
        if (-not (Test-Path -LiteralPath $promptPath -PathType Leaf)) { throw "Validated prompt is missing: $promptPath" }
        if ((Get-FileHash -LiteralPath $promptPath -Algorithm SHA256).Hash -ne [string]$shot.sha256) {
            throw "Validated prompt changed after validation: $promptPath"
        }
        if ([double]$shot.duration_seconds -le 0) { throw "Validated shot duration must be positive: $($shot.shot_id)" }
    }
}

function Assert-EditingReady($State, [switch]$Completed) {
    if ($State.execution_policy.editing -ne 'enabled') {
        throw 'Editing is disabled. Use EnableEditing for this chapter when requested.'
    }
    foreach ($upstream in @('video_production', 'chapter_audit')) {
        if ($State.stages.$upstream.status -ne 'completed') {
            throw "Editing requires completed upstream stage: $upstream"
        }
    }
    if (-not $Completed) { return }
    $validReport = $false
    foreach ($artifact in @($State.stages.editing.artifacts)) {
        if (-not (Test-Path -LiteralPath $artifact.path -PathType Leaf)) { continue }
        if ((Get-FileHash -LiteralPath $artifact.path -Algorithm SHA256).Hash -ne $artifact.sha256) { continue }
        try { $report = Get-Content -LiteralPath $artifact.path -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 100 }
        catch { continue }
        if ($report.schema_version -ne 'jianying-editing-review-v1') { continue }
        if ([string]::IsNullOrWhiteSpace($report.chapter_directory) -or
            [System.IO.Path]::GetFullPath($report.chapter_directory) -ne $resolvedChapter) { continue }
        if ([string]::IsNullOrWhiteSpace($report.draft.name) -or
            [string]::IsNullOrWhiteSpace($report.subtitle_preset) -or
            [string]::IsNullOrWhiteSpace($report.verified_at) -or
            ($report.shot_count -isnot [long] -and $report.shot_count -isnot [int])) { continue }
        if ($report.shot_count -lt 1 -or
            ($report.subtitle_count -isnot [long] -and $report.subtitle_count -isnot [int]) -or
            $report.subtitle_count -lt 0) { continue }
        if ($null -eq $report.unresolved_issues -or @($report.unresolved_issues).Count -ne 0 -or
            $null -eq $report.evidence -or @($report.evidence).Count -eq 0 -or
            @($report.evidence | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }).Count -eq 0) { continue }
        $allPassed = $true
        foreach ($check in @('shot_order', 'original_audio', 'subtitle_text', 'subtitle_timing', 'preset_all', 'saved_reopened', 'editable')) {
            if ($report.checks.$check -isnot [bool] -or $report.checks.$check -ne $true) { $allPassed = $false }
        }
        if ($allPassed) { $validReport = $true }
    }
    if (-not $validReport) { throw 'Editing completion requires a registered, unchanged, fully passed editing review with evidence and no unresolved issues.' }
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
            editing = $(if ($DisableEditing) { 'not_enabled' } else { 'enabled' })
            video_prompt_validation = 'required'
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
            editing = (New-StageState $(if ($DisableEditing) { 'not_enabled' } else { 'pending' }))
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

if ($Action -eq 'EnableEditing') {
    if ($state.execution_policy.editing -eq 'enabled' -and $state.stages.editing.status -ne 'not_enabled') {
        Write-Output "EDITING_ALREADY_ENABLED=$statePath"
        return
    }
    $state.execution_policy.editing = 'enabled'
    if ($state.stages.editing.status -eq 'not_enabled') { $state.stages.editing.status = 'pending' }
    $state.stages.editing.updated_at = Get-Now
    Add-Event $state 'enable_editing' 'editing' '启用本章剪映排片与原声字幕制作。'
    Write-State $state
    Write-Output "EDITING_ENABLED=$statePath"
    return
}

if ($Action -eq 'SetStage') {
    if ([string]::IsNullOrWhiteSpace($Stage) -or [string]::IsNullOrWhiteSpace($Status)) {
        throw 'Stage and Status are required for SetStage.'
    }
    if ($Status -eq 'not_enabled' -and $Stage -ne 'editing') { throw 'not_enabled is only valid for editing.' }
    if ($Stage -eq 'screenplay' -and $Status -eq 'completed') {
        Assert-ScreenplayReady $state
    }
    if ($Stage -eq 'v10_prompts' -and $Status -eq 'completed') {
        Assert-VideoPromptReady $state
    }
    if ($Stage -eq 'video_production' -and $Status -in @('in_progress', 'completed')) {
        Assert-VideoPromptReady $state
    }
    if ($Stage -ne 'screenplay' -and $Stage -ne 'editing' -and $Status -in @('in_progress', 'completed')) {
        if ($state.stages.screenplay.status -ne 'completed') { throw "$Stage requires completed screenplay stage." }
        Assert-ScreenplayReady $state
    }
    if ($Stage -eq 'editing') {
        if ($state.execution_policy.editing -ne 'enabled' -and $Status -ne 'not_enabled') {
            throw 'Editing is disabled. Use EnableEditing for this chapter when requested.'
        }
        if ($state.execution_policy.editing -eq 'enabled' -and $Status -eq 'not_enabled') {
            throw 'Do not disable an enabled chapter using SetStage.'
        }
        if ($Status -in @('in_progress', 'completed')) {
            Assert-EditingReady $state -Completed:($Status -eq 'completed')
        }
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
        if ($stageName -eq 'editing') {
            if ($state.execution_policy.editing -eq 'enabled') {
                if ($stageState.status -notin @('pending', 'in_progress', 'completed', 'blocked')) {
                    $errors.Add('Enabled editing has an invalid status.')
                }
                if ($stageState.status -in @('in_progress', 'completed')) {
                    try { Assert-EditingReady $state -Completed:($stageState.status -eq 'completed') }
                    catch { $errors.Add($_.Exception.Message) }
                }
            }
            elseif ($stageState.status -ne 'not_enabled') { $errors.Add('Disabled editing must remain not_enabled.') }
        }
        if ($stageState.status -eq 'completed' -and @($stageState.artifacts).Count -eq 0) {
            $errors.Add("$stageName is completed but has no registered artifact.")
        }
        if ($stageName -eq 'v10_prompts' -and $stageState.status -eq 'completed') {
            try { Assert-VideoPromptReady $state }
            catch { $errors.Add($_.Exception.Message) }
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
