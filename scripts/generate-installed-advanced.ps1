param(
    [string]$InstallDir = $PSScriptRoot
)

$ErrorActionPreference = "Stop"

$installRoot = (Resolve-Path -LiteralPath $InstallDir).Path
$gforth = Join-Path $installRoot "gforth.exe"
$kernelImage = Join-Path $installRoot "gforth.fi"
$noOffsetImage = Join-Path $installRoot "gforth-mi-build-no-offset.fi"
$offsetImage = Join-Path $installRoot "gforth-mi-build-offset.fi"
$advancedImage = Join-Path $installRoot "gforth-advanced.fi"
$logPath = Join-Path $installRoot "generate-advanced.log"

function Write-Log {
    param([string]$Message)
    Add-Content -LiteralPath $logPath -Value $Message
}

function Require-File {
    param(
        [string]$Path,
        [string]$Description
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Missing $Description`: $Path"
    }
}

function Invoke-GforthStep {
    param(
        [string]$Name,
        [string[]]$Arguments,
        [int]$RetryCount = 1
    )

    for ($attempt = 1; $attempt -le $RetryCount; $attempt++) {
        Write-Log ""
        Write-Log "== $Name attempt $attempt/$RetryCount =="
        Write-Log ("& `"$gforth`" " + ($Arguments -join " "))

        Push-Location $installRoot
        $oldErrorActionPreference = $ErrorActionPreference
        try {
            $ErrorActionPreference = "Continue"
            $output = & $gforth @Arguments 2>&1
            $exitCode = $LASTEXITCODE
        } finally {
            $ErrorActionPreference = $oldErrorActionPreference
            Pop-Location
        }

        if ($output) {
            $output | ForEach-Object { Write-Log ([string]$_) }
        }

        if ($exitCode -eq 0) {
            return
        }

        Write-Log "$Name failed with exit code $exitCode"
        if ($attempt -lt $RetryCount) {
            Start-Sleep -Milliseconds (250 * $attempt)
        }
    }

    throw "$Name failed after $RetryCount attempt(s). See $logPath"
}

Set-Content -LiteralPath $logPath -Value "Generating gforth-advanced.fi in $installRoot"

Require-File -Path $gforth -Description "gforth executable"
Require-File -Path $kernelImage -Description "kernel image"
Require-File -Path (Join-Path $installRoot "exboot.fs") -Description "exboot.fs"
Require-File -Path (Join-Path $installRoot "startup.fs") -Description "startup.fs"
Require-File -Path (Join-Path $installRoot "comp-i.fs") -Description "comp-i.fs"
Require-File -Path (Join-Path $installRoot "kernel\accept.fs") -Description "kernel accept.fs"
Require-File -Path (Join-Path $installRoot "ekey.fs") -Description "ekey.fs"
Require-File -Path (Join-Path $installRoot "history.fs") -Description "history.fs"

Remove-Item -LiteralPath $noOffsetImage, $offsetImage, $advancedImage -Force -ErrorAction SilentlyContinue

$savePrefix = "include kernel/accept.fs require ekey.fs require history.fs "

# The two intermediate images must end up at different base addresses for
# comp-image to compute a complete relocation bitmap.  When address-space
# layout happens to place both at the same base, the composed image loads
# and passes a plain smoke test but crashes in compile-prims as soon as a
# new definition is compiled.  The compile smoke test below catches that;
# on failure the whole image set is rebuilt.
$accepted = $false
for ($round = 1; $round -le 4; $round++) {
    Write-Log ""
    Write-Log "== image generation round $round =="

    Invoke-GforthStep -Name "save no-offset image" -Arguments @(
        "--clear-dictionary",
        "--no-offset-im",
        "--die-on-signal=2",
        "-p", ".;~+;.",
        "-i", $kernelImage,
        "exboot.fs",
        "startup.fs",
        "-e", "$($savePrefix)savesystem gforth-mi-build-no-offset.fi"
    ) -RetryCount 12

    Invoke-GforthStep -Name "save offset image" -Arguments @(
        "--clear-dictionary",
        "--offset-image",
        "--die-on-signal=2",
        "-p", ".;~+;.",
        "-i", $kernelImage,
        "exboot.fs",
        "startup.fs",
        "-e", "$($savePrefix)savesystem gforth-mi-build-offset.fi"
    ) -RetryCount 12

    Invoke-GforthStep -Name "compose advanced image" -Arguments @(
        "--die-on-signal=2",
        "-p", ".;~+;.",
        "-i", $kernelImage,
        "-e", "3",
        "exboot.fs",
        "startup.fs",
        "comp-i.fs",
        "-e", "comp-image gforth-mi-build-no-offset.fi gforth-mi-build-offset.fi gforth-advanced.fi bye"
    ) -RetryCount 12

    Push-Location $installRoot
    try {
        $smoke = & $gforth "-i" $advancedImage "-e" ": generate-advanced-smoke 7 dup * ; generate-advanced-smoke . cr bye" 2>&1
        $smokeExit = $LASTEXITCODE
    } finally {
        Pop-Location
    }
    if ($smoke) {
        $smoke | ForEach-Object { Write-Log ([string]$_) }
    }
    if ($smokeExit -eq 0 -and (($smoke | Out-String) -match "49")) {
        Write-Log "compile smoke test passed on round $round"
        $accepted = $true
        break
    }
    Write-Log "compile smoke test failed on round $round (exit $smokeExit); rebuilding images"
    Remove-Item -LiteralPath $noOffsetImage, $offsetImage, $advancedImage -Force -ErrorAction SilentlyContinue
}

if (-not $accepted) {
    throw "Advanced image failed the compile smoke test after 4 generation rounds. See $logPath"
}

Write-Log ""
Write-Log "Generated $advancedImage"
