# kernel-inputs.ps1
# Helpers to tell whether kernl64l.fi still matches the sources it was built
# from.  regen-bootstrap.ps1 records a SHA256 per input file next to the image
# (kernl64l.fi.inputs); the image builders compare against it.  Content hashes
# are used instead of timestamps because build-native.ps1 rewrites generated
# files (kernel/version.fs, ...) on every run.

function Get-KernelInputFiles {
    param([string]$Root)

    $names = [System.Collections.Generic.List[string]]::new()
    foreach ($f in Get-ChildItem -LiteralPath (Join-Path $Root "kernel") -Filter "*.fs" -File) {
        $names.Add("kernel/" + $f.Name)
    }
    foreach ($n in @("prim", "cross.fs", "machpc.fs", "mach64l.fs")) {
        if (Test-Path -LiteralPath (Join-Path $Root $n)) {
            $names.Add($n)
        }
    }
    $sorted = $names.ToArray()
    [System.Array]::Sort($sorted, [System.StringComparer]::Ordinal)
    return $sorted
}

function Get-KernelInputHashes {
    param([string]$Root)

    $hashes = [ordered]@{}
    foreach ($name in Get-KernelInputFiles -Root $Root) {
        $hashes[$name] = (Get-FileHash -LiteralPath (Join-Path $Root $name) -Algorithm SHA256).Hash
    }
    return $hashes
}

function Write-KernelInputsStamp {
    param(
        [string]$Root,
        [string]$StampPath
    )

    $lines = foreach ($entry in (Get-KernelInputHashes -Root $Root).GetEnumerator()) {
        "$($entry.Value)  $($entry.Key)"
    }
    Set-Content -LiteralPath $StampPath -Value $lines
}

# Returns @{ Status = "ok" | "missing" | "stale"; Changed = <names> }
function Test-KernelInputsStamp {
    param(
        [string]$Root,
        [string]$StampPath
    )

    if (-not (Test-Path -LiteralPath $StampPath)) {
        return @{ Status = "missing"; Changed = @() }
    }

    $recorded = @{}
    foreach ($line in Get-Content -LiteralPath $StampPath) {
        if ($line -match '^([0-9A-Fa-f]{64})\s+(.+)$') {
            $recorded[$Matches[2]] = $Matches[1].ToUpperInvariant()
        }
    }

    $current = Get-KernelInputHashes -Root $Root
    $changed = [System.Collections.Generic.List[string]]::new()
    foreach ($entry in $current.GetEnumerator()) {
        if (-not $recorded.ContainsKey($entry.Key) -or $recorded[$entry.Key] -ne $entry.Value) {
            $changed.Add($entry.Key)
        }
    }
    foreach ($name in $recorded.Keys) {
        if (-not $current.Contains($name)) {
            $changed.Add("$name (removed)")
        }
    }

    if ($changed.Count -eq 0) {
        return @{ Status = "ok"; Changed = @() }
    }
    return @{ Status = "stale"; Changed = $changed.ToArray() }
}
