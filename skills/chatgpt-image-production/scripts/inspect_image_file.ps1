param(
    [Parameter(Mandatory = $true)]
    [string]$ImagePath,

    [ValidateSet('landscape', 'portrait', 'any')]
    [string]$ExpectedOrientation = 'landscape',

    [int]$MinimumWidth = 512,
    [int]$MinimumHeight = 512
)

$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $ImagePath -PathType Leaf)) { throw "Image not found: $ImagePath" }

Add-Type -AssemblyName System.Drawing
$resolved = (Resolve-Path -LiteralPath $ImagePath).Path
$image = $null
try {
    $image = [System.Drawing.Image]::FromFile($resolved)
    $width = [int]$image.Width
    $height = [int]$image.Height
    $format = [string]$image.RawFormat
}
finally {
    if ($null -ne $image) { $image.Dispose() }
}

$orientation = if ($width -gt $height) { 'landscape' } elseif ($height -gt $width) { 'portrait' } else { 'square' }
$ratio = [Math]::Round($width / [double]$height, 4)
$errors = [System.Collections.Generic.List[string]]::new()
$warnings = [System.Collections.Generic.List[string]]::new()
if ($width -lt $MinimumWidth) { $errors.Add("width below minimum: $width < $MinimumWidth") }
if ($height -lt $MinimumHeight) { $errors.Add("height below minimum: $height < $MinimumHeight") }
if ($ExpectedOrientation -ne 'any' -and $orientation -ne $ExpectedOrientation) { $errors.Add("orientation mismatch: expected $ExpectedOrientation, got $orientation") }
if ($ExpectedOrientation -eq 'landscape' -and [Math]::Abs($ratio - (16.0 / 9.0)) -gt 0.15) { $warnings.Add("aspect ratio is not close to 16:9: $ratio") }

$result = [pscustomobject][ordered]@{
    path = $resolved
    readable = $true
    width = $width
    height = $height
    orientation = $orientation
    aspect_ratio = $ratio
    format = $format
    bytes = (Get-Item -LiteralPath $resolved).Length
    sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $resolved).Hash
    errors = @($errors)
    warnings = @($warnings)
}
$result | ConvertTo-Json -Depth 10
if ($errors.Count -gt 0) { exit 1 }

