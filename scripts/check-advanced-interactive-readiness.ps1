param(
    [string]$NativeExe = ".\build\native\gforth.exe",
    [switch]$FailOnMissing
)

$ErrorActionPreference = "Stop"

function Invoke-GforthCheck {
    param(
        [string]$Name,
        [string]$Code
    )

    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = (Resolve-Path $NativeExe).Path
    $psi.ArgumentList.Add("-e")
    $psi.ArgumentList.Add($Code)
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false

    $p = [System.Diagnostics.Process]::Start($psi)
    $stdout = $p.StandardOutput.ReadToEnd()
    $stderr = $p.StandardError.ReadToEnd()
    $p.WaitForExit()

    [pscustomobject]@{
        Name = $Name
        ExitCode = $p.ExitCode
        Stdout = $stdout.Trim()
        Stderr = $stderr.Trim()
        Passed = ($p.ExitCode -eq 0)
    }
}

function Test-Word {
    param([string]$Word)

    $result = Invoke-GforthCheck -Name "word:$Word" -Code "s`" $Word`" find-name dup . cr bye"
    $result.Passed = ($result.ExitCode -eq 0 -and $result.Stdout -ne "0")
    return $result
}

function Test-Require {
    param([string]$File)

    Invoke-GforthCheck -Name "require:$File" -Code "require $File bye"
}

function Test-AdvancedLoaderOptIn {
    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = (Resolve-Path $NativeExe).Path
    $psi.ArgumentList.Add("windows-interactive-advanced.fs")
    $psi.ArgumentList.Add("-e")
    $psi.ArgumentList.Add("bye")
    $psi.Environment["GFORTH_WIN_ADVANCED"] = "1"
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false

    $p = [System.Diagnostics.Process]::Start($psi)
    $stdout = $p.StandardOutput.ReadToEnd()
    $stderr = $p.StandardError.ReadToEnd()
    $p.WaitForExit()

    [pscustomobject]@{
        Name = "advanced-loader:opt-in-report"
        ExitCode = $p.ExitCode
        Stdout = $stdout.Trim()
        Stderr = $stderr.Trim()
        Passed = ($p.ExitCode -eq 0 -and $stdout -match "ekey missing")
    }
}

$checks = @()

$checks += Invoke-GforthCheck -Name "smoke:-e" -Code "1 2 + . cr bye"

foreach ($word in @("require", "included", "os-type", "ekey", "history-cold", "locate", "see", "+status")) {
    $checks += Test-Word -Word $word
}

foreach ($file in @("windows-interactive-advanced.fs", "ekey.fs", "history.fs", "status-line.fs", "locate1.fs", "see.fs")) {
    $checks += Test-Require -File $file
}

$checks += Test-AdvancedLoaderOptIn

$missingOrFailing = $false

foreach ($check in $checks) {
    if ($check.Passed) {
        Write-Host "[PASS] $($check.Name): $($check.Stdout)"
    } else {
        $missingOrFailing = $true
        Write-Host "[FAIL] $($check.Name): exit $($check.ExitCode)"
        if ($check.Stdout) {
            Write-Host "  stdout: $($check.Stdout)"
        }
        if ($check.Stderr) {
            Write-Host "  stderr: $($check.Stderr)"
        }
    }
}

if ($FailOnMissing -and $missingOrFailing) {
    exit 1
}

exit 0
