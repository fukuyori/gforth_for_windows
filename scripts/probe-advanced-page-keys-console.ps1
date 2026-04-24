param(
    [string]$NativeExe = ".\build\native\gforth.exe",
    [string]$AdvancedImage = ".\build\native\gforth-advanced.fi",
    [int]$TimeoutSeconds = 8
)

$ErrorActionPreference = "Stop"

Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

public static class ConsoleInputProbe {
    public const int STD_INPUT_HANDLE = -10;
    public const short KEY_EVENT = 0x0001;

    [StructLayout(LayoutKind.Sequential)]
    public struct KEY_EVENT_RECORD {
        [MarshalAs(UnmanagedType.Bool)]
        public bool bKeyDown;
        public ushort wRepeatCount;
        public ushort wVirtualKeyCode;
        public ushort wVirtualScanCode;
        public char UnicodeChar;
        public uint dwControlKeyState;
    }

    [StructLayout(LayoutKind.Explicit)]
    public struct INPUT_RECORD {
        [FieldOffset(0)]
        public short EventType;
        [FieldOffset(4)]
        public KEY_EVENT_RECORD KeyEvent;
    }

    [DllImport("kernel32.dll", SetLastError=true)]
    public static extern IntPtr GetStdHandle(int nStdHandle);

    [DllImport("kernel32.dll", SetLastError=true)]
    public static extern bool WriteConsoleInput(
        IntPtr hConsoleInput,
        INPUT_RECORD[] lpBuffer,
        uint nLength,
        out uint lpNumberOfEventsWritten);

    [DllImport("kernel32.dll", SetLastError=true)]
    public static extern bool FlushConsoleInputBuffer(IntPtr hConsoleInput);

    public static INPUT_RECORD CharRecord(char ch) {
        INPUT_RECORD record = new INPUT_RECORD();
        record.EventType = KEY_EVENT;
        record.KeyEvent.bKeyDown = true;
        record.KeyEvent.wRepeatCount = 1;
        record.KeyEvent.wVirtualKeyCode = 0;
        record.KeyEvent.wVirtualScanCode = 0;
        record.KeyEvent.UnicodeChar = ch;
        record.KeyEvent.dwControlKeyState = 0;
        return record;
    }

    public static INPUT_RECORD VirtualKeyRecord(ushort virtualKeyCode, ushort scanCode) {
        INPUT_RECORD record = new INPUT_RECORD();
        record.EventType = KEY_EVENT;
        record.KeyEvent.bKeyDown = true;
        record.KeyEvent.wRepeatCount = 1;
        record.KeyEvent.wVirtualKeyCode = virtualKeyCode;
        record.KeyEvent.wVirtualScanCode = scanCode;
        record.KeyEvent.UnicodeChar = '\0';
        record.KeyEvent.dwControlKeyState = 0;
        return record;
    }
}
"@

function Send-ConsoleText {
    param([string]$Text)

    $inputHandle = [ConsoleInputProbe]::GetStdHandle([ConsoleInputProbe]::STD_INPUT_HANDLE)
    if ($inputHandle -eq [IntPtr]::Zero -or $inputHandle.ToInt64() -eq -1) {
        throw "Could not get console input handle."
    }

    $records = New-Object ConsoleInputProbe+INPUT_RECORD[] $Text.Length
    for ($i = 0; $i -lt $Text.Length; $i++) {
        $records[$i] = [ConsoleInputProbe]::CharRecord($Text[$i])
    }

    [uint32]$written = 0
    if (-not [ConsoleInputProbe]::WriteConsoleInput($inputHandle, $records, [uint32]$records.Length, [ref]$written)) {
        $lastError = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
        if ($lastError -eq 6) {
            throw "WriteConsoleInput failed with ERROR_INVALID_HANDLE. Run this probe from an interactive Windows Terminal or WezTerm session, not from a redirected/non-console host."
        }
        throw "WriteConsoleInput failed: $lastError"
    }
    if ($written -ne $records.Length) {
        throw "WriteConsoleInput wrote $written of $($records.Length) events."
    }
}

