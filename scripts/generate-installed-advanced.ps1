param(
    [string]$InstallDir = $PSScriptRoot
)

$ErrorActionPreference = "Stop"

$installRoot = (Resolve-Path -LiteralPath $InstallDir).Path
$gforth = Join-Path $installRoot "gforth.exe"
$imageBuilder = Join-Path $installRoot "gforth-ditc.exe"
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
        [string]$Executable = $gforth,
        [string[]]$Arguments,
        [int]$RetryCount = 1,
        [string]$RejectOutputPattern
    )

    for ($attempt = 1; $attempt -le $RetryCount; $attempt++) {
        Write-Log ""
        Write-Log "== $Name attempt $attempt/$RetryCount =="
        Write-Log ("& `"$Executable`" " + ($Arguments -join " "))

        Push-Location $installRoot
        $oldErrorActionPreference = $ErrorActionPreference
        try {
            $ErrorActionPreference = "Continue"
            $output = & $Executable @Arguments 2>&1
            $exitCode = $LASTEXITCODE
        } finally {
            $ErrorActionPreference = $oldErrorActionPreference
            Pop-Location
        }

        if ($output) {
            $output | ForEach-Object { Write-Log ([string]$_) }
        }

        if ($exitCode -eq 0) {
            $outputText = $output | Out-String
            if ($RejectOutputPattern -and $outputText -match $RejectOutputPattern) {
                Write-Log "$Name rejected output matching: $RejectOutputPattern"
                return $false
            }
            return $true
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
Require-File -Path $imageBuilder -Description "gforth DITC image builder"
Require-File -Path $kernelImage -Description "kernel image"
Require-File -Path (Join-Path $installRoot "exboot.fs") -Description "exboot.fs"
Require-File -Path (Join-Path $installRoot "startup.fs") -Description "startup.fs"
Require-File -Path (Join-Path $installRoot "comp-i.fs") -Description "comp-i.fs"
Require-File -Path (Join-Path $installRoot "kernel\accept.fs") -Description "kernel accept.fs"
Require-File -Path (Join-Path $installRoot "ekey.fs") -Description "ekey.fs"
Require-File -Path (Join-Path $installRoot "history.fs") -Description "history.fs"

Remove-Item -LiteralPath $noOffsetImage, $offsetImage, $advancedImage -Force -ErrorAction SilentlyContinue

$savePrefix = "include kernel/accept.fs require ekey.fs require history.fs "

# The two intermediate images must be created by the doubly indirect threaded
# builder.  A normal engine cannot provide independent code/xt/label bases and
# produces only a data-relocatable image whose checksum and code references
# become invalid when Windows ASLR changes the executable address.
$accepted = $false
for ($round = 1; $round -le 4; $round++) {
    Write-Log ""
    Write-Log "== image generation round $round =="

    $null = Invoke-GforthStep -Name "save no-offset image" -Executable $imageBuilder -Arguments @(
        "--clear-dictionary",
        "--no-offset-im",
        "--die-on-signal=2",
        "-p", ".;~+;.",
        "-i", $kernelImage,
        "exboot.fs",
        "startup.fs",
        "-e", "$($savePrefix)savesystem gforth-mi-build-no-offset.fi"
    ) -RetryCount 12

    $null = Invoke-GforthStep -Name "save offset image" -Executable $imageBuilder -Arguments @(
        "--clear-dictionary",
        "--offset-image",
        "--die-on-signal=2",
        "-p", ".;~+;.",
        "-i", $kernelImage,
        "exboot.fs",
        "startup.fs",
        "-e", "$($savePrefix)savesystem gforth-mi-build-offset.fi"
    ) -RetryCount 12

    $composeAccepted = Invoke-GforthStep -Name "compose advanced image" -Executable $imageBuilder -Arguments @(
        "--die-on-signal=2",
        "-p", ".;~+;.",
        "-i", $kernelImage,
        "-e", "3",
        "exboot.fs",
        "startup.fs",
        "comp-i.fs",
        "-e", "comp-image gforth-mi-build-no-offset.fi gforth-mi-build-offset.fi gforth-advanced.fi bye"
    ) -RetryCount 12 -RejectOutputPattern "images have the same base address"

    if (-not $composeAccepted) {
        Write-Log "composition did not produce a fully relocatable image; rebuilding images"
        Remove-Item -LiteralPath $noOffsetImage, $offsetImage, $advancedImage -Force -ErrorAction SilentlyContinue
        continue
    }

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
Remove-Item -LiteralPath $noOffsetImage, $offsetImage -Force -ErrorAction SilentlyContinue
