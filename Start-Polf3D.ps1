# POLF 3D - Copyright (c) 2026 oNdsen. Licensed under the MIT License, see LICENSE.

#requires -Version 7.2

<#
.SYNOPSIS
    POLF 3D - a ray casting shooter written in PowerShell.
.DESCRIPTION
    A from-scratch rewrite of the ideas behind the classic 1992 tile-based shooter: own code,
    own level, procedurally generated graphics and sounds. Everything is PowerShell except
    the innermost pixel loops and two P/Invoke declarations (src/Scaler.cs, Gamepad.cs, Terminal.cs), about 200 lines of C#.
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
    Host a network game for up to four players: Coop (the campaign, together) or Deathmatch (everybody against
    everybody, no monsters; Duel is the same thing). Guests join on the title screen, the host presses Enter to
    start - and F1 to see who is there, kick (K) or ban (B) somebody. Bans are kept in saves/banned.json.
.PARAMETER MaxPlayers
    Hosting: how many players may take part, the host included (2..4, default 4).
.PARAMETER PlayerName
    The name the other players see (letters, digits, blank, - and _; twelve characters at most).
.PARAMETER JoinGame
    Join the network game hosted on this computer (name or IP address).
.PARAMETER Port
    TCP port of the network game (default 27500). The host's firewall must let it in.
.PARAMETER Daily
    Go straight into today's dungeon: one generated floor, the same for everybody today, one life, recorded as a demo.
.PARAMETER Dungeon
    Play the dungeon generated from this number instead of today's.
.PARAMETER Tutorial
    Straight into the onboarding: a floor that explains every mechanism, one room at a time (N on the title screen).
