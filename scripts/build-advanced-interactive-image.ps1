param(
    [string]$NativeExe = ".\build\native\gforth.exe",
    [string]$ImageBuilderExe = ".\build\native\gforth-ditc.exe",
    [string]$OutputImage = ".\build\native\gforth-advanced.fi",
    [string]$BootstrapExe = "C:\Program Files (x86)\gforth\gforth.exe",
    [switch]$IncludeEkey,
    [switch]$IncludeHistory,
    [switch]$ProbeOnly
)

$ErrorActionPreference = "Stop"
$script:BuildWorkingDirectory = (Get-Location).Path

function Resolve-ExistingPath {
    param(
        [string]$Path,
        [string]$Description
    )

    if (-not (Test-Path $Path)) {
        throw "Missing $Description`: $Path"
    }
    return (Resolve-Path $Path).Path
}

function Convert-ToGforthPath {
    param([string]$Path)
    return $Path.Replace("\", "/")
}

function Invoke-Gforth {
    param(
        [string]$Exe,
        [string[]]$Arguments
    )

    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = $Exe
    foreach ($arg in $Arguments) {
        $psi.ArgumentList.Add($arg)
    }
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false
    $psi.WorkingDirectory = $script:BuildWorkingDirectory

    $p = [System.Diagnostics.Process]::Start($psi)
    $stdout = $p.StandardOutput.ReadToEnd()
    $stderr = $p.StandardError.ReadToEnd()
    $p.WaitForExit()

    [pscustomobject]@{
        ExitCode = $p.ExitCode
        Stdout = $stdout.Trim()
        Stderr = $stderr.Trim()
    }
}

function Test-Word {
    param(
        [string]$Exe,
        [string]$Word
    )

    $result = Invoke-Gforth -Exe $Exe -Arguments @("-e", "s`" $Word`" find-name dup . cr bye")
    return ($result.ExitCode -eq 0 -and $result.Stdout -ne "0")
}

function Test-WordResult {
    param(
        [string]$Exe,
        [string]$Word
    )

    $result = Invoke-Gforth -Exe $Exe -Arguments @("-e", "s`" $Word`" find-name dup . cr bye")
    $present = ($result.ExitCode -eq 0 -and $result.Stdout -ne "0")
    [pscustomobject]@{
        Word = $Word
        Result = $result
        Present = $present
    }
}

function Test-Require {
    param(
        [string]$Exe,
        [string]$File
    )

    Invoke-Gforth -Exe $Exe -Arguments @("-e", "require $File bye")
}

function Test-Code {
    param(
        [string]$Exe,
        [string]$Code
    )

    Invoke-Gforth -Exe $Exe -Arguments @("-e", "$Code bye")
}

function Get-BlockerToken {
    param([string]$Text)

    $match = [regex]::Match($Text, ">>>([^<]+)<<<")
    if ($match.Success) {
        return $match.Groups[1].Value.Trim()
    }
    return ""
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

function Write-RunCheck {
    param(
        [string]$Name,
        [object]$Result,
        [bool]$Passed
    )

    $detail = ""
    if ($Result.Stdout) {
        $detail = $Result.Stdout
        if ($detail.Length -gt 240) {
            $detail = $detail.Substring(0, 240) + " ..."
        }
    }
    if (-not $Passed) {
        $blocker = Get-BlockerToken -Text $Result.Stderr
        if ($blocker) {
            $detail = "blocker=$blocker"
        } elseif ($Result.Stderr) {
            $detail = "stderr=$($Result.Stderr.Split([Environment]::NewLine)[0])"
        }
    }
    Write-Check -Name $Name -Passed $Passed -Detail $detail
}

function Write-WordMatrix {
    param(
        [string]$Title,
        [string]$Exe,
        [string[]]$Words
    )

    Write-Host ""
    Write-Host "== $Title word surface =="
    foreach ($word in $Words) {
        $wordResult = Test-WordResult -Exe $Exe -Word $word
        Write-RunCheck -Name "word:$word" -Result $wordResult.Result -Passed $wordResult.Present
    }
}

function Write-CandidateMatrix {
    param(
        [string]$Title,
        [string]$Exe,
        [object[]]$Candidates
    )

    Write-Host ""
    Write-Host "== $Title candidate load paths =="
    foreach ($candidate in $Candidates) {
        $result = Test-Code -Exe $Exe -Code $candidate.Code
        $passed = ($result.ExitCode -eq 0 -and (-not $candidate.ExpectedPattern -or $result.Stdout -match $candidate.ExpectedPattern))
        Write-RunCheck -Name $candidate.Name -Result $result -Passed $passed
    }
}

function Write-InvocationCandidateMatrix {
    param(
        [string]$Title,
        [string]$Exe,
        [object[]]$Candidates
    )

    Write-Host ""
    Write-Host "== $Title invocation candidates =="
    foreach ($candidate in $Candidates) {
        $attempts = 1
        if ($candidate.RetryCount) {
            $attempts = 1 + [int]$candidate.RetryCount
        }
        $result = $null
        $passed = $false
        for ($attempt = 1; $attempt -le $attempts; $attempt++) {
            if ($candidate.OutputImage -and (Test-Path $candidate.OutputImage)) {
                Remove-Item -LiteralPath $candidate.OutputImage -Force
            }
            $result = Invoke-Gforth -Exe $Exe -Arguments $candidate.Arguments
            $passed = ($result.ExitCode -eq 0 -and (-not $candidate.ExpectedPattern -or $result.Stdout -match $candidate.ExpectedPattern))
            if ($passed -and $candidate.OutputImage) {
                $passed = ((Test-Path $candidate.OutputImage) -and ((Get-Item $candidate.OutputImage).Length -gt 0))
            }
            if ($passed) {
                break
            }
        }
        Write-RunCheck -Name $candidate.Name -Result $result -Passed $passed
        if ($candidate.OutputImage) {
            if (Test-Path $candidate.OutputImage) {
                $imageInfo = Get-Item $candidate.OutputImage
                Write-Check -Name "$($candidate.Name):output" -Passed ($imageInfo.Length -gt 0) -Detail "$($imageInfo.FullName) ($($imageInfo.Length) bytes)"
            } else {
                Write-Check -Name "$($candidate.Name):output" -Passed $false -Detail $candidate.OutputImage
            }
        }
    }
}

function Write-ImageSurfaceMatrix {
    param(
        [string]$Title,
        [string]$Exe,
        [object[]]$Images,
        [string[]]$Words
    )

    Write-Host ""
    Write-Host "== $Title image word surface =="
    foreach ($image in $Images) {
        if (-not (Test-Path $image.Path)) {
            Write-Check -Name "$($image.Name):exists" -Passed $false -Detail $image.Path
            continue
        }

        $imagePath = (Resolve-Path $image.Path).Path
        $imageInfo = Get-Item $imagePath
        Write-Check -Name "$($image.Name):exists" -Passed $true -Detail "$imagePath ($($imageInfo.Length) bytes)"
        foreach ($word in $Words) {
            $result = Invoke-Gforth -Exe $Exe -Arguments @("-i", $imagePath, "-e", "s`" $word`" find-name dup . cr bye")
            $present = ($result.ExitCode -eq 0 -and $result.Stdout -ne "0")
            Write-RunCheck -Name "$($image.Name):word:$word" -Result $result -Passed $present
        }
    }
}

function Invoke-ImageBuildStep {
    param(
        [string]$Name,
        [string]$Exe,
        [string[]]$Arguments,
        [string]$OutputImage,
        [int]$RetryCount = 2,
        [string]$RejectOutputPattern
    )

    $attempts = 1 + $RetryCount
    $result = $null
    $passed = $false

    for ($attempt = 1; $attempt -le $attempts; $attempt++) {
        if ($OutputImage -and (Test-Path $OutputImage)) {
            Remove-Item -LiteralPath $OutputImage -Force
        }
        $result = Invoke-Gforth -Exe $Exe -Arguments $Arguments
        $passed = ($result.ExitCode -eq 0)
        if ($passed -and $RejectOutputPattern) {
            $combinedOutput = "$($result.Stdout)`n$($result.Stderr)"
            $passed = ($combinedOutput -notmatch $RejectOutputPattern)
        }
        if ($passed -and $OutputImage) {
            $passed = ((Test-Path $OutputImage) -and ((Get-Item $OutputImage).Length -gt 0))
        }
        if ($passed) {
            break
        }
    }

    Write-RunCheck -Name $Name -Result $result -Passed $passed
    if ($OutputImage) {
        if (Test-Path $OutputImage) {
            $imageInfo = Get-Item $OutputImage
            Write-Check -Name "$Name`:output" -Passed ($imageInfo.Length -gt 0) -Detail "$($imageInfo.FullName) ($($imageInfo.Length) bytes)"
        } else {
            Write-Check -Name "$Name`:output" -Passed $false -Detail $OutputImage
        }
    }

    return $passed
}

function Test-ImageSmoke {
    param(
        [string]$Name,
        [string]$Exe,
        [string]$Image
    )

    $result = Invoke-Gforth -Exe $Exe -Arguments @("-i", $Image, "-e", "1 2 + . cr bye")
    $passed = ($result.ExitCode -eq 0 -and $result.Stdout -match "3")
    Write-RunCheck -Name $Name -Result $result -Passed $passed
    return $passed
}

function Test-ImageWord {
    param(
        [string]$Name,
        [string]$Exe,
        [string]$Image,
        [string]$Word
    )

    $result = Invoke-Gforth -Exe $Exe -Arguments @("-i", $Image, "-e", "s`" $Word`" find-name dup . cr bye")
    $passed = ($result.ExitCode -eq 0 -and $result.Stdout -ne "0")
    Write-RunCheck -Name $Name -Result $result -Passed $passed
    return $passed
}

$native = Resolve-ExistingPath -Path $NativeExe -Description "native gforth executable"
$imageBuilder = Resolve-ExistingPath -Path $ImageBuilderExe -Description "DITC image-builder executable"
$repoRoot = (Resolve-Path ".").Path
$outputFullPath = [System.IO.Path]::GetFullPath($OutputImage, $repoRoot)
$outputDirectory = [System.IO.Path]::GetDirectoryName($outputFullPath)
$defaultImage = Join-Path (Split-Path -Parent $native) "gforth.fi"
$kernelImage = Join-Path $repoRoot "kernl64l.fi"
$nativeExeForForth = Convert-ToGforthPath $native
$repoRootForForth = Convert-ToGforthPath $repoRoot
$imageBuilderWords = @(
    "savesystem",
    "comp-image",
    "dump-fi",
    "slurp-file",
    "sections",
    "current-section",
    "section-dp",
    '$Variable',
    "MEM+DO",
    "{",
    "{:",
    "nocov[",
    "base-execute"
)
$environmentWords = @(
    "environment-wordlist",
    "environment?",
    "os-type",
    "vocabulary",
    "wordlist",
    "search-wordlist",
    "get-current",
    "set-current",
    "get-order",
    "set-order"
)
$advancedSurfaceWords = @(
    "savesystem",
    "comp-image",
    "ekey",
    "history-cold",
    "see",
    "locate",
    "+status"
)
$localImages = @(
    [pscustomobject]@{
        Name = "default"
        Path = $defaultImage
    },
    [pscustomobject]@{
        Name = "kernel"
        Path = $kernelImage
    },
    [pscustomobject]@{
        Name = "installer-stage"
        Path = (Join-Path $repoRoot "build/installer/stage/gforth.fi")
    },
    [pscustomobject]@{
        Name = "tmp-stagecheck"
        Path = (Join-Path $repoRoot ".tmp-stagecheck/gforth.fi")
    }
)
$nativeCandidates = @(
    [pscustomobject]@{
        Name = "native candidate:minimal-colon"
        Code = ': empty ; s" empty" find-name dup . cr'
        ExpectedPattern = "\S*[1-9]\S*"
    },
    [pscustomobject]@{
        Name = "native candidate:literal-colon"
        Code = ': one 1 ; one . cr'
        ExpectedPattern = "1"
    },
    [pscustomobject]@{
        Name = "native candidate:to.fs"
        Code = 'require to.fs s" to-table:" find-name dup . cr'
        ExpectedPattern = "\S*[1-9]\S*"
    },
    [pscustomobject]@{
        Name = "native candidate:environ.fs"
        Code = 'require environ.fs s" environment-wordlist" find-name dup . cr'
        ExpectedPattern = "\S*[1-9]\S*"
    },
    [pscustomobject]@{
        Name = "native candidate:envos-minimal-shim"
        Code = ': environment-wordlist 0 ; : set-current drop ; require envos.fs os-type type cr'
        ExpectedPattern = "win32"
    },
    [pscustomobject]@{
        Name = "native candidate:to+float"
        Code = 'require to.fs require float.fs s" fvalue" find-name dup . cr'
        ExpectedPattern = "\S*[1-9]\S*"
    },
    [pscustomobject]@{
        Name = "native candidate:to+glocals"
        Code = 'require to.fs require glocals.fs s" {:" find-name dup . cr'
        ExpectedPattern = "\S*[1-9]\S*"
    },
    [pscustomobject]@{
        Name = "native candidate:debugs"
        Code = 'require debugs.fs s" nocov[" find-name dup . cr'
        ExpectedPattern = "\S*[1-9]\S*"
    },
    [pscustomobject]@{
        Name = "native candidate:builder-prefix"
        Code = 'require to.fs require glocals.fs require stuff.fs require savesys.fs s" savesystem" find-name dup . cr'
        ExpectedPattern = "\S*[1-9]\S*"
    }
)
$nativeStartupPrefixCandidates = @(
    [pscustomobject]@{
        Name = "native compile-context:literal-before-rec-sequence"
        Code = ': one 1 ; one . cr'
        ExpectedPattern = "1"
    },
    [pscustomobject]@{
        Name = "native compile-context:primitive-before-rec-sequence"
        Code = ': plus + ; 1 2 plus . cr'
        ExpectedPattern = "3"
    },
    [pscustomobject]@{
        Name = "native compile-context:primitive-after-rec-sequence"
        Code = 'require rec-sequence.fs : plus + ; 1 2 plus . cr'
        ExpectedPattern = "3"
    },
    [pscustomobject]@{
        Name = "native compile-context:literal-after-rec-sequence"
        Code = 'require rec-sequence.fs : one 1 ; one . cr'
        ExpectedPattern = "1"
    },
    [pscustomobject]@{
        Name = "native compile-context:struct-core-after-rec-sequence"
        Code = 'require rec-sequence.fs : naligned 1- tuck + swap invert and ; 3 8 naligned . cr'
        ExpectedPattern = "8"
    },
    [pscustomobject]@{
        Name = "native startup-prefix:except"
        Code = 'require except.fs 1 . cr'
        ExpectedPattern = "1"
    },
    [pscustomobject]@{
        Name = "native startup-prefix:except-after-rec-sequence"
        Code = 'require rec-sequence.fs require except.fs 1 . cr'
        ExpectedPattern = "1"
    },
    [pscustomobject]@{
        Name = "native startup-prefix:rec-sequence"
        Code = 'require rec-sequence.fs 1 . cr'
        ExpectedPattern = "1"
    },
    [pscustomobject]@{
        Name = "native startup-prefix:search"
        Code = 'require rec-sequence.fs require search.fs 1 . cr'
        ExpectedPattern = "1"
    },
    [pscustomobject]@{
        Name = "native startup-prefix:options"
        Code = 'require rec-sequence.fs require search.fs require options.fs 1 . cr'
        ExpectedPattern = "1"
    },
    [pscustomobject]@{
        Name = "native startup-prefix:environ"
        Code = 'require rec-sequence.fs require search.fs require options.fs require environ.fs 1 . cr'
        ExpectedPattern = "1"
    },
    [pscustomobject]@{
        Name = "native startup-prefix:envos"
        Code = 'require rec-sequence.fs require search.fs require options.fs require environ.fs require ~+/envos.fs os-type type cr'
        ExpectedPattern = "win32"
    },
    [pscustomobject]@{
        Name = "native startup-prefix:to"
        Code = 'require rec-sequence.fs require search.fs require options.fs require environ.fs require ~+/envos.fs require to.fs s" to-table:" find-name dup . cr'
        ExpectedPattern = "\S*[1-9]\S*"
    }
)
$bootstrapCandidates = @(
    [pscustomobject]@{
        Name = "bootstrap candidate:kernel/stringk.fs"
        Code = 'require kernel/stringk.fs s" $Variable" find-name dup . cr'
        ExpectedPattern = "\S*[1-9]\S*"
    },
    [pscustomobject]@{
        Name = 'bootstrap candidate:simple-$Variable-shim+sections'
        Code = ': $Variable Create 0 , ; require sections.fs s" sections" find-name dup . cr'
        ExpectedPattern = "\S*[1-9]\S*"
    },
    [pscustomobject]@{
        Name = 'bootstrap candidate:simple-$Variable-shim+comp-i'
        Code = ': $Variable Create 0 , ; require comp-i.fs s" comp-image" find-name dup . cr'
        ExpectedPattern = "\S*[1-9]\S*"
    }
)
$nativeInvocationCandidates = @(
    [pscustomobject]@{
        Name = "native invocation:envos-only"
        Arguments = @("-i", $defaultImage, "-e", 'require envos.fs s" os-type" find-name dup . cr bye')
        ExpectedPattern = "\S*[1-9]\S*"
    },
    [pscustomobject]@{
        Name = "native invocation:envos-minimal-shim"
        Arguments = @("-i", $defaultImage, "-e", ': environment-wordlist 0 ; : set-current drop ; require envos.fs os-type type cr bye')
        ExpectedPattern = "win32"
    },
    [pscustomobject]@{
        Name = "native invocation:exboot+startup"
        Arguments = @("-i", $defaultImage, "exboot.fs", "startup.fs", "-e", 's" savesystem" find-name dup . cr s" ekey" find-name dup . cr s" history-cold" find-name dup . cr s" see" find-name dup . cr s" locate" find-name dup . cr bye')
        ExpectedPattern = "\S*[1-9]\S*"
    },
    [pscustomobject]@{
        Name = "native invocation:rec-sequence+exboot+startup"
        Arguments = @("-i", $defaultImage, "rec-sequence.fs", "exboot.fs", "startup.fs", "-e", 's" savesystem" find-name dup . cr s" os-type" find-name dup . cr bye')
        ExpectedPattern = "\S*[1-9]\S*"
    },
    [pscustomobject]@{
        Name = "native invocation:clear-dictionary-save"
        Arguments = @("--clear-dictionary", "--no-offset-im", "--die-on-signal=2", "-i", $defaultImage, "exboot.fs", "startup.fs", "-e", 's" savesystem" find-name dup . cr bye')
        ExpectedPattern = "\S*[1-9]\S*"
    },
    [pscustomobject]@{
        Name = "native invocation:clear-dictionary-rec-sequence-save"
        Arguments = @("--clear-dictionary", "--no-offset-im", "--die-on-signal=2", "-i", $defaultImage, "rec-sequence.fs", "exboot.fs", "startup.fs", "-e", 's" savesystem" find-name dup . cr bye')
        ExpectedPattern = "\S*[1-9]\S*"
    },
    [pscustomobject]@{
        Name = "native invocation:gforthmi-no-offset-save"
        Arguments = @("--clear-dictionary", "--no-offset-im", "--die-on-signal=2", "-p", ".;~+;.", "-i", $kernelImage, "exboot.fs", "startup.fs", "-e", 'savesystem build/native/gforth-mi-probe-no-offset.fi')
        ExpectedPattern = $null
        OutputImage = (Join-Path $repoRoot "build/native/gforth-mi-probe-no-offset.fi")
        RetryCount = 2
    },
    [pscustomobject]@{
        Name = "native invocation:gforthmi-rec-sequence-no-offset-save"
        Arguments = @("--clear-dictionary", "--no-offset-im", "--die-on-signal=2", "-p", ".;~+;.", "-i", $kernelImage, "rec-sequence.fs", "exboot.fs", "startup.fs", "-e", 'savesystem build/native/gforth-mi-rec-probe-no-offset.fi')
        ExpectedPattern = $null
        OutputImage = (Join-Path $repoRoot "build/native/gforth-mi-rec-probe-no-offset.fi")
        RetryCount = 2
    },
    [pscustomobject]@{
        Name = "native invocation:gforthmi-offset-save"
        Arguments = @("--clear-dictionary", "--offset-image", "--die-on-signal=2", "-p", ".;~+;.", "-i", $kernelImage, "exboot.fs", "startup.fs", "-e", 'savesystem build/native/gforth-mi-probe-offset.fi')
        ExpectedPattern = $null
        OutputImage = (Join-Path $repoRoot "build/native/gforth-mi-probe-offset.fi")
        RetryCount = 2
    },
    [pscustomobject]@{
        Name = "native invocation:gforthmi-comp-image"
        Arguments = @("--die-on-signal=2", "-p", ".;~+;.", "-i", $kernelImage, "-e", "3", "exboot.fs", "startup.fs", "comp-i.fs", "-e", 'comp-image build/native/gforth-mi-probe-no-offset.fi build/native/gforth-mi-probe-offset.fi build/native/gforth-advanced-probe.fi bye')
        ExpectedPattern = $null
        OutputImage = (Join-Path $repoRoot "build/native/gforth-advanced-probe.fi")
        RetryCount = 2
    },
    [pscustomobject]@{
        Name = "native invocation:gforthmi-comp-image-two-no-offset"
        Arguments = @("--die-on-signal=2", "-p", ".;~+;.", "-i", $kernelImage, "-e", "3", "exboot.fs", "startup.fs", "comp-i.fs", "-e", 'comp-image build/native/gforth-mi-probe-no-offset.fi build/native/gforth-mi-rec-probe-no-offset.fi build/native/gforth-advanced-two-no-offset.fi bye')
        ExpectedPattern = $null
        OutputImage = (Join-Path $repoRoot "build/native/gforth-advanced-two-no-offset.fi")
        RetryCount = 2
    }
)
$bootstrapCrossCandidates = @(
    [pscustomobject]@{
        Name = "bootstrap cross:kernel-only"
        Arguments = @(
            "--die-on-signal",
            "-m64M",
            "-p", ".;$repoRootForForth",
            "-e", "fpath= .|./kernel|~+|.",
            "-e", 's" mach64l.fs" include kernel/main.fs',
            "-e", "save-cross build/native/gforth-kernel-only-probe.fi $nativeExeForForth bye"
        )
        ExpectedPattern = "Saving to"
        OutputImage = (Join-Path $repoRoot "build/native/gforth-kernel-only-probe.fi")
    },
    [pscustomobject]@{
        Name = "bootstrap cross:pre-search+kernel"
        Arguments = @(
            "--die-on-signal",
            "-m64M",
            "-p", ".;$repoRootForForth",
            "-e", "fpath= .|./kernel|~+|.",
            "-e", 'require search.fs s" mach64l.fs" include kernel/main.fs',
            "-e", "save-cross build/native/gforth-pre-search-probe.fi $nativeExeForForth bye"
        )
        ExpectedPattern = "Saving to"
        OutputImage = (Join-Path $repoRoot "build/native/gforth-pre-search-probe.fi")
    },
    [pscustomobject]@{
        Name = "bootstrap cross:pre-builder+kernel"
        Arguments = @(
            "--die-on-signal",
            "-m64M",
            "-p", ".;$repoRootForForth",
            "-e", "fpath= .|./kernel|~+|.",
            "-e", 'require to.fs require glocals.fs require stuff.fs require savesys.fs s" mach64l.fs" include kernel/main.fs',
            "-e", "save-cross build/native/gforth-pre-builder-probe.fi $nativeExeForForth bye"
        )
        ExpectedPattern = "Saving to"
        OutputImage = (Join-Path $repoRoot "build/native/gforth-pre-builder-probe.fi")
    },
    [pscustomobject]@{
        Name = "bootstrap cross:kernel+savesys"
        Arguments = @(
            "--die-on-signal",
            "-m64M",
            "-p", ".;$repoRootForForth",
            "-e", "fpath= .|./kernel|~+|.",
            "-e", 's" mach64l.fs" include kernel/main.fs include savesys.fs',
            "-e", "save-cross build/native/gforth-builder-probe.fi $nativeExeForForth bye"
        )
        ExpectedPattern = "Saving to"
        OutputImage = (Join-Path $repoRoot "build/native/gforth-builder-probe.fi")
    },
    [pscustomobject]@{
        Name = "bootstrap cross:kernel+builder-prefix"
        Arguments = @(
            "--die-on-signal",
            "-m64M",
            "-p", ".;$repoRootForForth",
            "-e", "fpath= .|./kernel|~+|.",
            "-e", 's" mach64l.fs" include kernel/main.fs include to.fs include glocals.fs include stuff.fs include savesys.fs',
            "-e", "save-cross build/native/gforth-builder-probe2.fi $nativeExeForForth bye"
        )
        ExpectedPattern = "Saving to"
        OutputImage = (Join-Path $repoRoot "build/native/gforth-builder-probe2.fi")
    }
)

$outputParentOk = [string]::IsNullOrEmpty($outputDirectory) -or (Test-Path $outputDirectory)
$separateFromDefault = ([System.IO.Path]::GetFullPath($defaultImage) -ne $outputFullPath)
$advancedLoaderExists = Test-Path "windows-interactive-advanced.fs"

if ($ProbeOnly) {
Write-Host "Advanced interactive image probe"
Write-Host "native: $native"
Write-Host "default image: $defaultImage"
Write-Host "advanced image: $outputFullPath"
Write-Host "include ekey: $IncludeEkey"
Write-Host "include history: $IncludeHistory"

Write-Host ""
Write-Host "== Image layout =="
Write-Check -Name "advanced image directory" -Passed $outputParentOk -Detail $outputDirectory

Write-Check -Name "advanced image separate from default image" -Passed $separateFromDefault

Write-Check -Name "advanced loader source" -Passed $advancedLoaderExists -Detail "windows-interactive-advanced.fs"

$requiredSources = @("comp-i.fs", "startup.fs", "ekey.fs", "history.fs", "see.fs", "locate1.fs", "status-line.fs")
foreach ($source in $requiredSources) {
    Write-Check -Name "source:$source" -Passed (Test-Path $source)
}

Write-Host ""
Write-Host "== Native image origin =="
$defaultImageExists = Test-Path $defaultImage
$kernelImageExists = Test-Path $kernelImage
Write-Check -Name "default image exists" -Passed $defaultImageExists -Detail $defaultImage
Write-Check -Name "kernel cross image exists" -Passed $kernelImageExists -Detail $kernelImage
if ($defaultImageExists -and $kernelImageExists) {
    $defaultInfo = Get-Item $defaultImage
    $kernelInfo = Get-Item $kernelImage
    $sameSize = ($defaultInfo.Length -eq $kernelInfo.Length)
    Write-Check -Name "default image matches kernel image size" -Passed $sameSize -Detail "$($defaultInfo.Length) bytes"
}
Write-Host "note: build-native.ps1 produces build/native/gforth.fi from the cross-built kernl64l.fi compact image."
Write-Host "note: the advanced path must add or build a full startup/image-builder environment separately."

Write-Host ""
Write-Host "== Native compact image =="

$smoke = Invoke-Gforth -Exe $native -Arguments @("-e", "1 2 + . cr bye")
$nativeSmokeOk = ($smoke.ExitCode -eq 0 -and $smoke.Stdout -match "3")
Write-Check -Name "native smoke" -Passed $nativeSmokeOk -Detail $smoke.Stdout

$nativeHasSaveSystem = Test-Word -Exe $native -Word "savesystem"
Write-Check -Name "native word:savesystem" -Passed $nativeHasSaveSystem

$nativeHasCompImage = Test-Word -Exe $native -Word "comp-image"
Write-Check -Name "native word:comp-image" -Passed $nativeHasCompImage

Write-WordMatrix -Title "Native image-builder prerequisite" -Exe $native -Words $imageBuilderWords
Write-WordMatrix -Title "Native environment/search-order prerequisite" -Exe $native -Words $environmentWords
Write-ImageSurfaceMatrix -Title "Local existing" -Exe $native -Images $localImages -Words $advancedSurfaceWords
Write-CandidateMatrix -Title "Native builder prerequisite" -Exe $native -Candidates $nativeCandidates
Write-CandidateMatrix -Title "Native startup prefix" -Exe $native -Candidates $nativeStartupPrefixCandidates
Write-InvocationCandidateMatrix -Title "Native full-startup" -Exe $native -Candidates $nativeInvocationCandidates

foreach ($file in @("windows-interactive-advanced.fs", "status-line.fs", "locate1.fs", "savesys.fs", "comp-i.fs", "ekey.fs", "history.fs", "see.fs")) {
    $require = Test-Require -Exe $native -File $file
    Write-RunCheck -Name "native require:$file" -Result $require -Passed ($require.ExitCode -eq 0)
}

Write-Host ""
Write-Host "== Bootstrap image builder =="

$bootstrapAvailable = Test-Path $BootstrapExe
Write-Check -Name "bootstrap executable" -Passed $bootstrapAvailable -Detail $BootstrapExe

$bootstrapCanRun = $false
$bootstrapHasSaveSystem = $false
$bootstrapCanLoadCompI = $false

if ($bootstrapAvailable) {
    $bootstrap = (Resolve-Path $BootstrapExe).Path
    $bootstrapVersion = Invoke-Gforth -Exe $bootstrap -Arguments @("--version")
    $bootstrapCanRun = ($bootstrapVersion.ExitCode -eq 0)
    Write-Check -Name "bootstrap smoke" -Passed $bootstrapCanRun -Detail $bootstrapVersion.Stdout

    if ($bootstrapCanRun) {
        $bootstrapHasSaveSystem = Test-Word -Exe $bootstrap -Word "savesystem"
        Write-Check -Name "bootstrap word:savesystem" -Passed $bootstrapHasSaveSystem

        Write-WordMatrix -Title "Bootstrap image-builder prerequisite" -Exe $bootstrap -Words $imageBuilderWords
        Write-WordMatrix -Title "Bootstrap environment/search-order prerequisite" -Exe $bootstrap -Words $environmentWords
        Write-CandidateMatrix -Title "Bootstrap builder prerequisite" -Exe $bootstrap -Candidates $bootstrapCandidates
        Write-InvocationCandidateMatrix -Title "Bootstrap cross intermediate" -Exe $bootstrap -Candidates $bootstrapCrossCandidates
        foreach ($candidate in $bootstrapCrossCandidates) {
            if (Test-Path $candidate.OutputImage) {
                $probeImage = (Resolve-Path $candidate.OutputImage).Path
                $probeInfo = Get-Item $probeImage
                Write-Check -Name "$($candidate.Name):output" -Passed $true -Detail "$probeImage ($($probeInfo.Length) bytes)"
            } else {
                Write-Check -Name "$($candidate.Name):output" -Passed $false -Detail $candidate.OutputImage
            }
        }

        $compI = Invoke-Gforth -Exe $bootstrap -Arguments @("comp-i.fs", "-e", "s`" comp-image`" find-name dup . cr bye")
        $bootstrapCanLoadCompI = ($compI.ExitCode -eq 0 -and $compI.Stdout -ne "0")
        Write-Check -Name "bootstrap load:comp-i.fs" -Passed $bootstrapCanLoadCompI
        if (-not $bootstrapCanLoadCompI -and $compI.Stderr) {
            Write-Host "  $($compI.Stderr)"
        }
    }
}

Write-Host ""
Write-Host "Advanced interactive image probe complete."
Write-Host "Next required work:"
Write-Host "- make the native gforthmi-like path produce $OutputImage in normal build mode"
Write-Host "- verify the resulting image word surface before restoring ekey.fs/history.fs"
Write-Host "- keep build/native/gforth.fi on the current simple saccept path until then"
exit 0
}

if (-not $outputParentOk -or -not $separateFromDefault -or -not $advancedLoaderExists) {
    Write-Host "Refusing to build the advanced image until the image layout is valid."
    exit 2
}

Write-Host "Building advanced interactive image"

$buildNoOffsetImage = Join-Path $repoRoot "build/native/gforth-mi-build-no-offset.fi"
$buildOffsetImage = Join-Path $repoRoot "build/native/gforth-mi-build-offset.fi"
$outputImageForForth = Convert-ToGforthPath $outputFullPath
$savePrefix = ""
if ($IncludeHistory) {
    $savePrefix = "include kernel/accept.fs require ekey.fs require history.fs "
} elseif ($IncludeEkey) {
    $savePrefix = "include kernel/accept.fs require ekey.fs "
}
$buildRetryCount = 2
if ($IncludeEkey -or $IncludeHistory) {
    $buildRetryCount = 12
}

$noOffsetOk = Invoke-ImageBuildStep `
    -Name "build:no-offset-save" `
    -Exe $imageBuilder `
    -Arguments @("--clear-dictionary", "--no-offset-im", "--die-on-signal=2", "-p", ".;~+;.", "-i", $kernelImage, "exboot.fs", "startup.fs", "-e", "$($savePrefix)savesystem build/native/gforth-mi-build-no-offset.fi") `
    -OutputImage $buildNoOffsetImage `
    -RetryCount $buildRetryCount

if (-not $noOffsetOk) {
    Write-Host "Advanced interactive image build failed before the first temporary image."
    exit 2
}

$offsetOk = Invoke-ImageBuildStep `
    -Name "build:offset-save" `
    -Exe $imageBuilder `
    -Arguments @("--clear-dictionary", "--offset-image", "--die-on-signal=2", "-p", ".;~+;.", "-i", $kernelImage, "exboot.fs", "startup.fs", "-e", "$($savePrefix)savesystem build/native/gforth-mi-build-offset.fi") `
    -OutputImage $buildOffsetImage `
    -RetryCount $buildRetryCount

if ($offsetOk) {
    $advancedOk = Invoke-ImageBuildStep `
        -Name "build:comp-image" `
        -Exe $imageBuilder `
        -Arguments @("--die-on-signal=2", "-p", ".;~+;.", "-i", $kernelImage, "-e", "3", "exboot.fs", "startup.fs", "comp-i.fs", "-e", "comp-image build/native/gforth-mi-build-no-offset.fi build/native/gforth-mi-build-offset.fi $outputImageForForth bye") `
        -OutputImage $outputFullPath `
        -RetryCount $buildRetryCount `
        -RejectOutputPattern "images have the same base address"
    if ($advancedOk) {
        if (Test-ImageSmoke -Name "build:advanced-smoke" -Exe $native -Image $outputFullPath) {
            if (($IncludeEkey -or $IncludeHistory) -and -not (Test-ImageWord -Name "build:advanced-word:ekey" -Exe $native -Image $outputFullPath -Word "ekey")) {
                Write-Host "Advanced interactive image was written but does not expose ekey."
                exit 2
            }
            if ($IncludeHistory -and -not (Test-ImageWord -Name "build:advanced-word:history-cold" -Exe $native -Image $outputFullPath -Word "history-cold")) {
                Write-Host "Advanced interactive image was written but does not expose history-cold."
                exit 2
            }
            exit 0
        }
        Write-Host "Advanced interactive image was written but does not start cleanly."
        exit 2
    }
}

Write-Host "Advanced interactive image build failed; refusing to create a data-relocatable fallback."
exit 2
