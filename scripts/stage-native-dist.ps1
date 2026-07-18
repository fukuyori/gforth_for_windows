param(
    [string]$StageDir = "$(Join-Path (Get-Location) 'build/installer/stage')",
    [switch]$Clean
)

$ErrorActionPreference = "Stop"
$RepoRoot = (Get-Location).Path
$NativeDir = Join-Path $RepoRoot "build/native"

function Copy-StageFile {
    param(
        [string]$SourcePath,
        [string]$DestinationPath
    )

    $destinationDir = Split-Path -Path $DestinationPath -Parent
    if ($destinationDir) {
        New-Item -ItemType Directory -Force -Path $destinationDir | Out-Null
    }

    Copy-Item -LiteralPath $SourcePath -Destination $DestinationPath -Force
}

function Remove-ItemWithRetry {
    param(
        [string]$Path,
        [int]$RetryCount = 10
    )

    for ($attempt = 1; $attempt -le $RetryCount; $attempt++) {
        try {
            Remove-Item -LiteralPath $Path -Recurse -Force
            return
        } catch [System.IO.IOException] {
            if ($attempt -eq $RetryCount) {
                throw
            }
            Start-Sleep -Milliseconds (100 * $attempt)
        }
    }
}

function Copy-RootPattern {
    param(
        [string]$Pattern,
        [string]$Destination
    )

    Get-ChildItem -Path $RepoRoot -File -Filter $Pattern | ForEach-Object {
        Copy-StageFile -SourcePath $_.FullName -DestinationPath (Join-Path $Destination $_.Name)
    }
}

function Copy-RootFile {
    param(
        [string]$RelativePath,
        [string]$Destination = $StageDir
    )

    $sourcePath = Join-Path $RepoRoot $RelativePath
    if (Test-Path $sourcePath) {
        Copy-StageFile -SourcePath $sourcePath -DestinationPath (Join-Path $Destination (Split-Path -Leaf $RelativePath))
    }
}

function Copy-DirectoryTree {
    param(
        [string]$RelativePath,
        [string[]]$Patterns = @("*")
    )

    $sourceRoot = Join-Path $RepoRoot $RelativePath
    if (-not (Test-Path $sourceRoot)) {
        return
    }

    $destRoot = Join-Path $StageDir $RelativePath
    $copied = @{}

    foreach ($pattern in $Patterns) {
        Get-ChildItem -Path $sourceRoot -Recurse -File -Filter $pattern | ForEach-Object {
            if ($copied.ContainsKey($_.FullName)) {
                return
            }

            $copied[$_.FullName] = $true
            $relativeLeaf = $_.FullName.Substring($sourceRoot.Length).TrimStart('\')
            Copy-StageFile -SourcePath $_.FullName -DestinationPath (Join-Path $destRoot $relativeLeaf)
        }
    }
}

if (-not (Test-Path (Join-Path $NativeDir "gforth.exe"))) {
    throw "Missing build/native/gforth.exe. Run scripts/build-native.ps1 first."
}

if (-not (Test-Path (Join-Path $NativeDir "gforth.fi"))) {
    throw "Missing build/native/gforth.fi. Run scripts/build-native.ps1 first."
}

if (-not (Test-Path (Join-Path $NativeDir "gforth-ditc.exe"))) {
    throw "Missing build/native/gforth-ditc.exe. Run scripts/build-native.ps1 first."
}

if ($Clean -and (Test-Path $StageDir)) {
    Remove-ItemWithRetry -Path $StageDir
}

New-Item -ItemType Directory -Force -Path $StageDir | Out-Null

Copy-StageFile -SourcePath (Join-Path $NativeDir "gforth.exe") -DestinationPath (Join-Path $StageDir "gforth.exe")
Copy-StageFile -SourcePath (Join-Path $NativeDir "gforth-ditc.exe") -DestinationPath (Join-Path $StageDir "gforth-ditc.exe")
Copy-StageFile -SourcePath (Join-Path $NativeDir "gforth.fi") -DestinationPath (Join-Path $StageDir "gforth.fi")
Copy-StageFile -SourcePath (Join-Path $RepoRoot "scripts/generate-installed-advanced.ps1") -DestinationPath (Join-Path $StageDir "generate-advanced.ps1")
Copy-StageFile -SourcePath (Join-Path $RepoRoot "scripts/gforth-advanced.cmd") -DestinationPath (Join-Path $StageDir "gforth-advanced.cmd")

$advancedImage = Join-Path $NativeDir "gforth-advanced.fi"
if (Test-Path $advancedImage) {
    Copy-StageFile -SourcePath $advancedImage -DestinationPath (Join-Path $StageDir "gforth-advanced.fi")
}

$rootPatterns = @(
    "*.fs",
    "*.fb",
    "*.4th"
)

foreach ($pattern in $rootPatterns) {
    Copy-RootPattern -Pattern $pattern -Destination $StageDir
}

$rootFiles = @(
    "README",
    "README.md",
    "COPYING",
    "COPYING.DOC",
    "COPYING.LIB",
    "AUTHORS",
    "NEWS",
    "INSTALL.BINDIST",
    "help.txt",
    "gforth.ico"
)

foreach ($file in $rootFiles) {
    Copy-RootFile -RelativePath $file
}

Copy-DirectoryTree -RelativePath "compat"
Copy-DirectoryTree -RelativePath "kernel"
Copy-DirectoryTree -RelativePath "unix" -Patterns @("*.fs", "*.i")
Copy-DirectoryTree -RelativePath "wordlibs" -Patterns @("*.fs", "*.h", "*.pri", "README")

Write-Host "Staged native distribution at $StageDir" -ForegroundColor Green
