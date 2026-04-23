param(
    [string]$NativeExe = ".\build\native\gforth.exe",
    [string]$OutputImage = ".\build\native\gforth-advanced.fi",
    [string]$BootstrapExe = "C:\Program Files (x86)\gforth\gforth.exe",
    [switch]$ProbeOnly
)

$ErrorActionPreference = "Stop"

function Resolve-ExistingPath {
    param(
        [string]$Path,
        [string]$Description
    )

    if (-not (Test-Path $Path)) {
        throw "Missing $Description`: $Path"
    }
    return (Resolve-Path $Path).Path
}

function Invoke-Gforth {
    param(
        [string]$Exe,
        [string[]]$Arguments
    )

    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = $Exe
    foreach ($arg in $Arguments) {
        $psi.ArgumentList.Add($arg)
    }
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false

    $p = [System.Diagnostics.Process]::Start($psi)
    $stdout = $p.StandardOutput.ReadToEnd()
    $stderr = $p.StandardError.ReadToEnd()
    $p.WaitForExit()

    [pscustomobject]@{
        ExitCode = $p.ExitCode
        Stdout = $stdout.Trim()
        Stderr = $stderr.Trim()
    }
}

function Test-Word {
    param(
        [string]$Exe,
        [string]$Word
    )

    $result = Invoke-Gforth -Exe $Exe -Arguments @("-e", "s`" $Word`" find-name dup . cr bye")
    return ($result.ExitCode -eq 0 -and $result.Stdout -ne "0")
}

function Write-Check {
    param(
        [string]$Name,
        [bool]$Passed,
        [string]$Detail = ""
    )

    if ($Passed) {
        Write-Host "[PASS] $Name $Detail"
    } else {
        Write-Host "[FAIL] $Name $Detail"
    }
}

$native = Resolve-ExistingPath -Path $NativeExe -Description "native gforth executable"
$repoRoot = (Resolve-Path ".").Path

Write-Host "Advanced interactive image probe"
Write-Host "native: $native"
Write-Host "output: $OutputImage"

$smoke = Invoke-Gforth -Exe $native -Arguments @("-e", "1 2 + . cr bye")
$nativeSmokeOk = ($smoke.ExitCode -eq 0 -and $smoke.Stdout -match "3")
Write-Check -Name "native smoke" -Passed $nativeSmokeOk -Detail $smoke.Stdout

$nativeHasSaveSystem = Test-Word -Exe $native -Word "savesystem"
Write-Check -Name "native word:savesystem" -Passed $nativeHasSaveSystem

$nativeHasCompImage = Test-Word -Exe $native -Word "comp-image"
Write-Check -Name "native word:comp-image" -Passed $nativeHasCompImage

$bootstrapAvailable = Test-Path $BootstrapExe
Write-Check -Name "bootstrap executable" -Passed $bootstrapAvailable -Detail $BootstrapExe

$bootstrapCanRun = $false
$bootstrapHasSaveSystem = $false
$bootstrapCanLoadCompI = $false

if ($bootstrapAvailable) {
    $bootstrap = (Resolve-Path $BootstrapExe).Path
    $bootstrapVersion = Invoke-Gforth -Exe $bootstrap -Arguments @("--version")
    $bootstrapCanRun = ($bootstrapVersion.ExitCode -eq 0)
    Write-Check -Name "bootstrap smoke" -Passed $bootstrapCanRun -Detail $bootstrapVersion.Stdout

    if ($bootstrapCanRun) {
        $bootstrapHasSaveSystem = Test-Word -Exe $bootstrap -Word "savesystem"
        Write-Check -Name "bootstrap word:savesystem" -Passed $bootstrapHasSaveSystem

        $compI = Invoke-Gforth -Exe $bootstrap -Arguments @("comp-i.fs", "-e", "s`" comp-image`" find-name dup . cr bye")
        $bootstrapCanLoadCompI = ($compI.ExitCode -eq 0 -and $compI.Stdout -ne "0")
        Write-Check -Name "bootstrap load:comp-i.fs" -Passed $bootstrapCanLoadCompI
        if (-not $bootstrapCanLoadCompI -and $compI.Stderr) {
            Write-Host "  $($compI.Stderr)"
        }
    }
}

$canBuildNow = $nativeSmokeOk -and $nativeHasSaveSystem -and $nativeHasCompImage

if ($canBuildNow) {
    Write-Host "The native image has the required image-building words, but this script does not yet implement the final two-image compaction step."
    Write-Host "Refusing to create $OutputImage until the image layout has been validated."
    exit 3
}

Write-Host ""
Write-Host "Advanced interactive image build is not available yet."
Write-Host "Next required work:"
Write-Host "- produce or obtain a current Gforth image-builder with savesystem and comp-image"
Write-Host "- decide whether Windows ships a separate gforth-advanced.fi or a runtime loader"
Write-Host "- keep build/native/gforth.fi on the current simple saccept path until then"

if ($ProbeOnly) {
    exit 0
}

exit 2
