param(
    [string]$Compiler = "C:\Program Files\LLVM\bin\clang.exe",
    [string]$Arch = "amd64",
    [string]$BootstrapExe,
    [string]$BootstrapImage,
    [string]$BootstrapPrimSpec,
    [string]$M4Exe,
    [switch]$SkipBootstrap,
    [switch]$SyntaxOnly,
    [switch]$CheckAdvancedInteractive,
    [switch]$ProbeAdvancedInteractive,
    [switch]$CheckWindowsInteractiveRelease
)

$ErrorActionPreference = "Stop"
$RepoRoot = (Get-Location).Path

function Convert-ToGforthPath {
    param([string]$Path)
    return $Path.Replace("\", "/")
}

function Convert-ToBootstrapArgumentPath {
    param([string]$Path)

    if (-not $Path) {
        return $null
    }

    $candidate = $Path
    try {
        $candidate = (Resolve-Path $Path).Path
    } catch {
    }

    if ([System.IO.Path]::IsPathRooted($candidate)) {
        try {
            $relative = [System.IO.Path]::GetRelativePath($RepoRoot, $candidate)
            if ($relative) {
                return Convert-ToGforthPath $relative
            }
        } catch {
        }
    }

    return Convert-ToGforthPath $candidate
}

function Set-ContentWithRetry {
    param(
        [string]$Path,
        [string]$Value,
        [switch]$NoNewline,
        [int]$RetryCount = 10
    )

    for ($attempt = 1; $attempt -le $RetryCount; $attempt++) {
        try {
            if ($NoNewline) {
                Set-Content -Path $Path -Value $Value -NoNewline
            } else {
                Set-Content -Path $Path -Value $Value
            }
            return
        } catch [System.IO.IOException] {
            if ($attempt -eq $RetryCount) {
                throw
            }
            Start-Sleep -Milliseconds (100 * $attempt)
        }
    }
}

function Get-PackageVersion {
    $line = Select-String -Path "configure.ac" -Pattern "AC_INIT\(\[gforth\],\[([^\]]+)\]" | Select-Object -First 1
    if (-not $line) {
        throw "Could not determine PACKAGE_VERSION from configure.ac"
    }
    return $line.Matches[0].Groups[1].Value
}

function Get-NativeTemplateValues {
    $packageVersion = Get-PackageVersion
    $includeRoot = Convert-ToGforthPath (Join-Path $RepoRoot "include")
    return @{
        PACKAGE_VERSION = $packageVersion
        PACKAGE_STRING = "gforth $packageVersion"
        GFORTH_VERSION = $packageVersion
        machine = $Arch
        host_os = "win32"
        LIB_SUFFIX = ".la"
        SO_SUFFIX = ".dll"
        GNU_LIBTOOL = "libtool"
        LIBTOOL_CC = (Convert-ToGforthPath $Compiler)
        LIBTOOL_CXX = "clang++"
        CFLAGS = ""
        CPPFLAGS = ""
        CXXFLAGS = ""
        LDFLAGS = ""
        PACKAGE_TARNAME = "gforth"
        incdir = $includeRoot
        FFCALLFLAG = "false"
        LIBFFIFLAG = "false"
        FFI_H_NAME = "ffi.h"
        GETENTROPY = "false"
        GETRANDOM = "false"
        GLESFLAG = "false"
        GLXFLAG = "false"
        MINOSFLAG = "false"
        EC_MODE = "false"
        PEEPHOLEFLAG = "true"
        ATOMIC = "true"
    }
}

function Expand-TemplateFile {
    param(
        [string]$TemplatePath,
        [string]$OutputPath,
        [hashtable]$Values
    )

    $content = Get-Content $TemplatePath -Raw
    foreach ($key in $Values.Keys) {
        $content = $content.Replace("@$key@", [string]$Values[$key])
    }
    Set-Content $OutputPath $content
}

function Write-NativeConfig {
    $template = Get-Content "compat/win32/native-config.h.in" -Raw
    $values = Get-NativeTemplateValues
    $content = $template.Replace("@PACKAGE_VERSION@", $values.PACKAGE_VERSION).Replace("@PACKAGE_STRING@", $values.PACKAGE_STRING)
    Set-Content "engine/config.h" $content
}

function Write-SupportGeneratedFiles {
    $values = Get-NativeTemplateValues
    Expand-TemplateFile -TemplatePath "machpc.fs.in" -OutputPath "machpc.fs" -Values $values
    $machpc = Get-Content "machpc.fs" -Raw
    $machpc = $machpc.Replace("false DefaultValue crlf", "true DefaultValue crlf")
    Set-Content "machpc.fs" $machpc
    Expand-TemplateFile -TemplatePath "envos.fs.in" -OutputPath "envos.fs" -Values $values
    Expand-TemplateFile -TemplatePath "kernel/version.fs.in" -OutputPath "kernel/version.fs" -Values $values

    $authorLines = @(
        '\ generated file; source file: AUTHORS',
        ': authors ( -- ) \ gforth',
        '  \G show the list of authors',
        '  cr'
    )

    foreach ($line in Get-Content "AUTHORS") {
        if ($line.StartsWith("N: ")) {
            $name = $line.Substring(3).Replace('"', '""')
            $authorLines += "  1 attr! ."" ${name}:"" 0 attr! cr "
        } elseif ($line.StartsWith("D: ")) {
            $desc = $line.Substring(3).Replace('"', '""')
            $authorLines += "  ."" $desc"" cr "
        }
    }
    $authorLines += ';'
    Set-Content "kernel/authors.fs" $authorLines
}

function Remove-M4Quotes {
    param([string]$Text)
    $trimmed = $Text.Trim()
    if ($trimmed.Length -ge 2 -and $trimmed[0] -eq [char]0x60 -and $trimmed[$trimmed.Length-1] -eq "'") {
        return $trimmed.Substring(1, $trimmed.Length - 2)
    }
    return $trimmed
}

function Expand-M4Template {
    param(
        [string]$Template,
        [string[]]$Arguments
    )

    $expanded = $Template
    for ($i = 0; $i -lt $Arguments.Count; $i++) {
        $expanded = $expanded.Replace("`$$($i + 1)", $Arguments[$i])
    }
    return $expanded
}

function Parse-M4Arguments {
    param([string]$InvocationText)

    $openParen = $InvocationText.IndexOf('(')
    $closeParen = $InvocationText.LastIndexOf(')')
    if ($openParen -lt 0 -or $closeParen -le $openParen) {
        throw "Could not parse macro arguments: $InvocationText"
    }

    $body = $InvocationText.Substring($openParen + 1, $closeParen - $openParen - 1)
    $parts = New-Object System.Collections.Generic.List[string]
    $current = New-Object System.Text.StringBuilder
    $depth = 0
    $inQuote = $false

    foreach ($ch in $body.ToCharArray()) {
        if ($ch -eq [char]0x60 -and -not $inQuote) {
            $inQuote = $true
            [void]$current.Append($ch)
            continue
        }
        if ($ch -eq "'" -and $inQuote) {
            $inQuote = $false
            [void]$current.Append($ch)
            continue
        }
        if (-not $inQuote) {
            if ($ch -eq '(') {
                $depth++
            } elseif ($ch -eq ')') {
                $depth--
            } elseif ($ch -eq ',' -and $depth -eq 0) {
                $parts.Add((Remove-M4Quotes $current.ToString()))
                $current.Clear() | Out-Null
                continue
            }
        }
        [void]$current.Append($ch)
    }

    $parts.Add((Remove-M4Quotes $current.ToString()))
    return ,$parts.ToArray()
}

function Get-MacroInvocation {
    param(
        [string[]]$Lines,
        [int]$StartIndex
    )

    $builder = New-Object System.Text.StringBuilder
    $depth = 0
    $inQuote = $false

    for ($i = $StartIndex; $i -lt $Lines.Count; $i++) {
        if ($builder.Length -gt 0) {
            [void]$builder.Append("`n")
        }
        $line = $Lines[$i]
        [void]$builder.Append($line)

        foreach ($ch in $line.ToCharArray()) {
            if ($ch -eq [char]0x60 -and -not $inQuote) {
                $inQuote = $true
                continue
            }
            if ($ch -eq "'" -and $inQuote) {
                $inQuote = $false
                continue
            }
            if (-not $inQuote) {
                if ($ch -eq '(') {
                    $depth++
                } elseif ($ch -eq ')') {
                    $depth--
                }
            }
        }

        if ($depth -eq 0 -and $builder.ToString().Contains(')')) {
            return @{
                Text = $builder.ToString()
                EndIndex = $i
            }
        }
    }

    throw "Unterminated macro invocation starting at line $StartIndex"
}

function Expand-Forlocal {
    param([string[]]$Arguments)

    $upper = [int](Remove-M4Quotes $Arguments[0])
    $body = Remove-M4Quotes $Arguments[1]
    $chunks = New-Object System.Collections.Generic.List[string]
    for ($i = 0; $i -le $upper; $i++) {
        $expanded = $body.Replace("%i", [string]$i)
        $expanded = [regex]::Replace($expanded, '\bi\b', [string]$i)
        $expanded = $expanded.Replace("%", "")
        $chunks.Add($expanded)
    }
    return [string]::Join("`r`n`r`n", $chunks)
}

function Expand-MinimalPrimSource {
    $condbranchTemplate = @'
$1	( $7 #a_target $2 )	gforth-internal	$3
$4 $5 SET_IP((Xt *)a_target);
/* condbranch_opt=0 */
}
/* condbranch_opt=0 */
$6

\+glocals

$1-lp+!#	( $7 #a_target #nlocals $2 )	gforth-internal	$3_lp_plus_store_number
$4	$5	lp += nlocals;
ALIVE_DEBUGGING(lp[-1]);
SET_IP((Xt *)a_target);
/* condbranch_opt=0 */
}
/* condbranch_opt=0 */

\+
'@

    $comparisonsTemplate = @'
$1=	( $2 -- f )		$6	$3equals
f = FLAG($4==$5);
:
    [ char $1x char 0 = [IF]
	] IF false ELSE true THEN [
    [ELSE]
	] xor 0= [
    [THEN] ] ;

$1<>	( $2 -- f )		$7	$3not_equals
f = FLAG($4!=$5);
:
    [ char $1x char 0 = [IF]
	] IF true ELSE false THEN [
    [ELSE]
	] xor 0<> [
    [THEN] ] ;

$1<	( $2 -- f )		$8	$3less_than
f = FLAG($4<$5);
:
    [ char $1x char 0 = [IF]
	] MINI and 0<> [
    [ELSE] char $1x char u = [IF]
	]   2dup xor 0<  IF nip ELSE - THEN 0<  [
	[ELSE]
	    ] MINI xor >r MINI xor r> u< [
	[THEN]
    [THEN] ] ;

$1>	( $2 -- f )		$9	$3greater_than
f = FLAG($4>$5);
:
    [ char $1x char 0 = [IF] ] negate [ [ELSE] ] swap [ [THEN] ]
    $1< ;

$1<=	( $2 -- f )		gforth	$3less_or_equal
f = FLAG($4<=$5);
:
    $1> 0= ;

$1>=	( $2 -- f )		gforth	$3greater_or_equal
f = FLAG($4>=$5);
:
    [ char $1x char 0 = [IF] ] negate [ [ELSE] ] swap [ [THEN] ]
    $1<= ;
'@

    $dcomparisonsTemplate = @'
$1=	( $2 -- f )		$6	$3equals
#ifdef BUGGY_LL_CMP
f = FLAG($4.lo==$5.lo && $4.hi==$5.hi);
#else
f = FLAG($4==$5);
#endif

$1<>	( $2 -- f )		$7	$3not_equals
#ifdef BUGGY_LL_CMP
f = FLAG($4.lo!=$5.lo || $4.hi!=$5.hi);
#else
f = FLAG($4!=$5);
#endif

$1<	( $2 -- f )		$8	$3less_than
#ifdef BUGGY_LL_CMP
f = FLAG($4.hi==$5.hi ? $4.lo<$5.lo : $4.hi<$5.hi);
#else
f = FLAG($4<$5);
#endif

$1>	( $2 -- f )		$9	$3greater_than
#ifdef BUGGY_LL_CMP
f = FLAG($4.hi==$5.hi ? $4.lo>$5.lo : $4.hi>$5.hi);
#else
f = FLAG($4>$5);
#endif

$1<=	( $2 -- f )		gforth	$3less_or_equal
#ifdef BUGGY_LL_CMP
f = FLAG($4.hi==$5.hi ? $4.lo<=$5.lo : $4.hi<=$5.hi);
#else
f = FLAG($4<=$5);
#endif

$1>=	( $2 -- f )		gforth	$3greater_or_equal
#ifdef BUGGY_LL_CMP
f = FLAG($4.hi==$5.hi ? $4.lo>=$5.lo : $4.hi>=$5.hi);
#else
f = FLAG($4>=$5);
#endif
'@

    $lines = Get-Content "prim"
    $cache0 = Get-Content "cache0.vmg" -Raw
    $output = New-Object System.Collections.Generic.List[string]

    for ($index = 0; $index -lt $lines.Count; $index++) {
        $line = $lines[$index]
        $trimmed = $line.Trim()

        if ($trimmed -like 'ifdef(*' -and $trimmed -like '*cache0.vmg*') {
            $output.Add($cache0.TrimEnd())
            continue
        }
        if ($trimmed -match '^undefine\(') {
            continue
        }
        if ($trimmed.StartsWith("divert(") -and $trimmed -like '*-1*') {
            while ($index -lt $lines.Count -and $lines[$index].Trim() -notlike 'divert*dnl') {
                $index++
            }
            continue
        }
        if ($trimmed.StartsWith("define(forlocal,")) {
            while ($index -lt $lines.Count -and $lines[$index].Trim() -notlike "*')')") {
                $index++
            }
            continue
        }
        if ($trimmed -eq "define(condbranch," -or $trimmed -eq "define(comparisons," -or $trimmed -eq "define(dcomparisons,") {
            $definition = Get-MacroInvocation -Lines $lines -StartIndex $index
            $index = $definition.EndIndex
            continue
        }
        if ($trimmed -like 'ifdef(*' -and $trimmed -like '*STACK_CACHE_FILE*' -and $index + 1 -lt $lines.Count -and $lines[$index + 1].Trim() -like '*peeprules.vmg*') {
            $index++
            continue
        }
        if ($trimmed.StartsWith("condbranch(") -or $trimmed.StartsWith("comparisons(") -or $trimmed.StartsWith("dcomparisons(") -or $trimmed.StartsWith("forlocal(")) {
            $invocation = Get-MacroInvocation -Lines $lines -StartIndex $index
            $args = Parse-M4Arguments $invocation.Text
            if ($trimmed.StartsWith("condbranch(")) {
                while ($args.Count -lt 7) {
                    $args += ""
                }
                $output.Add((Expand-M4Template -Template $condbranchTemplate -Arguments $args) + "`r`n")
            } elseif ($trimmed.StartsWith("comparisons(")) {
                $output.Add((Expand-M4Template -Template $comparisonsTemplate -Arguments $args) + "`r`n")
            } elseif ($trimmed.StartsWith("dcomparisons(")) {
                $output.Add((Expand-M4Template -Template $dcomparisonsTemplate -Arguments $args) + "`r`n")
            } else {
                $output.Add((Expand-Forlocal -Arguments $args) + "`r`n")
            }
            $index = $invocation.EndIndex
            continue
        }

        $output.Add($line)
    }

    $content = ($output -join "`r`n") + "`r`n"
    $quotePattern = [regex]::Escape([string][char]0x60) + "([^']*)'"
    return [regex]::Replace($content, $quotePattern, '$1')
}

