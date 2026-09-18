# POLF 3D - Copyright (c) 2026 oNdsen. Licensed under the MIT License, see LICENSE.

#requires -Version 7.2

<#
.SYNOPSIS
    POLF 3D - a ray casting shooter written in PowerShell.
.DESCRIPTION
    A from-scratch rewrite of the ideas behind the classic 1992 tile-based shooter: own code,
    own level, procedurally generated graphics and sounds. Everything is PowerShell except
    the innermost pixel loops (src/Scaler.cs) and the XInput declaration (src/Gamepad.cs), about 150 lines of C#.
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
.PARAMETER Speedrun
    Show the speedrun clock (floor time, par, total run) and keep records in saves/speedrun.json.
.PARAMETER FlatFloors
    Plain coloured floor and ceiling instead of textures (the 1992 look, a little faster).
.PARAMETER HostGame
    Host a network game for a second player: Coop (the campaign, together) or Duel (one against one,
    no monsters). The game starts as soon as the other player has joined and the host presses Enter.
.PARAMETER JoinGame
    Join the network game hosted on this computer (name or IP address).
.PARAMETER Port
    TCP port of the network game (default 27500). The host's firewall must let it in.
.PARAMETER NoGamepad
    Do not look for an XInput game pad.
.PARAMETER NoSound
    Skip sound synthesis (faster start, no sound effects).
.PARAMETER NoMusic
    No background music (toggle in game with F4).
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
.EXAMPLE
    ./Start-Polf3D.ps1 -HostGame Coop          # ... and on the other computer:  ./Start-Polf3D.ps1 -JoinGame 192.168.1.20
#>
[CmdletBinding()]
param(
    [ValidateRange(2, 5)][int]$Scale = 3,
    [ValidateSet(320, 160)][int]$Columns = 320,
    [Alias('Difficulty')][ValidateRange(1, 4)][int]$StartDifficulty = 2,       # not named $Difficulty: the game's own
                                                                               # $script:Difficulty (0..3) would inherit the validation
    [string]$Map,
    [ValidateRange(1, 99)][int]$Level = 1,
    [ValidateSet('Coop', 'Duel')][string]$HostGame,
    [string]$JoinGame,
    [ValidateRange(1024, 65535)][int]$Port = 27500,
    [switch]$Speedrun,
    [switch]$FlatFloors,
    [switch]$NoGamepad,
    [switch]$NoSound,
    [switch]$NoMusic,
    [switch]$GodMode,
    [switch]$InfiniteAmmo,
    [switch]$OneHitKill,
    [switch]$AllWeapons,
    [switch]$SelfTest,
    [Parameter(DontShow)][string]$RecordAttractDemo,     # maintenance: let the bot play floor 1 and save the demo to this file
    [Parameter(DontShow)][int]$BalanceTest = 0,          # maintenance: let the bot play this floor on every difficulty and print how it fared (negative: only the boss duels)
    [Parameter(DontShow)][string]$Screenshots,           # maintenance: stage and save the README pictures into this folder
    [Parameter(DontShow)][int]$AutoQuitSeconds = 0      # test aid: play by script in the real window, then quit
)

Set-StrictMode -Off
$ErrorActionPreference = 'Stop'
if (-not $IsWindows) { throw 'POLF 3D needs Windows (Windows Forms / GDI+).' }

Add-Type -AssemblyName System.Windows.Forms, System.Drawing, PresentationCore

$script:Clock = [System.Diagnostics.Stopwatch]::StartNew()
$script:SaveDir = Join-Path $PSScriptRoot 'saves'
$script:MusicDir = Join-Path $PSScriptRoot 'bin/music'
$script:MapFiles = @(if ($Map) { (Resolve-Path -LiteralPath $Map).Path }
    else { Get-ChildItem (Join-Path $PSScriptRoot 'maps') -Filter 'level*.map' | Sort-Object { [int]($_.BaseName -replace '\D') } | ForEach-Object FullName })
if (-not $script:MapFiles) { throw 'No maps found (maps/level*.map).' }
$script:StartLevelIndex = [Math]::Min($Level, $script:MapFiles.Count) - 1
$script:LevelIndex = $script:StartLevelIndex
$script:MapFile = $script:MapFiles[$script:LevelIndex]
$script:Difficulty = $StartDifficulty - 1
$script:GodMode = [bool]$GodMode
$script:Speedrun = [bool]$Speedrun
$script:FlatFloors = [bool]$FlatFloors
$script:InfiniteAmmo = [bool]$InfiniteAmmo
$script:OneHitKill = [bool]$OneHitKill
$script:CheatAllWeapons = [bool]$AllWeapons
$script:AutoQuit = $AutoQuitSeconds
$script:SfxEnabled = -not $NoSound -and -not $SelfTest