.PARAMETER Horde
    Straight into the arena: one life, wave after wave. -HordeNumber picks the waves (default: today's number).
.PARAMETER VerifyDemo
    No window: play this demo file back and report whether it is genuine - for dungeon runs that includes the time.
.PARAMETER ExportGif
    No window: play this demo file back and save it as an animated GIF (-GifPath, default: next to the demo).
    -GifStart and -GifSeconds choose the part of the demo (default: the first 12 seconds), -GifScale 2 doubles the pixels.
.PARAMETER Terminal
    No window: draw the game into the terminal with half-block characters and 24 bit colours. Wants a terminal
    that understands ANSI sequences (Windows Terminal) - and the bigger its window, the finer the picture.
.PARAMETER TerminalKeys
    Terminal mode: take the key presses the terminal delivers instead of asking Windows which keys are down.
    Needed over SSH (where it is switched on automatically); fire is J then.
.PARAMETER NoGamepad
    Do not look for an XInput game pad.
.PARAMETER NoSound
    Skip sound synthesis (faster start, no sound effects).
.PARAMETER NoMods
    Ignore the mods in ./mods (every *.psd1 there is merged into the game's tables, see src/Mods.ps1).
.PARAMETER NoVoices
    The enemies beep instead of talking (they talk through Windows' speech synthesiser, if it has an English voice).
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
.PARAMETER Version
    Print the version and leave.
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
    [ValidateSet('Coop', 'Duel', 'Deathmatch')][string]$HostGame,
    [ValidateRange(2, 4)][int]$MaxPlayers = 4,
    [string]$PlayerName,
    [string]$JoinGame,
    [ValidateRange(1024, 65535)][int]$Port = 27500,
    [switch]$Daily,
    [ValidateRange(1, 99999999)][int]$Dungeon,
    [switch]$Tutorial,
    [switch]$Horde,
    [ValidateRange(1, 99999999)][int]$HordeNumber,
    [string]$VerifyDemo,
    [string]$ExportGif,
    [string]$GifPath,
    [ValidateRange(0, 3600)][double]$GifStart = 0,
    [ValidateRange(1, 120)][double]$GifSeconds = 12,
    [ValidateRange(1, 3)][int]$GifScale = 1,
    [switch]$Terminal,
    [switch]$TerminalKeys,
    [switch]$Speedrun,
    [switch]$FlatFloors,
    [switch]$NoGamepad,
    [switch]$NoSound,
    [switch]$NoMods,
    [switch]$NoVoices,
    [switch]$NoMusic,
    [switch]$GodMode,
    [switch]$InfiniteAmmo,
    [switch]$OneHitKill,
    [switch]$AllWeapons,
    [switch]$SelfTest,
    [switch]$Version,
    [Parameter(DontShow)][string]$RecordAttractDemo,     # maintenance: let the bot play floor 1 and save the demo to this file
    [Parameter(DontShow)][int]$BalanceTest = 0,          # maintenance: let the bot play this floor on every difficulty and print how it fared (negative: only the boss duels)
    [Parameter(DontShow)][string]$Screenshots,           # maintenance: stage and save the README pictures into this folder
    [Parameter(DontShow)][int]$AutoQuitSeconds = 0      # test aid: play by script in the real window, then quit
)

Set-StrictMode -Off
$script:PolfVersion = '1.1.1'          # the one place the version is written down: title screen, -Version and tools/New-Release.ps1 read it
if ($Version) { "POLF 3D $script:PolfVersion"; return }
$ErrorActionPreference = 'Stop'
if (-not $IsWindows) { throw 'POLF 3D needs Windows (Windows Forms / GDI+).' }

Add-Type -AssemblyName System.Windows.Forms, System.Drawing

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
                Write-Step "compiling $File (once - it is cached in bin/ until the source changes) ..."
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
    # sound: a software mixer on waveOut. No sound device, no compiler -> a silent game
    $script:Mixer = $null
    if ($script:SfxEnabled -or $script:MusicEnabled) {
        try { $script:Mixer = Import-CSharpClass 'src/Mixer.cs' 'PolfMixer'; if (-not $script:Mixer::Open()) { $script:Mixer = $null } } catch { $script:Mixer = $null }
        if (-not $script:Mixer) { Write-Warning 'No sound: the mixer could not open an audio device.'; $script:SfxEnabled = $false; $script:MusicEnabled = $false }
    }
}

Write-Step "POLF 3D $script:PolfVersion starting ..."
foreach ($file in 'Defs', 'Assets.Gfx', 'Assets.Sfx', 'Voices', 'Map', 'Doors', 'Mechanics', 'Actors', 'Player', 'Render', 'Music', 'Mods', 'SaveGame', 'Transcript', 'Achievements', 'Demo', 'GifExport', 'Dungeon', 'Settings', 'Network', 'Abilities', 'Policy', 'Perks', 'Loot', 'Events', 'Horde', 'Tutorial', 'Story', 'Console', 'Terminal', 'Ending', 'Game', 'SelfTest') {
    . (Join-Path $PSScriptRoot "src/$file.ps1")
}
$headless = $SelfTest -or $Screenshots -or $RecordAttractDemo -or $BalanceTest -or $VerifyDemo -or $ExportGif
$script:SfxEnabled = -not $NoSound -and -not $headless
$script:MusicEnabled = -not $NoMusic -and -not $headless
$script:AttractDemo = Join-Path $PSScriptRoot 'demos/attract.json'

if (-not $NoMods -and (-not $headless -or $VerifyDemo -or $ExportGif)) {
    Import-Mods (Join-Path $PSScriptRoot 'mods')
    if ($script:Mods) { Write-Step "mods: $($script:Mods -join ', ')" }
}
if (-not $headless) {
    # what the player has set in the options menu - unless the command line says otherwise
    Import-Settings
    if (-not $PSBoundParameters.ContainsKey('Scale')) { $Scale = [int]$script:Settings.Scale }
    if ($FlatFloors) { $script:Settings.FlatFloors = $true }
}
Write-Step 'loading the C# helpers ...';       Initialize-Scaler
if (-not $headless) { Update-Settings }
Write-Step 'building state tables ...';        Initialize-States
Write-Step 'painting wall textures ...';       Initialize-WallTextures; Initialize-Flats
Write-Step 'painting sprites ...';             Initialize-Sprites
Write-Step 'synthesising sounds ...';          Initialize-Sounds
if (-not $NoVoices) { Initialize-Voices }
Initialize-Renderer $Scale ([int](320 / $Columns))

if ($RecordAttractDemo) {
    Export-AttractDemo $RecordAttractDemo
    return
}
if ($VerifyDemo) {
    if (-not (Test-DemoFile (Resolve-Path -LiteralPath $VerifyDemo).Path)) { exit 1 }
    return
}
if ($ExportGif) {
    $demo = (Resolve-Path -LiteralPath $ExportGif).Path
    if (-not $GifPath) { $GifPath = [System.IO.Path]::ChangeExtension($demo, '.gif') }
    if (-not (Export-DemoGif $demo ([System.IO.Path]::GetFullPath($GifPath, (Get-Location).Path)) $GifStart $GifSeconds $GifScale)) { exit 1 }
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
$script:AutoTutorial = [bool]$Tutorial
$script:AutoHorde = if ($HordeNumber) { $HordeNumber } elseif ($Horde) { Get-DailySeed } else { 0 }
$script:AutoDungeon = if ($Dungeon) { $Dungeon } elseif ($Daily) { Get-DailySeed } else { 0 }
Write-Step 'ready.'
try {
    if ($HostGame) { Initialize-Network 'host' $(if ($HostGame -eq 'Coop') { 'coop' } else { 'duel' }) '' $Port $MaxPlayers $PlayerName; Write-Step "hosting a $HostGame game for up to $MaxPlayers players on port $Port" }
    elseif ($JoinGame) { Initialize-Network 'client' 'coop' $JoinGame $Port 4 $PlayerName; Write-Step "joining the game on ${JoinGame}:$Port" }
    if ($Terminal -or $TerminalKeys) { Initialize-Terminal ([bool]$TerminalKeys) } else { New-GameWindow }
    # the soundtrack of the floors is composed in the background from now on, the floors first
    Start-MusicComposer (@(1..$script:MapFiles.Count) + $script:MUSIC_BONUS + $script:MUSIC_ENDING + 0)
    Start-GameLoop
}
finally {
    if ($script:Mixer) { $script:Mixer::Close() }
    Stop-Terminal
    Stop-Network
    Stop-MusicComposer
    Stop-Music
    if ($script:Form -and -not $script:Form.IsDisposed) { $script:Form.Close(); $script:Form.Dispose() }
    [System.Windows.Forms.Cursor]::Show()
}
