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

Invoke-GforthStep -Name "smoke test advanced image" -Arguments @(
    "-i", $advancedImage,
    "-e", "bye"
)

Write-Log ""
Write-Log "Generated $advancedImage"