function Write-MinimalPrimSpec {
    $content = Expand-MinimalPrimSource
    Set-Content "prim.b" $content
}

function Resolve-ToolPath {
    param([string]$ExplicitPath, [string]$CommandName)

    if ($ExplicitPath) {
        return $ExplicitPath
    }

    $cmd = Get-Command $CommandName -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($cmd) {
        return $cmd.Source
    }

    return $null
}

function Get-LocalBootstrapExe {
    $localExe = Join-Path $RepoRoot "build/native/gforth.exe"
    if (Test-Path $localExe) {
        return $localExe
    }
    return $null
}

function Get-LocalBootstrapImage {
    $localImage = Join-Path $RepoRoot "build/native/gforth.fi"
    if (Test-Path $localImage) {
        return $localImage
    }
    return $null
}

function Test-ExistingPath {
    param([string]$Path)

    if (-not $Path) {
        return $false
    }

    try {
        return Test-Path $Path
    } catch {
        return $false
    }
}

function Get-InstalledBootstrapExe {
    $candidates = @(
        (Join-Path ${env:ProgramFiles(x86)} "gforth\gforth.exe"),
        (Join-Path ${env:ProgramFiles} "gforth\gforth.exe"),
        (Join-Path ${env:LOCALAPPDATA} "Programs\Gforth\gforth.exe")
    ) | Where-Object { $_ }

    foreach ($candidate in $candidates) {
        if (Test-ExistingPath $candidate) {
            return $candidate
        }
    }

    $resolved = Resolve-ToolPath -CommandName "gforth"
    if ($resolved) {
        return $resolved
    }

    return $null
}