function Send-ConsoleVirtualKeys {
    param([ushort[]]$VirtualKeyCodes)

    if ($VirtualKeyCodes.Count -eq 0) {
        return
    }

    $inputHandle = [ConsoleInputProbe]::GetStdHandle([ConsoleInputProbe]::STD_INPUT_HANDLE)
    if ($inputHandle -eq [IntPtr]::Zero -or $inputHandle.ToInt64() -eq -1) {
        throw "Could not get console input handle."
    }

    $records = New-Object ConsoleInputProbe+INPUT_RECORD[] $VirtualKeyCodes.Count
    for ($i = 0; $i -lt $VirtualKeyCodes.Count; $i++) {
        $scanCode = switch ($VirtualKeyCodes[$i]) {
            0x21 { 0x49 }
            0x22 { 0x51 }
            default { 0 }
        }
        $records[$i] = [ConsoleInputProbe]::VirtualKeyRecord($VirtualKeyCodes[$i], [ushort]$scanCode)
    }

    [uint32]$written = 0
    if (-not [ConsoleInputProbe]::WriteConsoleInput($inputHandle, $records, [uint32]$records.Length, [ref]$written)) {
        $lastError = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
        throw "WriteConsoleInput virtual keys failed: $lastError"
    }
    if ($written -ne $records.Length) {
        throw "WriteConsoleInput wrote $written of $($records.Length) virtual key events."
    }
}

function Clear-ConsoleInput {
    $inputHandle = [ConsoleInputProbe]::GetStdHandle([ConsoleInputProbe]::STD_INPUT_HANDLE)
    if ($inputHandle -eq [IntPtr]::Zero -or $inputHandle.ToInt64() -eq -1) {
        throw "Could not get console input handle."
    }
    [void][ConsoleInputProbe]::FlushConsoleInputBuffer($inputHandle)
}

