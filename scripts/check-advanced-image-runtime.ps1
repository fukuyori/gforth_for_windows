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

foreach ($word in @("savesystem", "ekey", "k-left", "k-f1", "k-winch", "history-cold", "edit-terminal", "bindkey", "see", "locate", "+status", "-status", "status-terminal-ready?", ".status", ".unstatus", "win-status-requested?", "status-auto-enabled?")) {
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

$seeColonRun = Invoke-Gforth -Arguments @("-i", $advancedImagePath, "-e", "see interpret cr bye")
$seeColonPassed = ($seeColonRun.ExitCode -eq 0 -and $seeColonRun.Stdout -match ": interpret")
$seeColonDetail = if ($seeColonRun.Stderr) {
    $seeColonRun.Stderr.Split([Environment]::NewLine)[0]
} else {
    ($seeColonRun.Stdout -replace "`r?`n", " | ").Trim()
}
Write-Check -Name "runtime:see-colon-existing" -Passed $seeColonPassed -Detail $seeColonDetail
$allPassed = $allPassed -and $seeColonPassed

$seePrimitiveRun = Invoke-Gforth -Arguments @("-i", $advancedImagePath, "-e", "see dup cr bye")
$seePrimitivePassed = ($seePrimitiveRun.ExitCode -eq 0 -and $seePrimitiveRun.Stdout -match "Code dup")
$seePrimitiveDetail = if ($seePrimitivePassed) {
    ($seePrimitiveRun.Stdout -replace "`r?`n", " | ").Trim()
} elseif ($seePrimitiveRun.Stderr) {
    $seePrimitiveRun.Stderr.Split([Environment]::NewLine)[0]
} else {
    ($seePrimitiveRun.Stdout -replace "`r?`n", " | ").Trim()
}
Write-Check -Name "runtime:see-primitive" -Passed $seePrimitivePassed -Detail $seePrimitiveDetail
$allPassed = $allPassed -and $seePrimitivePassed

$locateColonRun = Invoke-Gforth -Arguments @("-i", $advancedImagePath, "-e", "locate interpret cr bye")
$locateColonPassed = ($locateColonRun.ExitCode -eq 0 -and $locateColonRun.Stdout -match "kernel/main.fs")
$locateColonDetail = if ($locateColonRun.Stderr) {
    $locateColonRun.Stderr.Split([Environment]::NewLine)[0]
} else {
    ($locateColonRun.Stdout -replace "`r?`n", " | ").Trim()
}
Write-Check -Name "runtime:locate-existing" -Passed $locateColonPassed -Detail $locateColonDetail
$allPassed = $allPassed -and $locateColonPassed

$locatePrimitiveRun = Invoke-Gforth -Arguments @("-i", $advancedImagePath, "-e", "locate + cr bye")
$locatePrimitivePassed = ($locatePrimitiveRun.ExitCode -eq 0 -and $locatePrimitiveRun.Stdout -match "kernel/main.fs")
$locatePrimitiveDetail = if ($locatePrimitiveRun.Stderr) {
    $locatePrimitiveRun.Stderr.Split([Environment]::NewLine)[0]
} else {
    ($locatePrimitiveRun.Stdout -replace "`r?`n", " | ").Trim()
}
Write-Check -Name "runtime:locate-primitive" -Passed $locatePrimitivePassed -Detail $locatePrimitiveDetail
$allPassed = $allPassed -and $locatePrimitivePassed

$sourceRuntimeName = ".tmp-advanced-see-locate-runtime.fs"
$sourceRuntimePath = Join-Path (Resolve-Path ".").Path $sourceRuntimeName
if (Test-Path $sourceRuntimePath) {
    Remove-Item -LiteralPath $sourceRuntimePath -Force
}
Set-Content -LiteralPath $sourceRuntimePath -Value "Variable phase10_value 16 phase10_value ! phase10_value @ . cr see phase10_value cr locate phase10_value cr bye"

$defaultNativeExe = Join-Path (Resolve-Path ".").Path "build\native\gforth.exe"
$defaultAdvancedImage = Join-Path (Resolve-Path ".").Path "build\native\gforth-advanced.fi"
if ((Resolve-Path $NativeExe).Path -eq $defaultNativeExe -and (Resolve-Path $AdvancedImage).Path -eq $defaultAdvancedImage) {
    $sourceRuntimeOutput = & .\build\native\gforth.exe -i .\build\native\gforth-advanced.fi $sourceRuntimeName 2>&1
} else {
    $sourceRuntimeOutput = & $NativeExe -i $AdvancedImage $sourceRuntimeName 2>&1
}
$sourceRuntimeRun = [pscustomobject]@{
    ExitCode = $LASTEXITCODE
    Stdout = ($sourceRuntimeOutput | Out-String).Trim()
    Stderr = ""
}
$sourceRuntimePassed = (
    $sourceRuntimeRun.ExitCode -eq 0 -and
    $sourceRuntimeRun.Stdout -match "\b16\b" -and
    $sourceRuntimeRun.Stdout -match "Variable phase10_value" -and
    $sourceRuntimeRun.Stdout -match "\.tmp-advanced-see-locate-runtime\.fs"
)
$sourceRuntimeDetail = if ($sourceRuntimeRun.Stderr) {
    $sourceRuntimeRun.Stderr.Split([Environment]::NewLine)[0]
} else {
    ($sourceRuntimeRun.Stdout -replace "`r?`n", " | ").Trim()
}
Write-Check -Name "runtime:see-locate-file-source" -Passed $sourceRuntimePassed -Detail $sourceRuntimeDetail
$allPassed = $allPassed -and $sourceRuntimePassed

if (Test-Path $sourceRuntimePath) {
    Remove-Item -LiteralPath $sourceRuntimePath -Force
}

$statusReadyRun = Invoke-Gforth -Arguments @("-i", $advancedImagePath, "-e", "status-terminal-ready? . cr bye")
$statusReadyPassed = ($statusReadyRun.ExitCode -eq 0 -and $statusReadyRun.Stdout -match "-1")
$statusReadyDetail = if ($statusReadyRun.Stderr) {
    $statusReadyRun.Stderr.Split([Environment]::NewLine)[0]
} else {
    $statusReadyRun.Stdout
}
Write-Check -Name "runtime:status-terminal-ready" -Passed $statusReadyPassed -Detail $statusReadyDetail
$allPassed = $allPassed -and $statusReadyPassed

$statusAutoRun = Invoke-Gforth `
    -Arguments @("-i", $advancedImagePath, "-e", "bootmessage status-auto-enabled? . cr .status .unstatus -status cr bye") `
    -Environment @{ GFORTH_WIN_STATUS = "1" }
$statusAutoPassed = (
    $statusAutoRun.ExitCode -eq 0 -and
    $statusAutoRun.Stdout -match "-1" -and
    $statusAutoRun.Stdout.Contains("$([char]27)[")
)
$statusAutoDetail = if ($statusAutoRun.Stderr) {
    $statusAutoRun.Stderr.Split([Environment]::NewLine)[0]
} else {
    ($statusAutoRun.Stdout -replace "`e", "<ESC>" -replace "`r?`n", " | ").Trim()
}
Write-Check -Name "runtime:status-auto-opt-in" -Passed $statusAutoPassed -Detail $statusAutoDetail
$allPassed = $allPassed -and $statusAutoPassed

$statusBasicRun = Invoke-Gforth -Arguments @("-i", $advancedImagePath, "-e", "+status .status .unstatus -status cr bye")
$statusBasicPassed = ($statusBasicRun.ExitCode -eq 0)
$statusBasicDetail = if ($statusBasicRun.Stderr) {
    $statusBasicRun.Stderr.Split([Environment]::NewLine)[0]
} else {
    ($statusBasicRun.Stdout -replace "`r?`n", " | ").Trim()
}
Write-Check -Name "runtime:status-basic-redraw" -Passed $statusBasicPassed -Detail $statusBasicDetail
$allPassed = $allPassed -and $statusBasicPassed

$statusStackRun = Invoke-Gforth -Arguments @("-i", $advancedImagePath, "-e", "1 2 3 +status .status .unstatus -status cr .s cr bye")
$statusStackPassed = (
    $statusStackRun.ExitCode -eq 0 -and
    $statusStackRun.Stdout -match "<3>\s+1\s+2\s+3"
)
$statusStackDetail = if ($statusStackRun.Stderr) {
    $statusStackRun.Stderr.Split([Environment]::NewLine)[0]
} else {
    ($statusStackRun.Stdout -replace "`r?`n", " | ").Trim()
}
Write-Check -Name "runtime:status-stack-redraw" -Passed $statusStackPassed -Detail $statusStackDetail
$allPassed = $allPassed -and $statusStackPassed

$statusCoexistRun = Invoke-Gforth -Arguments @("-i", $advancedImagePath, "-e", "+status 1 2 + . cr see interpret cr locate interpret cr .status .unstatus -status bye")
$statusCoexistPassed = (
    $statusCoexistRun.ExitCode -eq 0 -and
    $statusCoexistRun.Stdout -match "\b3\b" -and
    $statusCoexistRun.Stdout -match ": interpret" -and
    $statusCoexistRun.Stdout -match "kernel/main.fs"
)
$statusCoexistDetail = if ($statusCoexistRun.Stderr) {
    $statusCoexistRun.Stderr.Split([Environment]::NewLine)[0]
} else {
    ($statusCoexistRun.Stdout -replace "`r?`n", " | ").Trim()
}
Write-Check -Name "runtime:status-see-locate-coexist" -Passed $statusCoexistPassed -Detail $statusCoexistDetail
$allPassed = $allPassed -and $statusCoexistPassed

if (-not $allPassed) {
    exit 1
}

exit 0