function Get-BootstrapRoot {
    if (-not $script:ResolvedBootstrapExe) {
        return $null
    }
    return Split-Path -Parent $script:ResolvedBootstrapExe
}

function Invoke-CheckedProcess {
    param(
        [string]$Executable,
        [string[]]$Arguments,
        [string]$StdoutPath
    )

    if ($StdoutPath) {
        & $Executable @Arguments > $StdoutPath
    } else {
        & $Executable @Arguments
    }

    if ($LASTEXITCODE -ne 0) {
        throw "Command failed: $Executable $($Arguments -join ' ')"
    }
}

function Invoke-Bootstrap {
    param(
        [string[]]$Arguments,
        [string]$StdoutPath
    )

    if (-not $script:ResolvedBootstrapExe) {
        return $false
    }

    $gforthPath = ".;$(Convert-ToGforthPath $RepoRoot)"
    $allArgs = @("--die-on-signal", "-m64M", "-p", $gforthPath)
    if ($script:ResolvedBootstrapImage) {
        $allArgs += @("-i", $script:ResolvedBootstrapImage)
    }
    $allArgs += $Arguments
    Invoke-CheckedProcess -Executable $script:ResolvedBootstrapExe -Arguments $allArgs -StdoutPath $StdoutPath
    return $true
}