function Write-Step([string]$Text) { Write-Host ('[{0,6:0.0}s] {1}' -f $script:Clock.Elapsed.TotalSeconds, $Text) -ForegroundColor DarkCyan }

# ---- the only C#: the pixel scalers. Compiled once and cached as a DLL next to the script. -------
# Compiles one of the two C# files and returns its class. The class name carries a hash of its
# source: a PowerShell session can never unload a type, so without this an older version from an
# earlier run in the same session would shadow the new one. Compiled DLLs are cached in bin/.
function Import-CSharpClass([string]$File, [string]$ClassName) {
    $source = Get-Content -LiteralPath (Join-Path $PSScriptRoot $File) -Raw
    $hash = [BitConverter]::ToString([System.Security.Cryptography.SHA1]::HashData([Text.Encoding]::UTF8.GetBytes($source))).Replace('-', '').Substring(0, 10)
    $name = "${ClassName}_$hash"
    if (-not ($name -as [type])) {
        $code = $source.Replace("class $ClassName", "class $name")
        $binDir = Join-Path $PSScriptRoot 'bin'
        $dll = Join-Path $binDir "$name.dll"
        try {
            if (-not (Test-Path $dll)) {
                $null = New-Item -ItemType Directory -Path $binDir -Force
                Get-ChildItem $binDir -Filter "$ClassName*.dll" -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
                Add-Type -TypeDefinition $code -OutputAssembly $dll -OutputType Library
            }
            Add-Type -Path $dll
        }
        catch {
            Write-Verbose "DLL cache not usable ($($_.Exception.Message)), compiling in memory."
            Add-Type -TypeDefinition $code
        }
    }
    $name -as [type]
}

function Initialize-Scaler {
    $script:Scaler = Import-CSharpClass 'src/Scaler.cs' 'PolfScaler'
    if (-not $script:Scaler) { throw 'The scaler (src/Scaler.cs) could not be compiled.' }
    # the game pad is optional: no pad, no XInput or no compiler -> keyboard and mouse only
    $script:Pad = if ($NoGamepad) { $null } else { try { Import-CSharpClass 'src/Gamepad.cs' 'PolfGamepad' } catch { $null } }
}

Write-Step 'POLF 3D starting ...'
foreach ($file in 'Defs', 'Assets.Gfx', 'Assets.Sfx', 'Map', 'Doors', 'Mechanics', 'Actors', 'Player', 'Render', 'Music', 'SaveGame', 'Demo', 'Network', 'Abilities', 'Game', 'SelfTest') {
    . (Join-Path $PSScriptRoot "src/$file.ps1")
}
$headless = $SelfTest -or $Screenshots -or $RecordAttractDemo -or $BalanceTest
$script:SfxEnabled = -not $NoSound -and -not $headless
$script:MusicEnabled = -not $NoMusic -and -not $headless
$script:AttractDemo = Join-Path $PSScriptRoot 'demos/attract.json'

Write-Step 'compiling scaler (C#) ...';       Initialize-Scaler
Write-Step 'building state tables ...';        Initialize-States
Write-Step 'painting wall textures ...';       Initialize-WallTextures; Initialize-Flats
Write-Step 'painting sprites ...';             Initialize-Sprites
Write-Step 'synthesising sounds ...';          Initialize-Sounds
Initialize-Renderer $Scale ([int](320 / $Columns))

if ($RecordAttractDemo) {
    Export-AttractDemo $RecordAttractDemo
    return
}
if ($BalanceTest) {
    Invoke-BalanceTest $BalanceTest
    return
}
if ($Screenshots) {
    Export-Screenshots $Screenshots
    return
}
if ($SelfTest) {
    Invoke-SelfTest (Join-Path $PSScriptRoot 'selftest')
    return
}

if ($HostGame -and $JoinGame) { throw 'Either -HostGame or -JoinGame, not both.' }
Write-Step 'ready.'
try {
    if ($HostGame) { Initialize-Network 'host' $HostGame.ToLower() '' $Port; Write-Step "hosting a $HostGame game on port $Port" }
    elseif ($JoinGame) { Initialize-Network 'client' 'coop' $JoinGame $Port; Write-Step "joining the game on ${JoinGame}:$Port" }
    New-GameWindow
    Start-GameLoop
}
finally {
    Stop-Network
    Stop-Music
    if ($script:Form -and -not $script:Form.IsDisposed) { $script:Form.Close(); $script:Form.Dispose() }
    [System.Windows.Forms.Cursor]::Show()
}
