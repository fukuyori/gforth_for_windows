param(
    [string]$NativeExe = ".\build\native\gforth.exe",
    [int]$TimeoutSeconds = 8,
    [switch]$KeepTemp,
    [switch]$Json
)

$ErrorActionPreference = "Stop"

$script = Join-Path $PSScriptRoot "probe-saccept-history-persistence.ps1"
$probeArgs = @{
    NativeExe = $NativeExe
    TimeoutSeconds = $TimeoutSeconds
}

if ($KeepTemp) {
    $probeArgs.KeepTemp = $true
}

if ($Json) {
    $probeArgs.Json = $true
}

& $script @probeArgs
