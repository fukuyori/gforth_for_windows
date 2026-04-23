param(
    [string]$NativeExe = ".\build\native\gforth.exe",
    [int]$RepeatCount = 3,
    [int]$TimeoutSeconds = 10,
    [switch]$Json
)

$ErrorActionPreference = "Stop"

function Invoke-Gforth {
    param([string[]]$Arguments)

    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = (Resolve-Path $NativeExe).Path
    foreach ($arg in $Arguments) {
        $psi.ArgumentList.Add($arg)
    }
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false

    $p = [System.Diagnostics.Process]::Start($psi)
    if (-not $p.WaitForExit($TimeoutSeconds * 1000)) {
        try {
            $p.Kill()
            $p.WaitForExit()
        } catch {
        }
        $stdout = $p.StandardOutput.ReadToEnd()
        return [pscustomobject]@{
            ExitCode = -999
            Stdout = $stdout.Trim()
            Stderr = "Timed out after $TimeoutSeconds seconds"
        }
    }

    $stdout = $p.StandardOutput.ReadToEnd()
    $stderr = $p.StandardError.ReadToEnd()

    [pscustomobject]@{
        ExitCode = $p.ExitCode
        Stdout = $stdout.Trim()
        Stderr = $stderr.Trim()
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

function Get-Category {
    param(
        [string]$Target,
        [string]$Mode,
        [string]$Blocker
    )

    if ($Mode -eq "word") {
        return "missing-word"
    }

    if ($Blocker -eq "timeout") {
        return "compact-image-runtime-hang"
    }

    switch ($Blocker) {
        "{" { return "startup-context-dependency" }
        "nocov[" { return "startup-context-dependency" }
        "[DO]" { return "startup-context-dependency" }
        "to-table:" { return "startup-context-dependency" }
        "translator-max-offset#" { return "startup-context-dependency" }
        "save-cursor-position" { return "startup-context-dependency" }
        "restore-cursor-position" { return "startup-context-dependency" }
        "erase-display" { return "startup-context-dependency" }
        "base-execute" { return "startup-context-dependency" }
        "f.s-precision" { return "startup-context-dependency" }
        "order" { return "startup-context-dependency" }
        "os-type" { return "startup-context-dependency" }
        "User" { return "startup-context-dependency" }
        "DOES>" { return "compact-image-compile-limitation" }
        '$Variable' { return "image-builder-version-mismatch" }
        ";" { return "compact-image-compile-limitation" }
        "1+" { return "compact-image-compile-limitation" }
        "false" { return "compact-image-compile-limitation" }
        "find-name" { return "compact-image-compile-limitation" }
    }

    if ($Target -eq "windows-interactive-advanced.fs") {
        return "safe-runtime-loader"
    }

    return "unclassified"
}

function Get-NextAction {
    param([string]$Category)

    switch ($Category) {
        "missing-word" {
            return "Decide whether this word belongs in the compact image, runtime loader, or advanced image."
        }
        "startup-context-dependency" {
            return "Do not require this file directly yet; isolate the minimum startup/build-context definitions it needs."
        }
        "image-builder-version-mismatch" {
            return "Use a current image builder or avoid this bootstrap path for advanced image creation."
        }
        "compact-image-compile-limitation" {
            return "Keep this out of default startup; test only top-level interpreted probes or a fuller image."
        }
        "safe-runtime-loader" {
            return "Keep as opt-in reporting until activation prerequisites are available."
        }
        default {
            return "Inspect stderr manually and add a category once the blocker is understood."
        }
    }
}

function New-RunResult {
    param(
        [object]$Run,
        [bool]$Passed
    )

    $blocker = if ($Passed) {
        ""
    } elseif ($Run.ExitCode -eq -999) {
        "timeout"
    } else {
        Get-BlockerToken -Text $Run.Stderr
    }

    [pscustomobject]@{
        Passed = $Passed
        ExitCode = $Run.ExitCode
        Blocker = $blocker
        Stdout = $Run.Stdout
        Stderr = $Run.Stderr
    }
}

function New-AggregatedResult {
    param(
        [string]$Target,
        [string]$Mode,
        [object[]]$Runs
    )

    $passedRuns = @($Runs | Where-Object { $_.Passed })
    $failedRuns = @($Runs | Where-Object { -not $_.Passed })
    $blockers = @($failedRuns | ForEach-Object { $_.Blocker } | Where-Object { $_ } | Sort-Object -Unique)
    $categories = @()

    if ($failedRuns.Count -eq 0) {
        $categories = @("ready")
    } else {
        foreach ($blocker in $blockers) {
            $categories += Get-Category -Target $Target -Mode $Mode -Blocker $blocker
        }
        if ($blockers.Count -eq 0) {
            $categories += Get-Category -Target $Target -Mode $Mode -Blocker ""
        }
        $categories = @($categories | Sort-Object -Unique)
    }

    $result = if ($failedRuns.Count -eq 0) {
        "PASS"
    } elseif ($passedRuns.Count -gt 0) {
        "FLAKY"
    } else {
        "FAIL"
    }

    $primaryCategory = $categories[0]

    [pscustomobject]@{
        Target = $Target
        Mode = $Mode
        Result = $result
        Runs = $Runs.Count
        PassedRuns = $passedRuns.Count
        ExitCodes = (@($Runs | ForEach-Object { $_.ExitCode } | Sort-Object -Unique) -join ",")
        Blockers = ($blockers -join ",")
        Categories = ($categories -join ",")
        NextAction = if ($result -eq "PASS") { "No action needed for this check." } else { Get-NextAction -Category $primaryCategory }
        Details = $Runs
    }
}

$results = @()

foreach ($word in @(
    "os-type",
    "ekey",
    "history-cold",
    "locate",
    "see",
    "+status",
    "savesystem",
    "comp-image",
    "k-winch",
    "winch?",
    "form",
    "save-cursor-position",
    "restore-cursor-position",
    "erase-display",
    "base-execute",
    "f.s-precision",
    "order"
)) {
    $runs = @()
    for ($i = 0; $i -lt $RepeatCount; $i++) {
        $run = Invoke-Gforth -Arguments @("-e", "s`" $word`" find-name dup . cr bye")
        $passed = ($run.ExitCode -eq 0 -and $run.Stdout -ne "0")
        $runs += New-RunResult -Run $run -Passed $passed
    }
    $results += New-AggregatedResult -Target $word -Mode "word" -Runs $runs
}

foreach ($file in @("windows-interactive-advanced.fs", "ekey.fs", "history.fs", "status-line.fs", "locate1.fs", "see.fs")) {
    $runs = @()
    for ($i = 0; $i -lt $RepeatCount; $i++) {
        $run = Invoke-Gforth -Arguments @("-e", "require $file bye")
        $passed = ($run.ExitCode -eq 0)
        $runs += New-RunResult -Run $run -Passed $passed
    }
    $results += New-AggregatedResult -Target $file -Mode "require" -Runs $runs
}

if ($Json) {
    $results | ConvertTo-Json -Depth 4
    exit 0
}

Write-Host "Advanced interactive blocker classification"
Write-Host ""
Write-Host "| Target | Mode | Result | Passed/Runs | Blockers | Categories |"
Write-Host "| --- | --- | --- | --- | --- | --- |"

foreach ($result in $results) {
    $blockers = if ($result.Blockers) { $result.Blockers.Replace("|", "\|") } else { "" }
    Write-Host "| $($result.Target) | $($result.Mode) | $($result.Result) | $($result.PassedRuns)/$($result.Runs) | $blockers | $($result.Categories) |"
}

Write-Host ""
Write-Host "Next actions:"
foreach ($result in $results | Where-Object { $_.Result -ne "PASS" }) {
    Write-Host "- $($result.Target): $($result.NextAction)"
}
