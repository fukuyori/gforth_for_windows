param(
    [string]$NativeExe = ".\build\native\gforth.exe",
    [string]$AdvancedImage = ".\build\native\gforth-advanced.fi",
    [string]$BootstrapExe = "C:\Program Files (x86)\gforth\gforth.exe",
    [int]$RepeatCount = 3,
    [int]$TimeoutSeconds = 5,
    [switch]$Build,
    [switch]$ManualChecklistOnly
)

$ErrorActionPreference = "Stop"

function Write-Section {
    param([string]$Title)

    Write-Host ""
    Write-Host "== $Title =="
}

function Invoke-Step {
    param(
        [string]$Name,
        [scriptblock]$Body
    )

    Write-Section $Name
    & $Body
}

function Write-ManualChecklist {
    Write-Section "Manual integrated interactive checklist"
    Write-Host "Run the reduced default path in Windows Terminal and WezTerm:"
    Write-Host ""
    Write-Host '  $env:GFORTH_WIN_INTERACTIVE = "1"'
    Write-Host '  $env:GFORTH_WIN_HISTORY_FILE = ".gforth-history"'
    Write-Host '  .\build\native\gforth.exe'
    Write-Host ""
    Write-Host "Then check:"
    Write-Host '- `1 2 + .` then Enter prints `3 ok`.'
    Write-Host "- Backspace edits a simple typo without double echo."
    Write-Host '- `bye` exits and restores the terminal.'
    Write-Host "- Restart, press Up on an empty line, then Enter; the last history line is recalled."
    Write-Host "- Press Up repeatedly to walk to older history, then Down to return to newer history or an empty line."
    Write-Host "- Type a partial line, press Up, and confirm it is not overwritten before history browsing starts."
    Write-Host '- Press Down, PageUp, and PageDown on an empty line; they do not insert `[B`, `[5~`, or `[6~`.'
    Write-Host "- Resize the terminal while waiting at the prompt; the session should keep accepting input."
    Write-Host ""
    Write-Host "Unset after testing:"
    Write-Host ""
    Write-Host "  Remove-Item Env:\GFORTH_WIN_INTERACTIVE -ErrorAction SilentlyContinue"
    Write-Host "  Remove-Item Env:\GFORTH_WIN_HISTORY_FILE -ErrorAction SilentlyContinue"
    Write-Host ""
    Write-Host "Run the advanced image path in Windows Terminal and WezTerm:"
    Write-Host ""
    Write-Host '  $env:GFORTHHIST = ".gforth-advanced-history"'
    Write-Host '  .\build\native\gforth.exe -i .\build\native\gforth-advanced.fi'
    Write-Host ""
    Write-Host "Then check:"
    Write-Host '- `1 2 + .` then Enter prints `3 ok`.'
    Write-Host "- Backspace, Left, Right, Home, End, Up, Down, PageUp, and PageDown redraw without duplicate echo."
    Write-Host "- Restart, press Up on an empty line, then Enter; the last advanced-history line is recalled."
    Write-Host "- Press Up or PageUp repeatedly to walk to older advanced-history entries, then Down or PageDown to return."
    Write-Host '- `see +` and `locate +` produce useful output without crashing.'
    Write-Host ""
    Write-Host "Unset after testing:"
    Write-Host ""
    Write-Host "  Remove-Item Env:\GFORTHHIST -ErrorAction SilentlyContinue"
    Write-Host ""
    Write-Host "To automate the advanced PageUp/PageDown console-input check from an interactive terminal:"
    Write-Host ""
    Write-Host "  .\scripts\probe-advanced-page-keys-console.ps1"
}

if ($ManualChecklistOnly) {
    Write-ManualChecklist
    exit 0
}

if ($Build) {
    Invoke-Step "Native build with advanced readiness" {
        if ($BootstrapExe -and (Test-Path $BootstrapExe)) {
            & .\scripts\build-native.ps1 -BootstrapExe $BootstrapExe -CheckAdvancedInteractive
        } else {
            & .\scripts\build-native.ps1 -CheckAdvancedInteractive
        }
    }
}

Invoke-Step "Reduced interactive probe" {
    & .\scripts\probe-reduced-interactive.ps1 -NativeExe $NativeExe -TimeoutSeconds $TimeoutSeconds
}

Invoke-Step "Advanced interactive readiness" {
    & .\scripts\check-advanced-interactive-readiness.ps1 -NativeExe $NativeExe
}

Invoke-Step "Advanced blocker classification" {
    & .\scripts\classify-advanced-interactive-blockers.ps1 -NativeExe $NativeExe -RepeatCount $RepeatCount -TimeoutSeconds $TimeoutSeconds
}

if (Test-Path $AdvancedImage) {
    Invoke-Step "Advanced image runtime probe" {
        & .\scripts\check-advanced-image-runtime.ps1 -NativeExe $NativeExe -AdvancedImage $AdvancedImage -TimeoutSeconds $TimeoutSeconds
    }
} else {
    Write-Section "Advanced image runtime probe"
    Write-Host "Skipping advanced image runtime probe because $AdvancedImage does not exist."
}

Write-ManualChecklist

Write-Section "Result"
Write-Host "Automated Windows interactive release checks completed."
