param(
    [string]$NativeExe = ".\build\native\gforth.exe",
    [string]$AdvancedImage = ".\build\native\gforth-advanced.fi",
    [string]$ManualHistoryName = ".gforth-advanced-history",
    [int]$TimeoutSeconds = 8
)

$ErrorActionPreference = "Stop"

function Convert-ToGforthPath {
    param([string]$Path)
    return $Path.Replace("\", "/")
}

function Invoke-Gforth {
    param(
        [string[]]$Arguments,
        [hashtable]$Environment = @{}
    )

    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = (Resolve-Path $NativeExe).Path
    foreach ($arg in $Arguments) {
        $psi.ArgumentList.Add($arg)
    }
    foreach ($key in $Environment.Keys) {
        $psi.Environment[$key] = $Environment[$key]
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

function Invoke-GforthWithInput {
    param(
        [string[]]$Arguments,
        [string]$StandardInput,
        [hashtable]$Environment = @{}
    )

    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = (Resolve-Path $NativeExe).Path
    foreach ($arg in $Arguments) {
        $psi.ArgumentList.Add($arg)
    }
    foreach ($key in $Environment.Keys) {
        $psi.Environment[$key] = $Environment[$key]
    }
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false

    $p = [System.Diagnostics.Process]::Start($psi)
    $p.StandardInput.Write($StandardInput)
    $p.StandardInput.Close()

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

function Test-Word {
    param([string]$Word)

    $result = Invoke-Gforth -Arguments @("-i", $advancedImagePath, "-e", "s`" $Word`" find-name dup . cr bye")
    $passed = ($result.ExitCode -eq 0 -and $result.Stdout -ne "0")
    $detail = if ($result.Stderr) { $result.Stderr.Split([Environment]::NewLine)[0] } else { $result.Stdout }
    Write-Check -Name "word:$Word" -Passed $passed -Detail $detail
    return $passed
}

if (-not (Test-Path $AdvancedImage)) {
    throw "Missing advanced image: $AdvancedImage"
}

$advancedImagePath = (Resolve-Path $AdvancedImage).Path
$allPassed = $true

Write-Host "Advanced image runtime probe"
Write-Host "native: $((Resolve-Path $NativeExe).Path)"
Write-Host "advanced image: $advancedImagePath"
Write-Host ""

$smoke = Invoke-Gforth -Arguments @("-i", $advancedImagePath, "-e", "1 2 + . cr bye")
$smokePassed = ($smoke.ExitCode -eq 0 -and $smoke.Stdout -match "3")
Write-Check -Name "smoke" -Passed $smokePassed -Detail $smoke.Stdout
$allPassed = $allPassed -and $smokePassed

foreach ($word in @("savesystem", "ekey", "k-left", "k-f1", "k-winch", "history-cold", "edit-terminal", "bindkey", "see", "locate", "+status")) {
    $allPassed = (Test-Word -Word $word) -and $allPassed
}

$historyPath = Join-Path (Resolve-Path ".").Path ".tmp-advanced-history-runtime.txt"
if (Test-Path $historyPath) {
    Remove-Item -LiteralPath $historyPath -Recurse -Force
}

$historyText = "advanced-history-runtime"
$historyCode = "history-cold s`" $historyText`" write-history bye"
$historyRun = Invoke-Gforth `
    -Arguments @("-i", $advancedImagePath, "-e", $historyCode) `
    -Environment @{ GFORTHHIST = (Convert-ToGforthPath $historyPath) }

$historyFileOk = $false
if (Test-Path $historyPath -PathType Leaf) {
    $historyFileOk = ((Get-Content -Raw $historyPath).Trim() -eq $historyText)
}
$historyPassed = ($historyRun.ExitCode -eq 0 -and $historyFileOk)
$historyDetail = if (Test-Path $historyPath -PathType Leaf) {
    (Get-Content -Raw $historyPath).Trim()
} elseif ($historyRun.Stderr) {
    $historyRun.Stderr.Split([Environment]::NewLine)[0]
} else {
    "missing history file"
}
Write-Check -Name "runtime:history-write" -Passed $historyPassed -Detail $historyDetail
$allPassed = $allPassed -and $historyPassed

if (Test-Path $historyPath) {
    Remove-Item -LiteralPath $historyPath -Recurse -Force
}

$relativeHistoryName = ".tmp-advanced-relative-history-runtime.txt"
$relativeHistoryPath = Join-Path (Resolve-Path ".").Path $relativeHistoryName
if (Test-Path $relativeHistoryPath) {
    Remove-Item -LiteralPath $relativeHistoryPath -Recurse -Force
}

$relativeHistoryText = "advanced-relative-history-runtime"
$relativeHistoryCode = "history-cold s`" $relativeHistoryText`" write-history bye"
$relativeHistoryRun = Invoke-Gforth `
    -Arguments @("-i", $advancedImagePath, "-e", $relativeHistoryCode) `
    -Environment @{ GFORTHHIST = $relativeHistoryName }

$relativeHistoryOk = $false
if (Test-Path $relativeHistoryPath -PathType Leaf) {
    $relativeHistoryOk = ((Get-Content -Raw $relativeHistoryPath).Trim() -eq $relativeHistoryText)
}
$relativeHistoryPassed = ($relativeHistoryRun.ExitCode -eq 0 -and $relativeHistoryOk)
$relativeHistoryDetail = if (Test-Path $relativeHistoryPath -PathType Leaf) {
    (Get-Content -Raw $relativeHistoryPath).Trim()
} elseif (Test-Path $relativeHistoryPath -PathType Container) {
    "created directory instead of file"
} elseif ($relativeHistoryRun.Stderr) {
    $relativeHistoryRun.Stderr.Split([Environment]::NewLine)[0]
} else {
    "missing history file"
}
Write-Check -Name "runtime:history-relative-path" -Passed $relativeHistoryPassed -Detail $relativeHistoryDetail
$allPassed = $allPassed -and $relativeHistoryPassed

if (Test-Path $relativeHistoryPath) {
    Remove-Item -LiteralPath $relativeHistoryPath -Recurse -Force
}

$manualHistoryPath = Join-Path (Resolve-Path ".").Path $ManualHistoryName
$manualHistoryPassed = -not (Test-Path $manualHistoryPath -PathType Container)
$manualHistoryDetail = if (Test-Path $manualHistoryPath -PathType Container) {
    "stale directory blocks advanced history file"
} elseif (Test-Path $manualHistoryPath -PathType Leaf) {
    "file"
} else {
    "missing"
}
Write-Check -Name "runtime:manual-history-path-usable" -Passed $manualHistoryPassed -Detail $manualHistoryDetail
$allPassed = $allPassed -and $manualHistoryPassed

$replHistoryPath = Join-Path (Resolve-Path ".").Path ".tmp-advanced-repl-history-runtime.txt"
if (Test-Path $replHistoryPath) {
    Remove-Item -LiteralPath $replHistoryPath -Recurse -Force
}

$replRun = Invoke-GforthWithInput `
    -Arguments @("-i", $advancedImagePath) `
    -StandardInput "1 2 + .`nbye`n" `
    -Environment @{ GFORTHHIST = (Convert-ToGforthPath $replHistoryPath) }

$replHistoryOk = $false
if (Test-Path $replHistoryPath -PathType Leaf) {
    $replText = (Get-Content -Raw $replHistoryPath)
    $replHistoryOk = ($replText -match "1 2 \+ \." -and $replText -match "bye")
}
$replPassed = ($replRun.ExitCode -eq 0 -and $replRun.Stdout -match "3" -and $replHistoryOk)
$replDetail = if (Test-Path $replHistoryPath -PathType Leaf) {
    (Get-Content -Raw $replHistoryPath).Trim().Replace([Environment]::NewLine, " | ")
} elseif ($replRun.Stderr) {
    $replRun.Stderr.Split([Environment]::NewLine)[0]
} else {
    "missing history file"
}
Write-Check -Name "runtime:repl-history-save" -Passed $replPassed -Detail $replDetail
$allPassed = $allPassed -and $replPassed

if (Test-Path $replHistoryPath) {
    Remove-Item -LiteralPath $replHistoryPath -Recurse -Force
}

if (-not $allPassed) {
    exit 1
}

exit 0
