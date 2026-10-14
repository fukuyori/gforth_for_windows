# release-preflight.ps1
# Checks that the artifacts in build/native are current before they are
# staged.  build-release.ps1 -SkipNative reuses build/native as it is, so a
# stale engine or kernel image would otherwise go into the release unnoticed.
#
# Checks:
#   1. version-string of gforth.exe equals the version in configure.ac
#   2. the engines (gforth.exe, gforth-ditc.exe) are newer than their sources
#      (engine/*.c|h|i, compat/win32)
#   3. kernl64l.fi was generated from the current kernel sources
#      (kernl64l.fi.inputs, written by regen-bootstrap.ps1)
#   4. build/native/gforth.fi is the same file as kernl64l.fi
# On a failure the build stops; -AllowStale turns the failures into warnings.

. (Join-Path $PSScriptRoot "kernel-inputs.ps1")

function Get-ConfiguredVersion {
    param([string]$Root)

    $line = Select-String -Path (Join-Path $Root "configure.ac") -Pattern "AC_INIT\(\[gforth\],\[([^\]]+)\]" | Select-Object -First 1
    if (-not $line) {
        throw "Could not determine the version from configure.ac"
    }
    return $line.Matches[0].Groups[1].Value
}

function Test-NativeBuildFresh {
    param(
        [string]$Root,
        [switch]$AllowStale
    )

    $problems = [System.Collections.Generic.List[string]]::new()
    $native = Join-Path $Root "build/native"
    $exe = Join-Path $native "gforth.exe"
    $ditc = Join-Path $native "gforth-ditc.exe"
    $defaultImage = Join-Path $native "gforth.fi"
    $kernelImage = Join-Path $Root "kernl64l.fi"
    $fix = "Run scripts/regen-bootstrap.ps1 (kernel or prim changed), or scripts/build-native.ps1 -SkipBootstrap (engine only)."

    # 1. version
    $expected = Get-ConfiguredVersion -Root $Root
    $actual = (& $exe -e "version-string type bye" 2>&1 | Out-String).Trim()
    if ($actual -ne $expected) {
        $problems.Add("gforth.exe reports version '$actual' but configure.ac says '$expected'.")
    }

    # 2. engines vs. sources (config.h is rewritten by every build-native run
    #    and its content is covered by the version check)
    $sources = [System.Collections.Generic.List[System.IO.FileInfo]]::new()
    foreach ($pattern in @("engine/*.c", "engine/*.h", "engine/*.i")) {
        foreach ($f in Get-ChildItem -Path (Join-Path $Root $pattern) -File -ErrorAction SilentlyContinue) {
            if ($f.Name -ne "config.h") { $sources.Add($f) }
        }
    }
    foreach ($f in Get-ChildItem -Path (Join-Path $Root "compat/win32") -Recurse -File -ErrorAction SilentlyContinue) {
        $sources.Add($f)
    }
    $engineTime = @((Get-Item $exe).LastWriteTimeUtc, (Get-Item $ditc).LastWriteTimeUtc) | Sort-Object | Select-Object -First 1
    $newer = @($sources | Where-Object { $_.LastWriteTimeUtc -gt $engineTime } | Sort-Object LastWriteTimeUtc -Descending)
    if ($newer.Count -gt 0) {
        $names = ($newer | Select-Object -First 5 | ForEach-Object { $_.FullName.Substring($Root.Length).TrimStart('\', '/') }) -join ", "
        $problems.Add("The engine is older than its sources ($($newer.Count) newer: $names).")
    }

    # 3. kernel image vs. its inputs
    if (-not (Test-Path -LiteralPath $kernelImage)) {
        $problems.Add("kernl64l.fi is missing.")
    } else {
        $stamp = Test-KernelInputsStamp -Root $Root -StampPath "$kernelImage.inputs"
        if ($stamp.Status -eq "missing") {
            $problems.Add("There is no record of what kernl64l.fi was built from (kernl64l.fi.inputs).")
        } elseif ($stamp.Status -eq "stale") {
            $problems.Add("kernl64l.fi is older than its sources; changed: " + (($stamp.Changed | Select-Object -First 8) -join ", ") + ".")
        }

        # 4. default image vs. kernel image
        if ((Get-FileHash -LiteralPath $defaultImage -Algorithm SHA256).Hash -ne (Get-FileHash -LiteralPath $kernelImage -Algorithm SHA256).Hash) {
            $problems.Add("build/native/gforth.fi differs from kernl64l.fi.")
        }
    }

    if ($problems.Count -eq 0) {
        Write-Host "Preflight: build/native is current (version $expected)." -ForegroundColor Gray
        return
    }

    foreach ($p in $problems) {
        if ($AllowStale) {
            Write-Warning $p
        } else {
            Write-Host "Preflight failed: $p" -ForegroundColor Red
        }
    }
    if ($AllowStale) {
        Write-Warning "Continuing because -AllowStale was given."
        return
    }
    Write-Host $fix -ForegroundColor Yellow
    throw "build/native is not current; refusing to stage a release from it (-AllowStale overrides)."
}
