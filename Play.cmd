@echo off
rem POLF 3D - starts the game with PowerShell 7. Scripts that came out of a downloaded ZIP file are marked as
rem "from the internet" by Windows and PowerShell may refuse to run them; -ExecutionPolicy Bypass lifts that for this
rem one process and changes nothing on the machine. Arguments are passed on:  Play.cmd -Terminal   Play.cmd -Horde
where pwsh >nul 2>nul
if errorlevel 1 (
    echo POLF 3D needs PowerShell 7:  winget install Microsoft.PowerShell
    pause
    exit /b 1
)
pwsh -NoProfile -ExecutionPolicy Bypass -File "%~dp0Start-Polf3D.ps1" %*
if errorlevel 1 pause