function Invoke-GforthConsoleInput {
    param(
        [string[]]$Arguments,
        [string]$InjectedText,
        [ushort[]]$InjectedVirtualKeys = @(),
        [string]$SecondInjectedText = "",
        [ushort[]]$SecondInjectedVirtualKeys = @(),
        [int]$SecondDelayMilliseconds = 500,
        [hashtable]$Environment = @{}
    )

    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = (Resolve-Path $NativeExe).Path
    foreach ($arg in $Arguments) {
        $psi.ArgumentList.Add($arg)
    }
    foreach ($key in $Environment.Keys) {
        $psi.Environment[$key] = [string]$Environment[$key]
    }
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.RedirectStandardInput = $false
    $psi.UseShellExecute = $false

    Clear-ConsoleInput
    $p = [System.Diagnostics.Process]::Start($psi)
    Start-Sleep -Milliseconds 500
    if ($InjectedText -ne "") {
        Send-ConsoleText -Text $InjectedText
    }
    Send-ConsoleVirtualKeys -VirtualKeyCodes $InjectedVirtualKeys
    if ($SecondInjectedText -ne "" -or $SecondInjectedVirtualKeys.Count -ne 0) {
        Start-Sleep -Milliseconds $SecondDelayMilliseconds
        Send-ConsoleVirtualKeys -VirtualKeyCodes $SecondInjectedVirtualKeys
        if ($SecondInjectedText -ne "") {
            Send-ConsoleText -Text $SecondInjectedText
        }
    }

    if (-not $p.WaitForExit($TimeoutSeconds * 1000)) {
        try {
            $p.Kill()
            $p.WaitForExit()
        } catch {
        }
        Clear-ConsoleInput
        return [pscustomobject]@{
            ExitCode = -999
            Stdout = $p.StandardOutput.ReadToEnd().Trim()
            Stderr = "Timed out after $TimeoutSeconds seconds"
        }
    }

    Clear-ConsoleInput
    [pscustomobject]@{
        ExitCode = $p.ExitCode
        Stdout = $p.StandardOutput.ReadToEnd().Trim()
        Stderr = $p.StandardError.ReadToEnd().Trim()
    }
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

if (-not (Test-Path $AdvancedImage)) {
    throw "Missing advanced image: $AdvancedImage"
}

$advancedImagePath = (Resolve-Path $AdvancedImage).Path
$escape = [string][char]27
$allPassed = $true

Write-Host "Advanced console PageUp/PageDown probe"
Write-Host "native: $((Resolve-Path $NativeExe).Path)"
Write-Host "advanced image: $advancedImagePath"
Write-Host ""

$historyPath = Join-Path (Resolve-Path ".").Path ".tmp-advanced-page-console-history.txt"

function Reset-TestHistory {
    if (Test-Path $historyPath) {
        Remove-Item -LiteralPath $historyPath -Force
    }
    Set-Content -LiteralPath $historyPath -Value "1 2 + ." -NoNewline
}

Reset-TestHistory
$replRun = Invoke-GforthConsoleInput `
    -Arguments @("-i", $advancedImagePath) `
    -Environment @{ GFORTHHIST = $historyPath.Replace("\", "/") } `
    -InjectedText ($escape + "[5~`rbye`r")

$replPassed = (
    $replRun.ExitCode -eq 0 -and
    $replRun.Stdout -match "3\s+ok" -and
    $replRun.Stdout -notmatch "5~|6~"
)
Write-Check -Name "console:page-up-recalls-history" -Passed $replPassed -Detail (($replRun.Stdout + " " + $replRun.Stderr).Trim() -replace "`r?`n", " | ")
$allPassed = $allPassed -and $replPassed

Reset-TestHistory
$pageDownRun = Invoke-GforthConsoleInput `
    -Arguments @("-i", $advancedImagePath) `
    -Environment @{ GFORTHHIST = $historyPath.Replace("\", "/") } `
    -InjectedText ($escape + "[5~" + $escape + "[6~`rbye`r")

$pageDownPassed = (
    $pageDownRun.ExitCode -eq 0 -and
    $pageDownRun.Stdout -notmatch "3\s+ok" -and
    $pageDownRun.Stdout -notmatch "5~|6~"
)
Write-Check -Name "console:page-down-clears-history" -Passed $pageDownPassed -Detail (($pageDownRun.Stdout + " " + $pageDownRun.Stderr).Trim() -replace "`r?`n", " | ")
$allPassed = $allPassed -and $pageDownPassed

Reset-TestHistory
$splitPageUpRun = Invoke-GforthConsoleInput `
    -Arguments @("-i", $advancedImagePath) `
    -Environment @{ GFORTHHIST = $historyPath.Replace("\", "/") } `
    -InjectedText ($escape + "[") `
    -SecondInjectedText ("5~`rbye`r")

$splitPageUpPassed = (
    $splitPageUpRun.ExitCode -eq 0 -and
    $splitPageUpRun.Stdout -match "3\s+ok" -and
    $splitPageUpRun.Stdout -notmatch "5~|6~"
)
Write-Check -Name "console:split-page-up-recalls-history" -Passed $splitPageUpPassed -Detail (($splitPageUpRun.Stdout + " " + $splitPageUpRun.Stderr).Trim() -replace "`r?`n", " | ")
$allPassed = $allPassed -and $splitPageUpPassed

Reset-TestHistory
$splitPageDownRun = Invoke-GforthConsoleInput `
    -Arguments @("-i", $advancedImagePath) `
    -Environment @{ GFORTHHIST = $historyPath.Replace("\", "/") } `
    -InjectedText ($escape + "[5~" + $escape + "[") `
    -SecondInjectedText ("6~`rbye`r")

$splitPageDownPassed = (
    $splitPageDownRun.ExitCode -eq 0 -and
    $splitPageDownRun.Stdout -notmatch "3\s+ok" -and
    $splitPageDownRun.Stdout -notmatch "5~|6~"
)
Write-Check -Name "console:split-page-down-clears-history" -Passed $splitPageDownPassed -Detail (($splitPageDownRun.Stdout + " " + $splitPageDownRun.Stderr).Trim() -replace "`r?`n", " | ")
$allPassed = $allPassed -and $splitPageDownPassed

Reset-TestHistory
$vkPageUpRun = Invoke-GforthConsoleInput `
    -Arguments @("-i", $advancedImagePath) `
    -Environment @{ GFORTHHIST = $historyPath.Replace("\", "/") } `
    -InjectedText "" `
    -InjectedVirtualKeys @([ushort]0x21) `
    -SecondInjectedText "`rbye`r"

$vkPageUpPassed = (
    $vkPageUpRun.ExitCode -eq 0 -and
    $vkPageUpRun.Stdout -match "3\s+ok" -and
    $vkPageUpRun.Stdout -notmatch "5~|6~"
)
Write-Check -Name "console:vk-page-up-recalls-history" -Passed $vkPageUpPassed -Detail (($vkPageUpRun.Stdout + " " + $vkPageUpRun.Stderr).Trim() -replace "`r?`n", " | ")
$allPassed = $allPassed -and $vkPageUpPassed

Reset-TestHistory
$vkPageDownRun = Invoke-GforthConsoleInput `
    -Arguments @("-i", $advancedImagePath) `
    -Environment @{ GFORTHHIST = $historyPath.Replace("\", "/") } `
    -InjectedText "" `
    -InjectedVirtualKeys @([ushort]0x21, [ushort]0x22) `
    -SecondInjectedText "`rbye`r"

$vkPageDownPassed = (
    $vkPageDownRun.ExitCode -eq 0 -and
    $vkPageDownRun.Stdout -notmatch "3\s+ok" -and
    $vkPageDownRun.Stdout -notmatch "5~|6~"
)
Write-Check -Name "console:vk-page-down-clears-history" -Passed $vkPageDownPassed -Detail (($vkPageDownRun.Stdout + " " + $vkPageDownRun.Stderr).Trim() -replace "`r?`n", " | ")
$allPassed = $allPassed -and $vkPageDownPassed

Reset-TestHistory
$statusVkPageUpRun = Invoke-GforthConsoleInput `
    -Arguments @("-i", $advancedImagePath, "-e", "+status") `
    -Environment @{ GFORTHHIST = $historyPath.Replace("\", "/") } `
    -InjectedText "" `
    -InjectedVirtualKeys @([ushort]0x21) `
    -SecondInjectedText "`rbye`r"

$statusVkPageUpPassed = (
    $statusVkPageUpRun.ExitCode -eq 0 -and
    $statusVkPageUpRun.Stdout -match "3\s+ok" -and
    $statusVkPageUpRun.Stdout -notmatch "5~|6~"
)
Write-Check -Name "console:status-vk-page-up-recalls-history" -Passed $statusVkPageUpPassed -Detail (($statusVkPageUpRun.Stdout + " " + $statusVkPageUpRun.Stderr).Trim() -replace "`r?`n", " | ")
$allPassed = $allPassed -and $statusVkPageUpPassed

Reset-TestHistory
$statusVkPageDownRun = Invoke-GforthConsoleInput `
    -Arguments @("-i", $advancedImagePath, "-e", "+status") `
    -Environment @{ GFORTHHIST = $historyPath.Replace("\", "/") } `
    -InjectedText "" `
    -InjectedVirtualKeys @([ushort]0x21, [ushort]0x22) `
    -SecondInjectedText "`rbye`r"

$statusVkPageDownPassed = (
    $statusVkPageDownRun.ExitCode -eq 0 -and
    $statusVkPageDownRun.Stdout -notmatch "3\s+ok" -and
    $statusVkPageDownRun.Stdout -notmatch "5~|6~"
)
Write-Check -Name "console:status-vk-page-down-clears-history" -Passed $statusVkPageDownPassed -Detail (($statusVkPageDownRun.Stdout + " " + $statusVkPageDownRun.Stderr).Trim() -replace "`r?`n", " | ")
$allPassed = $allPassed -and $statusVkPageDownPassed

if (Test-Path $historyPath) {
    Remove-Item -LiteralPath $historyPath -Force
}

if (-not $allPassed) {
    exit 1
}

exit 0
