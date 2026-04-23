param(
    [string]$NativeExe = ".\build\native\gforth.exe",
    [int]$TimeoutSeconds = 8,
    [switch]$KeepTemp,
    [switch]$Json
)

$ErrorActionPreference = "Stop"

$tempFiles = @(
    ".tmp-history-create.txt",
    ".tmp-history-env.txt",
    ".tmp-history-append.txt",
    ".tmp-history-accept-runtime.txt",
    ".tmp-history-repl-runtime.txt",
    ".tmp-history-nav-runtime.txt",
    ".tmp-history-ekey-runtime.txt",
    ".tmp-history-ekey-multi-up-runtime.txt",
    ".tmp-history-ekey-down-newer-runtime.txt",
    ".tmp-history-ekey-down-empty-runtime.txt",
    ".tmp-history-ekey-empty-runtime.txt",
    ".tmp-history-ekey-typed-runtime.txt",
    ".tmp-history-integrated-runtime.txt"
)

function Remove-TempFiles {
    foreach ($file in $tempFiles) {
        if (Test-Path $file) {
            try {
                Remove-Item -Force $file
            } catch {
                Write-Warning "Could not remove ${file}: $($_.Exception.Message)"
            }
        }
    }
}

function Invoke-Gforth {
    param(
        [AllowNull()][string]$Code,
        [hashtable]$Environment = @{},
        [AllowNull()][string]$StandardInput = $null
    )

    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = (Resolve-Path $NativeExe).Path
    if ($null -ne $Code -and $Code -ne "") {
        $psi.ArgumentList.Add("-e")
        $psi.ArgumentList.Add($Code)
    }
    foreach ($key in $Environment.Keys) {
        $psi.Environment[$key] = [string]$Environment[$key]
    }
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.RedirectStandardInput = ($null -ne $StandardInput)
    $psi.UseShellExecute = $false

    $p = [System.Diagnostics.Process]::Start($psi)
    if ($null -ne $StandardInput) {
        $p.StandardInput.Write($StandardInput)
        $p.StandardInput.Close()
    }

    if (-not $p.WaitForExit($TimeoutSeconds * 1000)) {
        try {
            $p.Kill()
            $p.WaitForExit()
        } catch {
        }

        return [pscustomobject]@{
            ExitCode = -999
            Stdout = $p.StandardOutput.ReadToEnd().Trim()
            Stderr = "Timed out after $TimeoutSeconds seconds"
        }
    }

    [pscustomobject]@{
        ExitCode = $p.ExitCode
        Stdout = $p.StandardOutput.ReadToEnd().Trim()
        Stderr = $p.StandardError.ReadToEnd().Trim()
    }
}

function Get-BlockerToken {
    param([string]$Text)

    $match = [regex]::Match($Text, ">>>([^<]+)<<<")
    if ($match.Success) {
        return $match.Groups[1].Value.Trim()
    }
    return ""
}

function Get-ObservedState {
    param([object]$Run)

    if ($Run.ExitCode -eq -999) {
        return "TIMEOUT"
    }
    if ($Run.ExitCode -eq 0) {
        return "PASS"
    }
    return "FAIL"
}

function New-ProbeResult {
    param(
        [string]$Name,
        [string]$Expected,
        [object]$Run,
        [string]$Note,
        [bool]$ExtraCheck = $true
    )

    $observed = Get-ObservedState -Run $Run
    if ($observed -eq "PASS" -and -not $ExtraCheck) {
        $observed = "FAIL"
    }

    [pscustomobject]@{
        Name = $Name
        Expected = $Expected
        Observed = $observed
        Matched = ($observed -eq $Expected)
        ExitCode = $Run.ExitCode
        Blocker = if ($observed -eq "FAIL") { Get-BlockerToken -Text $Run.Stderr } else { "" }
        Stdout = $Run.Stdout
        Stderr = $Run.Stderr
        Note = $Note
    }
}

