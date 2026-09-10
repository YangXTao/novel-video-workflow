$ErrorActionPreference = 'Stop'
$dir = Join-Path ([IO.Path]::GetTempPath()) ('submission-bindings-' + [guid]::NewGuid())
New-Item -ItemType Directory -Path $dir | Out-Null
$shell = (Get-Process -Id $PID).Path
$manifestPath = Join-Path $dir 'manifest.json'
$resultPath = Join-Path $dir 'bindings.json'
$resolver = Join-Path $PSScriptRoot 'resolve_shot_bindings.ps1'
$validator = Join-Path $PSScriptRoot 'validate_asset_manifest.ps1'
function SaveManifest { [IO.File]::WriteAllText($manifestPath, ($script:manifest | ConvertTo-Json -Depth 30)) }
function Assert($condition, $message) { if (!$condition) { throw $message } }
$assets = [ordered]@{}
foreach ($id in @('A','B','SCENE','TAIL')) {
    $path = Join-Path $dir "$id.fixture"
    [IO.File]::WriteAllText($path, "fixture-$id")
    $assets[$id] = @{name=$id;type='prop';status='approved';file_path=$path;sha256=(Get-FileHash $path).Hash}
}
$manifest = [ordered]@{schema_version='novel-video-asset-manifest-v1';reference_policy=@{eligible_statuses=@('approved','reuse_approved');max_images_per_shot=10};assets=$assets}
SaveManifest
& $shell -NoProfile -File $validator -ManifestPath $manifestPath -Stage AssetsOnly | Out-Null
Assert ($LASTEXITCODE -eq 0) 'Asset-only stage incorrectly requires shots.'
& $shell -NoProfile -File $validator -ManifestPath $manifestPath -Stage Production | Out-Null
Assert ($LASTEXITCODE -eq 1) 'Production accepted no shots.'
$body = "## S01`n【角色·场景·核心设定】`n角色甲=@image1，角色乙=@image2。`n【时间轴】`n完整动作、声线与对白。"
$originalBody = $body
$shot = @{static_reference_assets=@('B','SCENE','A');text_only_entities=@();body_reference_bindings=@{'@image1'='A';'@image2'='B'};tail_frame=@{eligible=$true;status='approved';source_shot='S00';asset_id_when_created='TAIL';file_path=$assets.TAIL.file_path;sha256=$assets.TAIL.sha256}}
$manifest.shots = [ordered]@{S01=$shot}
SaveManifest
$console = @(& $resolver -ManifestPath $manifestPath -ShotId S01 -PromptText $body -OutputPath $resultPath)
Assert (($console -join '|') -eq '@image3 = S00尾帧|@image4 = SCENE') 'Production stdout must contain supplemental mappings only.'
$result = Get-Content -Raw $resultPath | ConvertFrom-Json
Assert (($result.bindings.asset_id -join ',') -eq 'A,B,TAIL,SCENE') 'Body numbering was displaced by tail.'
Assert (($result.supplemental_legend -join '|') -eq '@image3 = S00尾帧|@image4 = SCENE') 'Supplement includes existing body mappings.'
$submission = "严格执行下方第48章S01提示词，不能改写或摘要！！！直接生成视频；完成后返回原始视频卡片及结果链接。`n禁止背景音乐！！！`n【补充参考图映射】`n" + ($result.supplemental_legend -join "`n") + "`n" + $body
Assert ($submission.EndsWith($originalBody, [StringComparison]::Ordinal)) 'Body was rewritten.'
Assert ($body -ceq $originalBody) 'Input body mutated.'
function ExpectBlocked($label, $text) {
    SaveManifest
    $blocked=$false
    try { & $resolver -ManifestPath $manifestPath -ShotId S01 -PromptText $text | Out-Null } catch { $blocked=$true }
    Assert $blocked "$label was not blocked."
}
$shot.body_reference_bindings['@image2']='A'
ExpectBlocked 'duplicate asset binding' $body
$shot.body_reference_bindings=@{'@image1'='A';'@image7'='B'}
ExpectBlocked 'sparse unfillable numbering' ($body.Replace('@image2','@image7'))
$shot.body_reference_bindings=@{'@image1'='A'}
ExpectBlocked 'unresolved body token' $body
$shot.body_reference_bindings=@{'@image1'='A';'@image2'='B'}
$assets.B.status='no_build'
ExpectBlocked 'unapproved asset' $body
$assets.B.status='approved'
$manifest.reference_policy.max_images_per_shot=3
ExpectBlocked 'upload limit' $body
$manifest.reference_policy.max_images_per_shot=10
$shot.tail_frame.eligible=$false
$shot.static_reference_assets=@('B','A')
SaveManifest
& $resolver -ManifestPath $manifestPath -ShotId S01 -PromptText $body -OutputPath $resultPath | Out-Null
$result=Get-Content -Raw $resultPath | ConvertFrom-Json
Assert (@($result.supplemental_legend).Count -eq 0) 'No supplemental images should produce no supplemental legend.'
$emptyConsole = @(& $resolver -ManifestPath $manifestPath -ShotId S01 -PromptText $body)
Assert ($emptyConsole.Count -eq 0) 'No supplemental mappings must produce empty stdout.'
$legacyConsole = @(& $resolver -ManifestPath $manifestPath -ShotId S01)
Assert ($legacyConsole.Count -eq 3) 'Legacy output compatibility changed.'
$shot.body_reference_bindings=@{}
SaveManifest
& $resolver -ManifestPath $manifestPath -ShotId S01 -PromptText '本镜没有既定图号。' -OutputPath $resultPath | Out-Null
$result=Get-Content -Raw $resultPath | ConvertFrom-Json
Assert (@($result.supplemental_legend).Count -eq 2) 'Unnumbered body must receive full supplemental legend.'
Write-Output "PASS: assets-only/production, preserved body numbering, tail, supplemental-only, immutable body, duplicate/sparse/missing binding, status, limit, empty/full supplement. Fixtures: $dir"
