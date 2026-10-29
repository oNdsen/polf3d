@echo off
rem POLF 3D - starts the game with PowerShell 7. Scripts that came out of a downloaded ZIP file are marked as
rem "from the internet" by Windows and PowerShell may refuse to run them; -ExecutionPolicy Bypass lifts that for this
rem one process and changes nothing on the machine. Arguments are passed on:  Play.cmd -Terminal   Play.cmd -Horde
rem (a value with spaces in single quotes:  Play.cmd -PlayerName 'Big Boss').
rem The game runs without a console window: this file is done the moment it starts, and PowerShell runs under a
rem headless console host (Windows Terminal would give a hidden PowerShell a tab of its own).
rem Should the game not start, the reason comes up in a dialog - or, where the organisation allows PowerShell only
rem its constrained language and a dialog cannot be built, in Notepad. Terminal mode is the exception - it plays in
rem the console, so that one stays.
rem The game folder reaches PowerShell through the environment, not inside the command line: an apostrophe or an
rem ampersand in a folder name would break the command line.
where pwsh >nul 2>nul
if errorlevel 1 (
    echo POLF 3D needs PowerShell 7:  winget install Microsoft.PowerShell
    pause
    exit /b 1
)
set "POLF3D_ROOT=%~dp0"
echo %* | find /i "-Terminal" >nul
if not errorlevel 1 (
    pwsh -NoProfile -ExecutionPolicy Bypass -Command "& (Join-Path $env:POLF3D_ROOT 'Start-Polf3D.ps1') %*"
    exit /b
)
start "" conhost.exe --headless pwsh -NoProfile -ExecutionPolicy Bypass -Command "try { & (Join-Path $env:POLF3D_ROOT 'Start-Polf3D.ps1') %* } catch { $m = '' + $_ + [char]13 + [char]10 + [char]13 + [char]10 + 'If PowerShell said that running scripts is disabled on this system, an execution policy set by your organisation (Group Policy) forbids it, and Play.cmd cannot lift that.'; try { Add-Type -AssemblyName System.Windows.Forms; [void][System.Windows.Forms.MessageBox]::Show($m, 'POLF 3D did not start') } catch { $f = Join-Path $env:TEMP 'polf3d-did-not-start.txt'; Set-Content -LiteralPath $f -Value $m; Start-Process notepad.exe $f } }"
