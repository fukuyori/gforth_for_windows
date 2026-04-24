param(
    [string]$BootstrapExe,
    [string]$StageDir = "$(Join-Path (Get-Location) 'build/installer/stage')",
    [switch]$SkipNative
)

$ErrorActionPreference = "Stop"
$RepoRoot = (Get-Location).Path

if (-not $SkipNative) {
    $nativeArgs = @{}
    if ($BootstrapExe) {
        $nativeArgs.BootstrapExe = $BootstrapExe
    }
    & (Join-Path $RepoRoot "scripts/build-native.ps1") @nativeArgs
    if ($LASTEXITCODE -ne 0) {
        throw "Native release build failed."
    }
}

$nativeExe = Join-Path $RepoRoot "build/native/gforth.exe"
$nativeImage = Join-Path $RepoRoot "build/native/gforth.fi"
if (-not (Test-Path $nativeExe) -or -not (Test-Path $nativeImage)) {
    throw "Missing build/native/gforth.exe or build/native/gforth.fi. Run scripts/build-release.ps1 without -SkipNative first."
}

$advancedImageBuilder = Join-Path $RepoRoot "scripts/build-advanced-interactive-image.ps1"
& $advancedImageBuilder -NativeExe $nativeExe -OutputImage (Join-Path $RepoRoot "build/native/gforth-advanced.fi") -IncludeHistory
if ($LASTEXITCODE -ne 0) {
    throw "Native advanced interactive image build failed."
}

& (Join-Path $RepoRoot "scripts/stage-native-dist.ps1") -StageDir $StageDir -Clean
if ($LASTEXITCODE -ne 0) {
    throw "Release staging failed."
}

$stageExe = Join-Path $StageDir "gforth.exe"
$stageAdvancedImage = Join-Path $StageDir "gforth-advanced.fi"
& $advancedImageBuilder -NativeExe $stageExe -OutputImage $stageAdvancedImage -IncludeHistory
if ($LASTEXITCODE -ne 0) {
    throw "Staged advanced interactive image build failed."
}
if (-not (Test-Path $stageAdvancedImage)) {
    throw "Advanced interactive image was not created at $stageAdvancedImage."
}

Write-Host "Release build staged at $StageDir" -ForegroundColor Green
