param(
    # WSL distribution that has a full-image gforth, m4 and python3.
    # Default: the default WSL distribution.
    [string]$Distro,
    # Only regenerate the artifacts; skip the native rebuild and image copy.
    [switch]$SkipBuild
)

# Regenerates the bootstrap artifacts with a WSL Gforth
# (scripts/regen-bootstrap-wsl.sh), rebuilds the native engine without a
# bootstrap host, and installs the new kernel image as build/native/gforth.fi.
#
# Use after merging upstream changes to prim / kernel/ / startup libraries, and
# on a fresh clone.  See "Bootstrap Requirements After an Upstream Sync" in
# docs/WINDOWS-NATIVE.md.

$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path

$wslArgs = @()
if ($Distro) { $wslArgs += @("-d", $Distro) }

$wslRoot = (& wsl @wslArgs --exec wslpath -a $RepoRoot).Trim()
if ($LASTEXITCODE -ne 0 -or -not $wslRoot) {
    throw "Could not convert $RepoRoot to a WSL path. Is WSL installed?"
}

Write-Host "Regenerating bootstrap artifacts in WSL ($wslRoot)..." -ForegroundColor Cyan
& wsl @wslArgs --exec bash "$wslRoot/scripts/regen-bootstrap-wsl.sh"
if ($LASTEXITCODE -ne 0) {
    throw "WSL regeneration failed (exit $LASTEXITCODE)."
}

if ($SkipBuild) {
    Write-Host "Artifacts regenerated. Skipped the native build (-SkipBuild)." -ForegroundColor Green
    return
}

Set-Location $RepoRoot
& (Join-Path $PSScriptRoot "build-native.ps1") -SkipBootstrap
if ($LASTEXITCODE -ne 0) {
    throw "build-native.ps1 -SkipBootstrap failed (exit $LASTEXITCODE)."
}

Copy-Item -Force (Join-Path $RepoRoot "kernl64l.fi") (Join-Path $RepoRoot "build/native/gforth.fi")
Write-Host "Done: build/native/gforth.exe rebuilt, kernl64l.fi copied to build/native/gforth.fi." -ForegroundColor Green
Write-Host "Next: .\scripts\build-advanced-interactive-image.ps1 -IncludeHistory (or scripts\build-release.ps1 -SkipNative)" -ForegroundColor Gray
