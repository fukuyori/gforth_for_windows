param(
    [string]$StageDir = "$(Join-Path (Get-Location) 'build/installer/stage')",
    [string]$OutputDir = "$(Join-Path (Get-Location) 'build/installer/output')",
    [string]$InnoCompiler,
    # Code-sign gforth.exe / gforth-ditc.exe (if not already signed), the
    # uninstaller and the setup exe, using the certificate named by CODESIGN_CERT.
    [switch]$Sign,
    [string]$TimestampUrl = ""
)

$ErrorActionPreference = "Stop"
$RepoRoot = (Get-Location).Path

$signTool = $null
if ($Sign) {
    . (Join-Path $PSScriptRoot "signing.ps1")
    $signTool = Assert-SignPrereqs
    if (-not $TimestampUrl) { $TimestampUrl = $script:DefaultTimestampUrl }
    Write-Host "Code signing enabled: /n `"$env:CODESIGN_CERT`"" -ForegroundColor Gray
}

function Get-PackageVersion {
    $line = Select-String -Path "configure.ac" -Pattern "AC_INIT\(\[gforth\],\[([^\]]+)\]" | Select-Object -First 1
    if (-not $line) {
        throw "Could not determine PACKAGE_VERSION from configure.ac"
    }
    return $line.Matches[0].Groups[1].Value
}

function Resolve-InnoCompiler {
    param([string]$ExplicitPath)

    if ($ExplicitPath) {
        return (Resolve-Path $ExplicitPath).Path
    }

    $candidates = @(
        (Join-Path ${env:ProgramFiles(x86)} "Inno Setup 6\ISCC.exe"),
        (Join-Path ${env:ProgramFiles} "Inno Setup 6\ISCC.exe")
    ) | Where-Object { $_ -and (Test-Path $_) }

    return $candidates | Select-Object -First 1
}

$requiredStageFiles = @(
    "gforth.exe",
    "gforth-ditc.exe",
    "gforth.fi",
    "gforth-advanced.fi",
    "generate-advanced.ps1",
    "gforth-advanced.cmd"
)

foreach ($file in $requiredStageFiles) {
    $path = Join-Path $StageDir $file
    if (-not (Test-Path $path)) {
        throw "Missing staged release file: $path. Run scripts/build-release.ps1 first."
    }
}

$iscc = Resolve-InnoCompiler -ExplicitPath $InnoCompiler
if (-not $iscc) {
    Write-Warning "Inno Setup compiler (ISCC.exe) was not found. The staged layout is ready at $StageDir."
    Write-Warning "Install Inno Setup 6 and rerun this script, or pass -InnoCompiler <path-to-ISCC.exe>."
    exit 0
}

# Sign the staged executables so the installed files carry one signature
if ($Sign) {
    foreach ($exe in @("gforth.exe", "gforth-ditc.exe")) {
        Invoke-CodeSign -SignTool $signTool -Path (Join-Path $StageDir $exe) -TimestampUrl $TimestampUrl -SkipIfSigned
    }
}

New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
$version = Get-PackageVersion
$issPath = Join-Path $RepoRoot "installer/gforth-native.iss"
$stageArg = "/DStageDir=$StageDir"
$versionArg = "/DAppVersion=$version"
$outputArg = "/DOutputDir=$OutputDir"

$isccArgs = @($stageArg, $versionArg, $outputArg)
if ($Sign) {
    # /DSign activates the SignTool/SignedUninstaller directives in gforth-native.iss;
    # Inno Setup then signs both the uninstaller and the setup exe with this command
    # ($q = literal quote, $f = file to sign).
    $isccArgs += "/DSign"
    $isccArgs += "/Ssigntool=`$q$signTool`$q sign /n `$q$env:CODESIGN_CERT`$q /fd SHA256 /tr $TimestampUrl /td SHA256 `$f"
}

& $iscc @isccArgs $issPath
if ($LASTEXITCODE -ne 0) {
    throw "Inno Setup compilation failed."
}

Write-Host "Installer created in $OutputDir" -ForegroundColor Green