function Ensure-PrimSpec {
    $primSource = Get-Item "prim"
    $currentPrimSpec = if (Test-Path "prim.b") { Get-Item "prim.b" } else { $null }
    if (-not $script:ResolvedM4Exe -and -not $script:ResolvedBootstrapPrimSpec) {
        Write-MinimalPrimSpec
        return $true
    }
    if ($currentPrimSpec -and $currentPrimSpec.LastWriteTimeUtc -ge $primSource.LastWriteTimeUtc) {
        return $true
    }
    if ($script:ResolvedBootstrapPrimSpec -and (Test-Path $script:ResolvedBootstrapPrimSpec)) {
        Copy-Item $script:ResolvedBootstrapPrimSpec "prim.b"
        return $true
    }
    Invoke-CheckedProcess -Executable $script:ResolvedM4Exe -Arguments @("-Dcondbranch_opt=0", "prim") -StdoutPath "prim.b"
    return $true
}

function Generate-BootstrapArtifacts {
    $ready = Ensure-PrimSpec
    if (-not $ready -or -not $script:ResolvedBootstrapExe) {
        return
    }

    $primCommands = @(
        @{ Output = "engine/prim.i"; Forth = "c-flag on s`" prim.i`" save-mem out-filename 2! s`" prim.b`" ' output-c ' output-c-combined process-file bye" },
        @{ Output = "engine/prim_lab.i"; Forth = "c-flag on s`" prim.b`" ' output-label dup process-file bye" },
        @{ Output = "engine/prim_grp.i"; Forth = "c-flag on s`" prim.b`" ' noop dup process-file bye" },
        @{ Output = "engine/prim_names.i"; Forth = "c-flag on s`" prim.b`" ' output-forthname ' output-forthname-combined process-file bye" },
        @{ Output = "engine/prim_superend.i"; Forth = "c-flag on s`" prim.b`" ' output-superend dup process-file bye" },
        @{ Output = "engine/costs.i"; Forth = "c-flag on s`" prim.b`" ' output-costs-gforth-simple ' output-costs-gforth-combined process-file bye" },
        @{ Output = "engine/prim_num.i"; Forth = "c-flag on s`" prim.b`" ' output-c-prim-num ' noop process-file bye" },
        @{ Output = "engine/super2.i"; Forth = "c-flag on s`" prim.b`" ' output-super2-simple ' output-super2-combined process-file bye" }
    )

    foreach ($entry in $primCommands) {
        Invoke-Bootstrap -Arguments @("prims2x.fs", "-e", $entry.Forth) -StdoutPath $entry.Output | Out-Null
    }

    Copy-Item "kernel/aliases0.fs" "kernel/aliases.fs-"
    Invoke-Bootstrap -Arguments @("prims2x.fs", "-e", "forth-flag on s`" prim.b`" ' output-alias ' noop process-file bye") -StdoutPath "kernel/aliases.fs.generated" | Out-Null
    Get-Content "kernel/aliases.fs.generated" | Add-Content "kernel/aliases.fs-"
    Move-Item -Force "kernel/aliases.fs-" "kernel/aliases.fs"
    Remove-Item "kernel/aliases.fs.generated"

    Copy-Item "kernel/prim0.fs" "kernel/prim.fs-"
    Invoke-Bootstrap -Arguments @("prims2x.fs", "-e", "forth-flag on s`" prim.b`" ' output-forth ' output-forth-combined process-file bye") -StdoutPath "kernel/prim.fs.generated" | Out-Null
    Get-Content "kernel/prim.fs.generated" | Add-Content "kernel/prim.fs-"
    Move-Item -Force "kernel/prim.fs-" "kernel/prim.fs"
    Remove-Item "kernel/prim.fs.generated"
    $kernelPrimText = Get-Content "kernel/prim.fs" -Raw
    $kernelPrimText = $kernelPrimText.Replace('Create "newline e? crlf [IF] 2 c, $0D c, [ELSE] 1 c, [THEN] $0A c,', 'Create "newline 2 c, $0D c, $0A c,')
    Set-ContentWithRetry -Path "kernel/prim.fs" -Value $kernelPrimText -NoNewline

    if (Test-Path "prim.b") {
        $primText = Get-Content "prim.b" -Raw
        $primText = $primText.Replace("#ifdef HAS_FILE`r`nfflush(stdout);`r`nn = key((FILE*)wfileid);", "#ifdef HAS_FILE`r`nn = key((FILE*)wfileid);")
        $primText = $primText.Replace("#ifdef HAS_FILE`r`nfflush(stdout);`r`nf = key_query((FILE*)wfileid);", "#ifdef HAS_FILE`r`nf = key_query((FILE*)wfileid);")
        $primText = [regex]::Replace(
            $primText,
            "(winch\? \( -- a_addr \)\s+gforth-internal winch_query\s+)a_addr = &winch_addr;",
            '$1#ifdef SIGWINCH`r`na_addr = &winch_addr;`r`n#else`r`na_addr = NULL;`r`n#endif')
        Set-ContentWithRetry -Path "prim.b" -Value $primText -NoNewline
    }

    $binaryName = "$(Convert-ToGforthPath (Join-Path $RepoRoot 'build/native/gforth.exe'))"
    try {
        $bootstrapSearchPath = ".|./kernel|~+|."
        Invoke-Bootstrap -Arguments @(
            "-e", "fpath= $bootstrapSearchPath",
            "-e", 's" mach64l.fs" include kernel/main.fs',
            "-e", "save-cross kernl64l.fi- $binaryName bye"
        ) | Out-Null

        if (Test-Path "kernl64l.fi-") {
            Move-Item -Force "kernl64l.fi-" "kernl64l.fi"
            Copy-Item -Force "kernl64l.fi" (Join-Path $RepoRoot "build/native/gforth.fi")
        }
    } catch {
        Write-Warning "Bootstrap gforth generated the primitive tables, but could not cross-build kernl64l.fi: $($_.Exception.Message)"
    }
}

function Invoke-Compile {
    param(
        [string]$Source,
        [string]$Object,
        [string[]]$ExtraArgs = @()
    )

    $args = @(
        "-D_CRT_SECURE_NO_WARNINGS",
        "-D_CRT_NONSTDC_NO_DEPRECATE",
        "-D_WIN32_WINNT=0x0601",
        "-Icompat/win32/include",
        "-Iengine",
        "-Iarch/$Arch"
    )
    $args += $ExtraArgs

    if ($SyntaxOnly) {
        $args += @("-fsyntax-only", $Source)
    } else {
        $args += @("-c", $Source, "-o", $Object)
    }

    & $Compiler @args
    if ($LASTEXITCODE -ne 0) {
        throw "Compilation failed for $Source"
    }
}

function Invoke-Link {
    param(
        [string[]]$Objects,
        [string]$Output
    )

    & $Compiler @Objects "-o" $Output
    if ($LASTEXITCODE -ne 0) {
        throw "Link failed for $Output"
    }
}

function Invoke-OptionalPhase6Checks {
    $nativeExe = Join-Path $RepoRoot "build/native/gforth.exe"

    if (-not (Test-Path $nativeExe)) {
        Write-Warning "Skipping advanced interactive checks because $nativeExe does not exist."
        return
    }

    if ($CheckAdvancedInteractive) {
        $readinessScript = Join-Path $RepoRoot "scripts/check-advanced-interactive-readiness.ps1"
        if (Test-Path $readinessScript) {
            Write-Host ""
            Write-Host "Running advanced interactive readiness checks..."
            & $readinessScript -NativeExe $nativeExe
            if ($LASTEXITCODE -ne 0) {
                Write-Warning "Advanced interactive readiness checks exited with $LASTEXITCODE."
            }
        } else {
            Write-Warning "Advanced interactive readiness script is missing: $readinessScript"
        }
    }

    if ($ProbeAdvancedInteractive) {
        $probeScript = Join-Path $RepoRoot "scripts/build-advanced-interactive-image.ps1"
        if (Test-Path $probeScript) {
            Write-Host ""
            Write-Host "Probing advanced interactive image build readiness..."
            if ($script:ResolvedBootstrapExe) {
                & $probeScript -NativeExe $nativeExe -BootstrapExe $script:ResolvedBootstrapExe -ProbeOnly
            } else {
                & $probeScript -NativeExe $nativeExe -ProbeOnly
            }
            if ($LASTEXITCODE -ne 0) {
                Write-Warning "Advanced interactive image probe exited with $LASTEXITCODE."
            }
        } else {
            Write-Warning "Advanced interactive image probe script is missing: $probeScript"
        }
    }

    if ($CheckWindowsInteractiveRelease) {
        $releaseScript = Join-Path $RepoRoot "scripts/check-windows-interactive-release.ps1"
        if (Test-Path $releaseScript) {
            Write-Host ""
            Write-Host "Running Windows interactive release checks..."
            & $releaseScript -NativeExe $nativeExe
            if ($LASTEXITCODE -ne 0) {
                Write-Warning "Windows interactive release checks exited with $LASTEXITCODE."
            }
        } else {
            Write-Warning "Windows interactive release check script is missing: $releaseScript"
        }
    }
}

Write-NativeConfig
Write-SupportGeneratedFiles

$script:ResolvedBootstrapExe = if ($SkipBootstrap) {
    # Build only from pre-generated artifacts (engine/*.i, kernel/prim.fs,
    # kernel/aliases.fs, prim.b, kernl64l.fi), e.g. taken from an upstream
    # snapshot tarball.  Needed when no full-image bootstrap gforth is
    # available: the fork's installed gforth.fi is a kernel-only image, and
    # loading startup.fs on it replaces INCLUDED with the terminal-protocol
    # version from kernel/saccept.fs, which cannot read files.
    $null
} elseif ($BootstrapExe) {
    $BootstrapExe
} else {
    $installedBootstrapExe = Get-InstalledBootstrapExe
    if ($installedBootstrapExe) {
        $installedBootstrapExe
    } else {
        Get-LocalBootstrapExe
    }
}

$script:ResolvedBootstrapImage = if ($BootstrapImage) {
    Convert-ToBootstrapArgumentPath $BootstrapImage
} else {
    $null
}
$script:ResolvedBootstrapPrimSpec = $BootstrapPrimSpec
$script:ResolvedM4Exe = Resolve-ToolPath -ExplicitPath $M4Exe -CommandName "m4"

if (-not $script:ResolvedBootstrapImage) {
    $localBootstrapExe = Get-LocalBootstrapExe
    $localBootstrapImage = Get-LocalBootstrapImage
    if ($localBootstrapImage -and $script:ResolvedBootstrapExe -eq $localBootstrapExe) {
        $script:ResolvedBootstrapImage = Convert-ToBootstrapArgumentPath $localBootstrapImage
    }
}

if (-not $script:ResolvedBootstrapImage) {
    $bootstrapRoot = Get-BootstrapRoot
    if ($bootstrapRoot) {
        $defaultImage = Join-Path $bootstrapRoot "gforth.fi"
        if (Test-ExistingPath $defaultImage) {
            $script:ResolvedBootstrapImage = Convert-ToBootstrapArgumentPath $defaultImage
        }
    }
}

Generate-BootstrapArtifacts

$buildRoot = Join-Path "build" "native"
$objRoot = Join-Path $buildRoot "obj"
New-Item -ItemType Directory -Force -Path $objRoot | Out-Null

$sources = @(
    @{ Source = "compat/win32/src/win32_compat.c"; Object = (Join-Path $objRoot "win32_compat.o") },
    @{ Source = "engine/select.c"; Object = (Join-Path $objRoot "select.o") },
    @{ Source = "engine/strsignal.c"; Object = (Join-Path $objRoot "strsignal.o") },
    @{ Source = "engine/support.c"; Object = (Join-Path $objRoot "support.o") },
    @{ Source = "engine/io.c"; Object = (Join-Path $objRoot "io.o") },
    @{ Source = "engine/signals.c"; Object = (Join-Path $objRoot "signals.o") }
)

foreach ($entry in $sources) {
    Invoke-Compile -Source $entry.Source -Object $entry.Object
}

if ((Test-Path "engine/prim.i") -and (Test-Path "engine/prim_num.i") -and (Test-Path "engine/prim_names.i") -and (Test-Path "engine/prim_superend.i") -and (Test-Path "engine/costs.i") -and (Test-Path "engine/super2.i")) {
    $probeArgs = @(
        "-D_CRT_SECURE_NO_WARNINGS",
        "-D_CRT_NONSTDC_NO_DEPRECATE",
        "-D_WIN32_WINNT=0x0601",
        "-Icompat/win32/include",
        "-Iengine",
        "-Iarch/$Arch",
        "-DGFORTH_DEBUGGING",
        "-DENGINE=2",
        "-fsyntax-only",
        "engine/engine.c",
        "engine/main.c"
    )
    & $Compiler @probeArgs
    if ($LASTEXITCODE -ne 0) {
        throw "Compilation probe failed for engine.c/main.c"
    }

    if (-not $SyntaxOnly) {
        $coreSources = @(
            @{ Source = "engine/engine.c"; Object = (Join-Path $objRoot "engine-main.o"); ExtraArgs = @("-DGFORTH_DEBUGGING") },
            @{ Source = "engine/engine.c"; Object = (Join-Path $objRoot "engine.o"); ExtraArgs = @("-DGFORTH_DEBUGGING", "-DENGINE=2") },
            @{ Source = "engine/main.c"; Object = (Join-Path $objRoot "main.o"); ExtraArgs = @("-DGFORTH_DEBUGGING") },
            @{ Source = "engine/libmain.c"; Object = (Join-Path $objRoot "libmain.o") },
            @{ Source = "engine/fnmatch.c"; Object = (Join-Path $objRoot "fnmatch.o") },
            @{ Source = "engine/getopt.c"; Object = (Join-Path $objRoot "getopt.o"); ExtraArgs = @("-DATTRIBUTE_UNUSED=", "-include", "string.h") },
            @{ Source = "engine/getopt1.c"; Object = (Join-Path $objRoot "getopt1.o") },
            @{ Source = "engine/dblsub.c"; Object = (Join-Path $objRoot "dblsub.o") },
            @{ Source = "engine/exp10.c"; Object = (Join-Path $objRoot "exp10.o") },
            @{ Source = "engine/sincos.c"; Object = (Join-Path $objRoot "sincos.o") }
        )

        foreach ($entry in $coreSources) {
            Invoke-Compile -Source $entry.Source -Object $entry.Object -ExtraArgs $entry.ExtraArgs
        }

        $linkObjects = @(
            (Join-Path $objRoot "engine-main.o"),
            (Join-Path $objRoot "engine.o"),
            (Join-Path $objRoot "main.o"),
            (Join-Path $objRoot "libmain.o"),
            (Join-Path $objRoot "support.o"),
            (Join-Path $objRoot "io.o"),
            (Join-Path $objRoot "signals.o"),
            (Join-Path $objRoot "select.o"),
            (Join-Path $objRoot "strsignal.o"),
            (Join-Path $objRoot "win32_compat.o"),
            (Join-Path $objRoot "fnmatch.o"),
            (Join-Path $objRoot "getopt.o"),
            (Join-Path $objRoot "getopt1.o"),
            (Join-Path $objRoot "dblsub.o"),
            (Join-Path $objRoot "exp10.o"),
            (Join-Path $objRoot "sincos.o")
        )
        Invoke-Link -Objects $linkObjects -Output (Join-Path $buildRoot "gforth.exe")
    }
}

$generatedInputs = @(
    "machpc.fs",
    "envos.fs",
    "kernel/version.fs",
    "kernel/authors.fs",
    "prim.b",
    "engine/prim.i",
    "engine/prim_lab.i",
    "engine/prim_num.i",
    "engine/prim_grp.i",
    "engine/prim_names.i",
    "engine/prim_superend.i",
    "engine/costs.i",
    "engine/super2.i",
    "kernel/aliases.fs",
    "kernel/prim.fs",
    "kernl64l.fi"
)

$missing = $generatedInputs | Where-Object { -not (Test-Path $_) }
if ($missing.Count -gt 0) {
    Write-Host ""
    Write-Host "Native helper objects compiled, but the full executable still needs generated files:" -ForegroundColor Yellow
    $missing | ForEach-Object { Write-Host "  $_" -ForegroundColor Yellow }
    Write-Host ""
    if (-not $script:ResolvedBootstrapExe) {
        Write-Host "Pass -BootstrapExe <path-to-gforth.exe> to let this script generate Forth bootstrap artifacts." -ForegroundColor Yellow
    }
    if ((-not (Test-Path "prim.b")) -and (-not $script:ResolvedM4Exe)) {
        Write-Host "Pass -M4Exe <path-to-m4>, -BootstrapPrimSpec <path-to-prim.b>, or use a bootstrap install that already contains prim.b." -ForegroundColor Yellow
    }
    if ($script:ResolvedBootstrapExe -and -not $script:ResolvedBootstrapImage) {
        Write-Host "If your bootstrap gforth needs an explicit image, also pass -BootstrapImage <path-to-gforth.fi>." -ForegroundColor Yellow
    }
}

if (-not $SyntaxOnly -and ($CheckAdvancedInteractive -or $ProbeAdvancedInteractive -or $CheckWindowsInteractiveRelease)) {
    Invoke-OptionalPhase6Checks
}
