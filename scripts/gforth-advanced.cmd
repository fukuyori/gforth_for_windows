@echo off
rem Launch Gforth Native in advanced interactive mode (status bar + history).
rem Installed alongside gforth.exe; mirrors scripts/run-advanced.ps1.
setlocal
set "GFORTH_WIN_STATUS=1"
if not defined GFORTHHIST set "GFORTHHIST=%~dp0.gforth-advanced-history"
if exist "%~dp0gforth-advanced.fi" (
    "%~dp0gforth.exe" -i "%~dp0gforth-advanced.fi" %*
) else (
    "%~dp0gforth.exe" %*
)
