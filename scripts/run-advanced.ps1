param(
    [string]$NativeExe = ".\build\native\gforth.exe",
    [string]$AdvancedImage = ".\build\native\gforth-advanced.fi",
    [string]$HistoryPath = ".gforth-advanced-history",
    [switch]$NoHistory,
    [switch]$NoStatus
)

$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path

function Resolve-FromRepo {
    param(
        [string]$Path,
        [string]$Description
    )

    $candidate = if ([System.IO.Path]::IsPathRooted($Path)) {
        $Path
    } else {
        Join-Path $RepoRoot $Path
    }

    if (-not (Test-Path -LiteralPath $candidate)) {
        throw "Missing $Description`: $candidate"
    }

    return (Resolve-Path -LiteralPath $candidate).Path
}

$native = Resolve-FromRepo -Path $NativeExe -Description "native gforth executable"
$advanced = Resolve-FromRepo -Path $AdvancedImage -Description "advanced image"
$history = if ([System.IO.Path]::IsPathRooted($HistoryPath)) {
    $HistoryPath
} else {
    Join-Path $RepoRoot $HistoryPath
}

$oldStatus = $env:GFORTH_WIN_STATUS
$oldHistory = $env:GFORTHHIST
$hadStatus = Test-Path Env:\GFORTH_WIN_STATUS
$hadHistory = Test-Path Env:\GFORTHHIST
$exitCode = 0

try {
    if ($NoStatus) {
        Remove-Item Env:\GFORTH_WIN_STATUS -ErrorAction SilentlyContinue
    } else {
        $env:GFORTH_WIN_STATUS = "1"
    }

    if ($NoHistory) {
        Remove-Item Env:\GFORTHHIST -ErrorAction SilentlyContinue
    } else {
        $env:GFORTHHIST = $history
    }

    & $native -i $advanced
    $exitCode = $LASTEXITCODE
} finally {
    if ($hadStatus) {
        $env:GFORTH_WIN_STATUS = $oldStatus
    } else {
        Remove-Item Env:\GFORTH_WIN_STATUS -ErrorAction SilentlyContinue
    }

    if ($hadHistory) {
        $env:GFORTHHIST = $oldHistory
    } else {
        Remove-Item Env:\GFORTHHIST -ErrorAction SilentlyContinue
    }
}

if ($exitCode -ne 0) {
    throw "gforth exited with code $exitCode"
}
