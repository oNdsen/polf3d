@echo off
rem POLF 3D - starts the game with PowerShell 7. Scripts that came out of a downloaded ZIP file are marked as
rem "from the internet" by Windows and PowerShell may refuse to run them; -ExecutionPolicy Bypass lifts that for this
rem one process and changes nothing on the machine. Arguments are passed on:  Play.cmd -Terminal   Play.cmd -Horde
rem (a value with spaces in single quotes:  Play.cmd -PlayerName 'Big Boss').
rem This file is done the moment the game runs: it must not be open while the game updates itself and replaces it.
rem Should the game not start, PowerShell keeps the window and the reason on the screen.
where pwsh >nul 2>nul
if errorlevel 1 (
    echo POLF 3D needs PowerShell 7:  winget install Microsoft.PowerShell
    pause
    exit /b 1
)
start "" /b pwsh -NoProfile -ExecutionPolicy Bypass -Command "try { & '%~dp0Start-Polf3D.ps1' %* } catch { $_; Write-Host ''; Write-Host 'If PowerShell said that running scripts is disabled on this system, an execution policy set by your organisation (Group Policy) forbids it, and Play.cmd cannot lift that.'; Read-Host 'Press Enter to close' }"