function Test-Word {
    param([string]$Word)

    $run = Invoke-Gforth -Code ('s" ' + $Word + '" find-name dup . cr bye')
    $isPresent = ($run.ExitCode -eq 0 -and $run.Stdout -ne "0")
    return New-ProbeResult `
        -Name "word:$Word" `
        -Expected "PASS" `
        -Run $run `
        -ExtraCheck $isPresent `
        -Note "Required primitive for reduced interactive support."
}

function Test-FileText {
    param(
        [string]$Path,
        [string]$ExpectedText
    )

    if (-not (Test-Path $Path)) {
        return $false
    }

    $content = Get-Content -Raw -Path $Path
    if ($null -eq $content) {
        $content = ""
    }
    $text = $content.TrimEnd("`r", "`n")
    return ($text -eq $ExpectedText)
}

Remove-TempFiles

$results = @()

foreach ($word in @("create-file", "open-file", "write-line", "close-file", "file-size", "reposition-file", "accept", "getenv", "winch?", "form", "k-winch")) {
    $results += Test-Word -Word $word
}

$createPath = ".tmp-history-create.txt"
$createRun = Invoke-Gforth -Code ('s" ' + $createPath + '" w/o create-file throw Constant wh-fid s" hello" wh-fid write-line throw wh-fid close-file throw bye')
$results += New-ProbeResult `
    -Name "fixed-create-write:constant-fid" `
    -Expected "PASS" `
    -Run $createRun `
    -ExtraCheck (Test-FileText -Path $createPath -ExpectedText "hello") `
    -Note "One-shot create/write/close with a constant file id should be safe."

$envPath = ".tmp-history-env.txt"
$envRun = Invoke-Gforth `
    -Code ('s" GFORTH_WIN_HISTORY" getenv nip . cr s" ' + $envPath + '" w/o create-file throw Constant wh-fid s" env" wh-fid write-line throw wh-fid close-file throw bye') `
    -Environment @{ GFORTH_WIN_HISTORY = "1" }
$envStdoutOk = ($envRun.ExitCode -eq 0 -and $envRun.Stdout -ne "0")
$results += New-ProbeResult `
    -Name "env-opt-in:create-write" `
    -Expected "PASS" `
    -Run $envRun `
    -ExtraCheck ($envStdoutOk -and (Test-FileText -Path $envPath -ExpectedText "env")) `
    -Note "Feature gating can read GFORTH_WIN_HISTORY before writing."

$appendPath = ".tmp-history-append.txt"
Set-Content -Path $appendPath -Value "first" -NoNewline
$appendRun = Invoke-Gforth -Code ('s" ' + $appendPath + '" r/w open-file throw Constant wh-fid wh-fid file-size throw wh-fid reposition-file throw s" second" wh-fid write-line throw wh-fid close-file throw bye')
$appendOk = $false
if (Test-Path $appendPath) {
    $appendText = Get-Content -Raw -Path $appendPath
    $appendOk = ($appendText -match "first" -and $appendText -match "second")
}
$results += New-ProbeResult `
    -Name "open-existing:append" `
    -Expected "PASS" `
    -Run $appendRun `
    -ExtraCheck $appendOk `
    -Note "Appending to an existing history file is required before real persistence."

$acceptRuntimePath = ".tmp-history-accept-runtime.txt"
$acceptRuntimeRun = Invoke-Gforth `
    -Code "pad 1024 accept . cr bye" `
    -Environment @{ GFORTH_WIN_HISTORY = "1"; GFORTH_WIN_HISTORY_FILE = $acceptRuntimePath } `
    -StandardInput "accepted-runtime`n"
$results += New-ProbeResult `
    -Name "runtime-accept:history-file" `
    -Expected "PASS" `
    -Run $acceptRuntimeRun `
    -ExtraCheck (Test-FileText -Path $acceptRuntimePath -ExpectedText "accepted-runtime") `
    -Note "The built native accept persists an accepted line when history is enabled."

$replRuntimePath = ".tmp-history-repl-runtime.txt"
$replRuntimeRun = Invoke-Gforth `
    -Code $null `
    -Environment @{ GFORTH_WIN_HISTORY = "1"; GFORTH_WIN_HISTORY_FILE = $replRuntimePath } `
    -StandardInput "1 2 + .`nbye`n"
$results += New-ProbeResult `
    -Name "runtime-repl:history-file" `
    -Expected "PASS" `
    -Run $replRuntimeRun `
    -ExtraCheck (Test-FileText -Path $replRuntimePath -ExpectedText "1 2 + .`r`nbye") `
    -Note "The default REPL path persists input lines only when history is enabled."

$navRuntimePath = ".tmp-history-nav-runtime.txt"
Set-Content -Path $navRuntimePath -Value "7 8 + ."
$navRuntimeRun = Invoke-Gforth `
    -Code $null `
    -Environment @{ GFORTH_WIN_HISTORY_NAV = "1"; GFORTH_WIN_HISTORY_FILE = $navRuntimePath } `
    -StandardInput (([string][char]16) + "`nbye`n")
$results += New-ProbeResult `
    -Name "runtime-nav:ctrl-p-last-line" `
    -Expected "PASS" `
    -Run $navRuntimeRun `
    -ExtraCheck ($navRuntimeRun.Stdout -match "\b15\b") `
    -Note "Ctrl-P recalls the last history line when reduced navigation is enabled."

$ekeyRuntimePath = ".tmp-history-ekey-runtime.txt"
Set-Content -Path $ekeyRuntimePath -Value "7 8 + ."
$upRuntimeRun = Invoke-Gforth `
    -Code $null `
    -Environment @{ GFORTH_WIN_EKEY = "1"; GFORTH_WIN_HISTORY_FILE = $ekeyRuntimePath } `
    -StandardInput (([string][char]27) + "[A`nbye`n")
$results += New-ProbeResult `
    -Name "runtime-ekey:up-history" `
    -Expected "PASS" `
    -Run $upRuntimeRun `
    -ExtraCheck ($upRuntimeRun.Stdout -match "\b15\b") `
    -Note "ANSI Up recalls the last history line when selected ekey support is enabled."

$multiUpRuntimePath = ".tmp-history-ekey-multi-up-runtime.txt"
Set-Content -Path $multiUpRuntimePath -Value @("1 2 + .", "7 8 + .")
$multiUpRuntimeRun = Invoke-Gforth `
    -Code $null `
    -Environment @{ GFORTH_WIN_EKEY = "1"; GFORTH_WIN_HISTORY_FILE = $multiUpRuntimePath } `
    -StandardInput (([string][char]27) + "[A" + ([string][char]27) + "[A`nbye`n")
$results += New-ProbeResult `
    -Name "runtime-ekey:up-up-older" `
    -Expected "PASS" `
    -Run $multiUpRuntimeRun `
    -ExtraCheck ($multiUpRuntimeRun.Stdout -match "\b3\b" -and $multiUpRuntimeRun.Stderr -notmatch "error") `
    -Note "Repeated ANSI Up walks to older reduced-history entries."

$downNewerRuntimePath = ".tmp-history-ekey-down-newer-runtime.txt"
Set-Content -Path $downNewerRuntimePath -Value @("1 2 + .", "7 8 + .")
$downNewerRuntimeRun = Invoke-Gforth `
    -Code $null `
    -Environment @{ GFORTH_WIN_EKEY = "1"; GFORTH_WIN_HISTORY_FILE = $downNewerRuntimePath } `
    -StandardInput (([string][char]27) + "[A" + ([string][char]27) + "[A" + ([string][char]27) + "[B`nbye`n")
$results += New-ProbeResult `
    -Name "runtime-ekey:down-newer" `
    -Expected "PASS" `
    -Run $downNewerRuntimeRun `
    -ExtraCheck ($downNewerRuntimeRun.Stdout -match "\b15\b" -and $downNewerRuntimeRun.Stdout -notmatch "\[B" -and $downNewerRuntimeRun.Stderr -notmatch "error") `
    -Note "ANSI Down returns from an older entry to a newer reduced-history entry."

$downEmptyRuntimePath = ".tmp-history-ekey-down-empty-runtime.txt"
Set-Content -Path $downEmptyRuntimePath -Value "7 8 + ."
$downEmptyRuntimeRun = Invoke-Gforth `
    -Code $null `
    -Environment @{ GFORTH_WIN_EKEY = "1"; GFORTH_WIN_HISTORY_FILE = $downEmptyRuntimePath } `
    -StandardInput (([string][char]27) + "[A" + ([string][char]27) + "[B`nbye`n")
$results += New-ProbeResult `
    -Name "runtime-ekey:down-empty" `
    -Expected "PASS" `
    -Run $downEmptyRuntimeRun `
    -ExtraCheck ($downEmptyRuntimeRun.Stdout -notmatch "\b15\b" -and $downEmptyRuntimeRun.Stdout -notmatch "\[B" -and $downEmptyRuntimeRun.Stderr -notmatch "error") `
    -Note "ANSI Down after a single Up clears back to an empty edit line."

$emptyHistoryRuntimePath = ".tmp-history-ekey-empty-runtime.txt"
Set-Content -Path $emptyHistoryRuntimePath -Value ""
$emptyHistoryRuntimeRun = Invoke-Gforth `
    -Code $null `
    -Environment @{ GFORTH_WIN_EKEY = "1"; GFORTH_WIN_HISTORY_FILE = $emptyHistoryRuntimePath } `
    -StandardInput (([string][char]27) + "[A`nbye`n")
$results += New-ProbeResult `
    -Name "runtime-ekey:up-empty-history" `
    -Expected "PASS" `
    -Run $emptyHistoryRuntimeRun `
    -ExtraCheck ($emptyHistoryRuntimeRun.Stdout -notmatch "\b15\b" -and $emptyHistoryRuntimeRun.Stdout -notmatch "\[A" -and $emptyHistoryRuntimeRun.Stderr -notmatch "error") `
    -Note "ANSI Up against an empty reduced-history file is consumed safely."

$typedHistoryRuntimePath = ".tmp-history-ekey-typed-runtime.txt"
Set-Content -Path $typedHistoryRuntimePath -Value "7 8 + ."
$typedHistoryRuntimeRun = Invoke-Gforth `
    -Code $null `
    -Environment @{ GFORTH_WIN_EKEY = "1"; GFORTH_WIN_HISTORY_FILE = $typedHistoryRuntimePath } `
    -StandardInput ("9" + ([string][char]27) + "[A`nbye`n")
$results += New-ProbeResult `
    -Name "runtime-ekey:up-preserves-typed-line" `
    -Expected "PASS" `
    -Run $typedHistoryRuntimeRun `
    -ExtraCheck ($typedHistoryRuntimeRun.Stdout -notmatch "\b15\b" -and $typedHistoryRuntimeRun.Stdout -notmatch "\[A" -and $typedHistoryRuntimeRun.Stderr -notmatch "error") `
    -Note "ANSI Up does not overwrite a user-typed line before history browsing starts."

$downRuntimeRun = Invoke-Gforth `
    -Code $null `
    -Environment @{ GFORTH_WIN_EKEY = "1" } `
    -StandardInput (([string][char]27) + "[B`nbye`n")
$results += New-ProbeResult `
    -Name "runtime-ekey:down-swallowed" `
    -Expected "PASS" `
    -Run $downRuntimeRun `
    -ExtraCheck ($downRuntimeRun.Stdout -notmatch "\[B" -and $downRuntimeRun.Stderr -notmatch "error") `
    -Note "ANSI Down is consumed instead of entering literal escape text."

$pageUpRuntimeRun = Invoke-Gforth `
    -Code $null `
    -Environment @{ GFORTH_WIN_EKEY = "1" } `
    -StandardInput (([string][char]27) + "[5~`nbye`n")
$results += New-ProbeResult `
    -Name "runtime-ekey:page-up-swallowed" `
    -Expected "PASS" `
    -Run $pageUpRuntimeRun `
    -ExtraCheck ($pageUpRuntimeRun.Stdout -notmatch "\[5~|~" -and $pageUpRuntimeRun.Stderr -notmatch "error") `
    -Note "ANSI PageUp is consumed until richer paging behavior is available."

$pageDownRuntimeRun = Invoke-Gforth `
    -Code $null `
    -Environment @{ GFORTH_WIN_EKEY = "1" } `
    -StandardInput (([string][char]27) + "[6~`nbye`n")
$results += New-ProbeResult `
    -Name "runtime-ekey:page-down-swallowed" `
    -Expected "PASS" `
    -Run $pageDownRuntimeRun `
    -ExtraCheck ($pageDownRuntimeRun.Stdout -notmatch "\[6~|~" -and $pageDownRuntimeRun.Stderr -notmatch "error") `
    -Note "ANSI PageDown is consumed until richer paging behavior is available."

$winchRuntimeRun = Invoke-Gforth `
    -Code "-1 winch? !" `
    -Environment @{ GFORTH_WIN_WINCH = "1" } `
    -StandardInput "bye`n"
$results += New-ProbeResult `
    -Name "runtime-winch:pending-flag-consumed" `
    -Expected "PASS" `
    -Run $winchRuntimeRun `
    -ExtraCheck ($winchRuntimeRun.Stdout -match "bye" -and $winchRuntimeRun.Stderr -notmatch "error") `
    -Note "A pending resize flag is surfaced as k-winch and consumed without entering input text."

$integratedRuntimePath = ".tmp-history-integrated-runtime.txt"
Set-Content -Path $integratedRuntimePath -Value "7 8 + ."
$integratedRuntimeRun = Invoke-Gforth `
    -Code "-1 winch? !" `
    -Environment @{ GFORTH_WIN_INTERACTIVE = "1"; GFORTH_WIN_HISTORY_FILE = $integratedRuntimePath } `
    -StandardInput (([string][char]27) + "[A`nbye`n")
$integratedFileOk = $false
if (Test-Path $integratedRuntimePath) {
    $integratedText = Get-Content -Raw -Path $integratedRuntimePath
    $integratedFileOk = ($integratedText -match "7 8 \+ \." -and $integratedText -match "bye")
}
$results += New-ProbeResult `
    -Name "runtime-integrated:all-flags" `
    -Expected "PASS" `
    -Run $integratedRuntimeRun `
    -ExtraCheck ($integratedRuntimeRun.Stdout -match "\b15\b" -and $integratedRuntimeRun.Stderr -notmatch "error" -and $integratedFileOk) `
    -Note "GFORTH_WIN_INTERACTIVE enables persistence, Up recall, selected ekey, and k-winch handling."

$historyRun = Invoke-Gforth -Code "require history.fs bye"
$results += New-ProbeResult `
    -Name "require:history.fs" `
    -Expected "FAIL" `
    -Run $historyRun `
    -Note "Full history.fs should not be restored until its startup dependencies are isolated."

if (-not $KeepTemp) {
    Remove-TempFiles
}

if ($Json) {
    $results | ConvertTo-Json -Depth 4
    exit (@($results | Where-Object { -not $_.Matched }).Count)
}

Write-Host "reduced interactive probe"
Write-Host ""
Write-Host "| Probe | Expected | Observed | Matched | Blocker | Note |"
Write-Host "| --- | --- | --- | --- | --- | --- |"

foreach ($result in $results) {
    $matched = if ($result.Matched) { "yes" } else { "no" }
    $blocker = if ($result.Blocker) { $result.Blocker.Replace("|", "\|") } else { "" }
    $note = $result.Note.Replace("|", "\|")
    Write-Host "| $($result.Name) | $($result.Expected) | $($result.Observed) | $matched | $blocker | $note |"
}

$unmatched = @($results | Where-Object { -not $_.Matched })
if ($unmatched.Count -gt 0) {
    Write-Host ""
    Write-Host "Unexpected results:"
    foreach ($result in $unmatched) {
        Write-Host "- $($result.Name): expected $($result.Expected), observed $($result.Observed), exit $($result.ExitCode)"
        if ($result.Stdout) {
            Write-Host "  stdout: $($result.Stdout)"
        }
        if ($result.Stderr) {
            Write-Host "  stderr: $($result.Stderr)"
        }
    }
    exit 1
}

exit 0
