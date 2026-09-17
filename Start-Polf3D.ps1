# POLF 3D - Copyright (c) 2026 oNdsen. Licensed under the MIT License, see LICENSE.

#requires -Version 7.2

<#
.SYNOPSIS
    POLF 3D - a ray casting shooter written in PowerShell.
.DESCRIPTION
    A from-scratch rewrite of the ideas behind the classic 1992 tile-based shooter: own code,
    own level, procedurally generated graphics and sounds. Everything is PowerShell except
    the two innermost pixel loops (src/Scaler.cs, about 50 lines of C#).
.PARAMETER Scale
    Window size as a multiple of the internal 320x240 resolution (2..5).
.PARAMETER Columns
    Number of rays per frame: 320 (sharp) or 160 (faster, every wall strip two pixels wide).
.PARAMETER Difficulty
    Preselected difficulty 1..4 (can still be changed on the title screen).
.PARAMETER Map
    Play just this one level file instead of the campaign (maps/level1.map, level2.map, ...).
.PARAMETER Level
    Start the campaign on this floor.
.PARAMETER NoSound
    Skip sound synthesis (faster start, silent game).
.PARAMETER GodMode
    Cheat: no damage (toggle in game with F8).
.PARAMETER InfiniteAmmo
    Cheat: shooting costs nothing (F7).
.PARAMETER OneHitKill
    Cheat: every hit kills - the enemies AND you (F11).
.PARAMETER AllWeapons
    Cheat: start with every weapon, full ammunition and both keys (F6).
.PARAMETER SelfTest
    No window: simulate and render a number of frames, write PNGs to ./selftest and print timings.
.EXAMPLE
    ./Start-Polf3D.ps1 -Scale 4
#>
[CmdletBinding()]
param(
    [ValidateRange(2, 5)][int]$Scale = 3,
    [ValidateSet(320, 160)][int]$Columns = 320,
    [ValidateRange(1, 4)][int]$Difficulty = 2,
    [string]$Map,
    [ValidateRange(1, 99)][int]$Level = 1,
    [switch]$NoSound,
    [switch]$GodMode,
    [switch]$InfiniteAmmo,
    [switch]$OneHitKill,
    [switch]$AllWeapons,
    [switch]$SelfTest,
    [Parameter(DontShow)][string]$Screenshots,           # maintenance: stage and save the README pictures into this folder
    [Parameter(DontShow)][int]$AutoQuitSeconds = 0      # test aid: play by script in the real window, then quit
)

Set-StrictMode -Off
$ErrorActionPreference = 'Stop'
if (-not $IsWindows) { throw 'POLF 3D needs Windows (Windows Forms / GDI+).' }

Add-Type -AssemblyName System.Windows.Forms, System.Drawing

$script:Clock = [System.Diagnostics.Stopwatch]::StartNew()
$script:SaveDir = Join-Path $PSScriptRoot 'saves'
$script:MapFiles = @(if ($Map) { (Resolve-Path -LiteralPath $Map).Path }
    else { Get-ChildItem (Join-Path $PSScriptRoot 'maps') -Filter 'level*.map' | Sort-Object { [int]($_.BaseName -replace '\D') } | ForEach-Object FullName })
if (-not $script:MapFiles) { throw 'No maps found (maps/level*.map).' }
$script:StartLevelIndex = [Math]::Min($Level, $script:MapFiles.Count) - 1
$script:LevelIndex = $script:StartLevelIndex
$script:MapFile = $script:MapFiles[$script:LevelIndex]
$script:Difficulty = $Difficulty - 1
$script:GodMode = [bool]$GodMode
$script:InfiniteAmmo = [bool]$InfiniteAmmo
$script:OneHitKill = [bool]$OneHitKill
$script:CheatAllWeapons = [bool]$AllWeapons
$script:AutoQuit = $AutoQuitSeconds
$script:SfxEnabled = -not $NoSound -and -not $SelfTest

function Write-Step([string]$Text) { Write-Host ('[{0,6:0.0}s] {1}' -f $script:Clock.Elapsed.TotalSeconds, $Text) -ForegroundColor DarkCyan }

# ---- the only C#: the pixel scalers. Compiled once and cached as a DLL next to the script. -------
function Initialize-Scaler {
    if ('PolfScaler' -as [type]) { return }
    $source = Join-Path $PSScriptRoot 'src/Scaler.cs'
    $binDir = Join-Path $PSScriptRoot 'bin'
    $dll = Join-Path $binDir 'PolfScaler.dll'
    try {
        if (-not (Test-Path $dll) -or (Get-Item $dll).LastWriteTimeUtc -lt (Get-Item $source).LastWriteTimeUtc) {
            $null = New-Item -ItemType Directory -Path $binDir -Force
            Add-Type -Path $source -OutputAssembly $dll -OutputType Library
        }
        Add-Type -Path $dll
    }
    catch {
        Write-Verbose "DLL cache not usable ($($_.Exception.Message)), compiling in memory."
        Add-Type -Path $source
    }
}

Write-Step 'POLF 3D starting ...'
foreach ($file in 'Defs', 'Assets.Gfx', 'Assets.Sfx', 'Map', 'Doors', 'Actors', 'Player', 'Render', 'SaveGame', 'Game', 'SelfTest') {
    . (Join-Path $PSScriptRoot "src/$file.ps1")
}
$script:SfxEnabled = -not $NoSound -and -not $SelfTest -and -not $Screenshots

Write-Step 'compiling scaler (C#) ...';       Initialize-Scaler
Write-Step 'building state tables ...';        Initialize-States
Write-Step 'painting wall textures ...';       Initialize-WallTextures
Write-Step 'painting sprites ...';             Initialize-Sprites
Write-Step 'synthesising sounds ...';          Initialize-Sounds
Initialize-Renderer $Scale ([int](320 / $Columns))

if ($Screenshots) {
    Export-Screenshots $Screenshots
    return
}
if ($SelfTest) {
    Invoke-SelfTest (Join-Path $PSScriptRoot 'selftest')
    return
}

Write-Step 'ready.'
try {
    New-GameWindow
    Start-GameLoop
}
finally {
    if ($script:Form -and -not $script:Form.IsDisposed) { $script:Form.Close(); $script:Form.Dispose() }
    [System.Windows.Forms.Cursor]::Show()
}
