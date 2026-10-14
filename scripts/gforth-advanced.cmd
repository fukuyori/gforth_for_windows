@echo off
rem Launch Gforth Native in advanced interactive mode (status bar + history).
rem Installed alongside gforth.exe; mirrors scripts/run-advanced.ps1.
setlocal
set "GFORTH_WIN_STATUS=1"
if not defined GFORTHHIST set "GFORTHHIST=%~dp0.gforth-advanced-history"
if exist "%~dp0gforth-advanced.fi" (
    "%~dp0gforth.exe" -i "%~dp0gforth-advanced.fi" %*
) else (
    echo Gforth Native: gforth-advanced.fi was not found, starting in plain mode. 1>&2
    echo Run generate-advanced.ps1 in the installation folder to create it. 1>&2
    "%~dp0gforth.exe" %*
)
