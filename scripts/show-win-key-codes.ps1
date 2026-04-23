param(
    [string]$NativeExe = ".\build\native\gforth.exe",
    [int]$Count = 15
)

$ErrorActionPreference = "Stop"

Write-Host "Press keys in the gforth window. Suggested order: a, Up, Down, PageUp, PageDown."
Write-Host "The program exits after $Count key events."
Write-Host ""

$previousInteractive = [Environment]::GetEnvironmentVariable("GFORTH_WIN_INTERACTIVE", "Process")
[Environment]::SetEnvironmentVariable("GFORTH_WIN_INTERACTIVE", "1", "Process")

$reads = @()
for ($i = 1; $i -le $Count; $i++) {
    $reads += '." key: " key . cr'
}

$code = @"
cr
." gforth key-code probe is ready." cr
." Press keys now.  Each line prints one value returned by key." cr
$($reads -join "`n")
bye
"@
try {
    & $NativeExe -e $code
} finally {
    [Environment]::SetEnvironmentVariable("GFORTH_WIN_INTERACTIVE", $previousInteractive, "Process")
}
