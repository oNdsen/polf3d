# POLF 3D - Copyright (c) 2026 oNdsen. Licensed under the MIT License, see LICENSE.

# Game.ps1 - window, input, the game modes (title, play, dying, level done, game over) and
# the main loop. One pass of the loop = one frame: read input, advance the world by the tics
# that have passed since the last frame, render.

# virtual key codes (index into $script:KeyDown)
$script:VK = @{
    LButton = 1; RButton = 2; Enter = 13; Shift = 16; Ctrl = 17; Esc = 27; Space = 32
    Left = 37; Up = 38; Right = 39; Down = 40
    A = 65; C = 67; D = 68; E = 69; F = 70; G = 71; J = 74; L = 76; M = 77; N = 78; P = 80; Q = 81; R = 82; S = 83; T = 84; V = 86; W = 87; X = 88; Z = 90
    F2 = 113; F3 = 114; F4 = 115; F5 = 116; F6 = 117; F7 = 118; F8 = 119; F9 = 120; F11 = 122; F12 = 123
}

function New-GameWindow {
    $form = [System.Windows.Forms.Form]::new()
    $form.Text = 'POLF 3D'
    $form.ClientSize = [System.Drawing.Size]::new($script:WinW, $script:WinH)
    $form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedSingle
    $form.MaximizeBox = $false
    $form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
    $form.BackColor = [System.Drawing.Color]::Black
    $form.KeyPreview = $true

    $script:KeyDown = [bool[]]::new(256)
    $script:KeyHit = [System.Collections.Generic.Queue[int]]::new()

    $form.Add_KeyDown({
            param($s, $e)
            $c = [int]$e.KeyCode
            if ($c -lt 256) {
                if (-not $script:KeyDown[$c]) { $script:KeyHit.Enqueue($c) }
                $script:KeyDown[$c] = $true
            }
            $e.Handled = $true; $e.SuppressKeyPress = $script:Mode -ne 'console'      # the console wants the characters as well
        })
    $form.Add_KeyPress({ param($s, $e) if ($script:Mode -eq 'console' -and $script:CharQueue) { $script:CharQueue.Enqueue($e.KeyChar) }; $e.Handled = $true })
    $form.Add_PreviewKeyDown({ param($s, $e) if ($e.KeyCode -eq 'Tab') { $e.IsInputKey = $true } })
    $form.Add_KeyUp({ param($s, $e) $c = [int]$e.KeyCode; if ($c -lt 256) { $script:KeyDown[$c] = $false } })
    $form.Add_MouseDown({ param($s, $e) if ($e.Button -eq 'Left') { $script:KeyDown[1] = $true } elseif ($e.Button -eq 'Right') { $script:KeyDown[2] = $true } })
    $form.Add_MouseUp({ param($s, $e) if ($e.Button -eq 'Left') { $script:KeyDown[1] = $false } elseif ($e.Button -eq 'Right') { $script:KeyDown[2] = $false } })
    $form.Add_Deactivate({ [Array]::Clear($script:KeyDown, 0, 256); Set-MouseLook $false })
    $form.Add_FormClosed({ $script:Running = $false })
    $form.Add_Paint({ Show-Back })

    $script:Form = $form
    $form.Show()
    $script:FormG = $form.CreateGraphics()
    # Present through BufferedGraphics: it blits with plain GDI, about six times faster than
    # pushing a GDI+ bitmap to the screen. From here on all drawing goes into its buffer.
    $ctx = [System.Drawing.BufferedGraphicsManager]::Current
    $ctx.MaximumBuffer = [System.Drawing.Size]::new($script:WinW + 1, $script:WinH + 1)
    $script:Buffered = $ctx.Allocate($script:FormG, [System.Drawing.Rectangle]::new(0, 0, $script:WinW, $script:WinH))
    $script:BackG = $script:Buffered.Graphics
    Set-BackGraphicsMode
    $form.Activate()
}

function Set-MouseLook([bool]$On) {
    if ($script:TerminalMode) { return }
    if ($On -eq $script:MouseLook) { return }
    $script:MouseLook = $On
    if ($On) { [System.Windows.Forms.Cursor]::Hide(); Reset-MouseCenter } else { [System.Windows.Forms.Cursor]::Show() }
}

function Reset-MouseCenter {
    $script:MouseCenter = $script:Form.PointToScreen([System.Drawing.Point]::new([int]($script:WinW / 2), [int]($script:WinH / 3)))
    [System.Windows.Forms.Cursor]::Position = $script:MouseCenter
}

# ---------------------------------------------------------------------------------------------
# Starting and restarting
# ---------------------------------------------------------------------------------------------
function Reset-ScreenEffects {
    $script:DamageFlash = 0.0; $script:BonusFlash = 0.0; $script:BeamFlash = 0.0; $script:ForceFlash = 0.0
    $script:MuzzleFlash = 0.0; $script:Shake = 0.0
}

# KeepPlayer: score and lives survive (after a death).  KeepKit: weapons, ammo and health survive
# as well (riding the lift to the next floor). Keys never leave their floor.
function Start-Level([bool]$KeepPlayer, [bool]$KeepKit) {
    $script:NetLive = $false; $script:NetClient = $false
    $script:MapFile = if ($script:DungeonMap) { $script:DungeonMap } elseif ($script:BonusMap) { $script:BonusMap } else { $script:MapFiles[$script:LevelIndex] }
    $script:LevelSeed = if ($script:NextSeed) { $script:NextSeed } else { [int]($script:Clock.ElapsedTicks % 1000000) + 1 }
    $script:NextSeed = $null
    $script:Rng = [System.Random]::new($script:LevelSeed)
    $script:SecretExit = $false
    Initialize-Level $script:MapFile
    if (-not $KeepPlayer) { New-Player }
    if (-not $KeepKit) { Reset-PlayerKit }
    $script:LevelStartScore = $script:P.Score
    Reset-PlayerForLevel
    Set-Background
    Reset-ScreenEffects
    Reset-Abilities
    $script:PlayerDied = $false; $script:LevelDone = $false; $script:Killer = $null
    $script:MadeNoise = $false
    $script:MapBmp = $null
    $script:Message = $null
    $script:ShowWeapon = $true
    $script:HudDirty = $true
    if ($script:Net -and $script:Net.Connected) { Initialize-NetLevel $KeepPlayer $KeepKit }
    elseif ($KeepKit -and -not $script:Playback -and -not $script:Recording) { Save-Game 'auto' }      # arriving by lift
    Start-RunTranscript
    Show-Message $(if ($script:BonusMap) { "Secret floor: $($script:LevelName)" } else { "Floor $($script:LevelIndex + 1): $($script:LevelName)" })
    $script:MusicWanted = if ($script:DungeonSeed) { 1 + $script:DungeonSeed % 5 } elseif ($script:BonusMap) { $script:MUSIC_BONUS } else { $script:LevelIndex + 1 }
    Start-Music $script:MusicWanted
}

function Set-Mode([string]$Mode) {
    $script:Mode = $Mode
    $script:ModeTics = 0.0
    $script:KeyHit.Clear()
    if ($Mode -eq 'title' -and $script:NetLive) { Send-NetMessage 'B' }                # takes the other player along
    if ($Mode -in 'title', 'done', 'gameover') { $script:NetLive = $false; $script:NetClient = $false }
    if ($Mode -ne 'play') { Set-MouseLook $false }
    if ($Mode -eq 'dying') { $null = Stop-RunTranscript $false } elseif ($Mode -eq 'title') { $script:Transcript = $null }
    if ($script:Recording -and $Mode -notin 'play', 'paused') { if ($script:DungeonSeed) { $null = Save-DungeonRun $false } else { Stop-DemoRecording } }
    if ($Mode -eq 'title' -and $script:KeepColumnStep) { $script:ColumnStep = $script:KeepColumnStep; $script:KeepColumnStep = 0 }
    if ($Mode -eq 'title') { Stop-Dungeon }
    if ($Mode -eq 'title') { $script:MusicWanted = 0; Start-Music 0; $script:HasSaves = Test-SaveGame }
    if ($Mode -eq 'load') { $script:SaveList = @(Get-SaveList) }
}

# ---------------------------------------------------------------------------------------------
# One frame of actual game play
# ---------------------------------------------------------------------------------------------
function Get-PlayerInput {
    $k = $script:KeyDown; $vk = $script:VK
    $in = @{ Forward = 0; Strafe = 0; Turn = 0; MouseTurn = 0.0; Run = $k[$vk.Shift]; Sneak = $k[$vk.C]; Weapon = $script:WeaponKey; Ability = [int]$script:AbilityKey
        Fire = ($k[$vk.Ctrl] -or $k[$vk.LButton] -or $k[$vk.J]); Use = ($k[$vk.Space] -or $k[$vk.E] -or $k[$vk.RButton])
    }
    if ($k[$vk.W] -or $k[$vk.Up]) { $in.Forward += 1 }
    if ($k[$vk.S] -or $k[$vk.Down]) { $in.Forward -= 1 }
    if ($k[$vk.D]) { $in.Strafe += 1 }
    if ($k[$vk.A]) { $in.Strafe -= 1 }
    if ($k[$vk.Right]) { $in.Turn += 1 }
    if ($k[$vk.Left]) { $in.Turn -= 1 }
    if ($script:MouseLook) {
        $pos = [System.Windows.Forms.Cursor]::Position
        $in.MouseTurn = ($pos.X - $script:MouseCenter.X) * 0.12
        if ($pos -ne $script:MouseCenter) { [System.Windows.Forms.Cursor]::Position = $script:MouseCenter }
    }
    $script:WeaponKey = -1; $script:AbilityKey = 0
    Add-GamepadInput $in
    $in
}

# ---------------------------------------------------------------------------------------------
# Game pad (XInput):  left stick move/strafe, right stick turn, RT fire, LT run, A use, B sneak,
# LB/RB previous/next weapon, Back automap, Start pause. In menus: D-pad and A.
# ---------------------------------------------------------------------------------------------
$script:PAD = @{ Up = 1; Down = 2; Start = 0x10; Back = 0x20; LB = 0x100; RB = 0x200; A = 0x1000; B = 0x2000; X = 0x4000; Y = 0x8000 }

# Polls the pad once per frame. Looking for a pad that is not there is slow, so that happens only
# every two seconds. Sets $script:PadState (or $null) and $script:PadHit (buttons pressed this frame).
function Update-Gamepad {
    $script:PadHit = 0
    if (-not $script:Pad) { return }
    $now = $script:Clock.Elapsed.TotalSeconds
    if (-not $script:PadState -and $now -lt $script:PadRetry) { return }
    $state = $script:Pad::Read(0)
    if (-not $state) { $script:PadState = $null; $script:PadRetry = $now + 2.0; return }
    $buttons = [int]$state[6]
    $script:PadHit = $buttons -band (-bnot [int]$script:PadButtons)
    $script:PadButtons = $buttons
    $script:PadState = $state
}

# The next owned weapon in the given direction that can actually fire.
function Get-NextWeapon([int]$Step) {
    $n = $script:Weapons.Count; $i = $script:P.Weapon
    for ($k = 0; $k -lt $n; $k++) { $i = ($i + $Step + $n) % $n; if (Test-WeaponReady $i) { return $i } }
    -1
}

function Add-GamepadInput([hashtable]$In) {
    $s = $script:PadState
    if (-not $s) { return }
    $b = $script:PadButtons; $pad = $script:PAD
    $In.Strafe += $s[0]; $In.Forward += $s[1]
    $In.Turn += $s[2] * 1.4
    if ($s[5] -gt 0.3) { $In.Fire = $true }
    if ($s[4] -gt 0.3) { $In.Run = $true }
    if ($b -band $pad.A) { $In.Use = $true }
    if ($b -band $pad.B) { $In.Sneak = $true }
    if ($script:PadHit -band $pad.RB) { $In.Weapon = Get-NextWeapon 1 }
    if ($script:PadHit -band $pad.LB) { $In.Weapon = Get-NextWeapon -1 }
    if ($script:PadHit -band $pad.X) { $In.Ability = 2 }          # -Confirm: the one you need in a hurry
    $In.Forward = [Math]::Max(-1.0, [Math]::Min(1.0, $In.Forward)); $In.Strafe = [Math]::Max(-1.0, [Math]::Min(1.0, $In.Strafe))
}

function Update-World([double]$Tics, [hashtable]$In) {
    $script:MadeNoise = $false
    $playerTics = $Tics
    $Tics = Update-Abilities $Tics $In                           # -Confirm slows the world down, -WhatIf stops it
    if ($Tics -le 0) {
        # time stands still: all one can do is look around
        $script:P.Angle = ($script:P.Angle - $In.Turn * $script:WALK_TURN * $playerTics - $In.MouseTurn + 720.0) % 360.0
        $script:Stats.Tics += $playerTics
        return
    }
    if ($script:NetClient) {
        # guest of a network game: doors and enemies come from the host's snapshots
        Update-PushWall $Tics
        Update-Traps $Tics
        Update-Teleporters $Tics
        Update-Player $Tics $In
        Update-ClientActors $Tics
    }
    else {
        if ($script:NetLive) { $script:NetScope = 'world' }       # what the world does, both players hear
        Update-Doors $Tics
        Update-PushWall $Tics
        $script:NetScope = 'local'
        Update-Traps $Tics
        Update-Teleporters $Tics
        Update-Player $playerTics $In    # the player acts first: enemies hear this frame's shots
        if ($script:NetLive) {
            if ($script:Net.PeerNoise) { $script:MadeNoise = $true; $script:Net.PeerNoise = $false }
            $script:NetScope = 'world'
        }
        Update-Actors $Tics
        $script:NetScope = 'local'
    }
    if ($script:NetLive) { Update-NetGhost $Tics }
    if ($script:DamageFlash -gt 0) { $script:DamageFlash = [Math]::Max(0.0, $script:DamageFlash - $Tics) }
    if ($script:BonusFlash -gt 0) { $script:BonusFlash = [Math]::Max(0.0, $script:BonusFlash - $Tics) }
    if ($script:BeamFlash -gt 0) { $script:BeamFlash = [Math]::Max(0.0, $script:BeamFlash - $Tics) }
    if ($script:ForceFlash -gt 0) { $script:ForceFlash = [Math]::Max(0.0, $script:ForceFlash - $Tics) }
    if ($script:MuzzleFlash -gt 0) { $script:MuzzleFlash = [Math]::Max(0.0, $script:MuzzleFlash - $Tics) }
    if ($script:Shake -gt 0) { $script:Shake = [Math]::Max(0.0, $script:Shake - $Tics) }
    $script:Stats.Tics += $playerTics
    if (-not $script:NetLive -and -not $script:Predicting) { Update-Checkpoints $playerTics }
}

function Show-PlayFrame {
    Update-View
    if ($script:TerminalMode) { return }                         # the terminal shows the frame buffer itself, and text
    Copy-ViewToBack
    Show-Overlays
    if ($script:KeyDown[$script:VK.M] -and $script:Mode -eq 'play') { Show-AutoMap }
    elseif ($script:ShowMiniMap) { Show-MiniMap }
    if ($script:HudDirty) { Show-Hud }
}

# ---------------------------------------------------------------------------------------------
# Screens
# ---------------------------------------------------------------------------------------------
function Show-Shade([string]$Color) { Write-HudBar $Color 0 0 320 240 }

function Show-TitleScreen {
    Show-Shade 'FF0A1020'
    Write-HudBar '2C54C4' 0 0 320 3; Write-HudBar '2C54C4' 0 237 320 3
    Write-HudText 'POLF 3D' 'Huge' '102050' 1.5 9.5 320 40
    Write-HudText 'POLF 3D' 'Huge' 'FFFFFF' 0 8 320 40
    Write-HudText '>_  a ray casting shooter in PowerShell' 'Mid' '40E0FF' 0 46 320 12

    Write-HudText 'DIFFICULTY  (arrow keys, Enter = start)' 'Small' '8FB0FF' 0 66 320 8
    for ($i = 0; $i -lt 4; $i++) {
        $sel = $i -eq $script:Difficulty
        if ($sel) { Write-HudBar '2C54C4' 80 (76 + $i * 11) 160 10 }
        Write-HudText "$($i + 1)  $($script:Difficulties[$i].Name)" 'Mid' $(if ($sel) { 'FFFFFF' } else { '7080A0' }) 80 (76 + $i * 11) 160 10
    }
    $load = if ($script:HasSaves) { 'L = load a saved game     ' } else { '' }
    if ($script:Net) { $load = ''; Write-HudText (Get-NetStatus) 'Small' '60FF80' 0 131 320 8 }
    else {
        $best = Get-DungeonBest (Get-DailySeed)
        Write-HudText "G = today's dungeon #$(Get-DailySeed)$(if ($best) { "   (your best: $(Format-Time ([double]$best.Seconds) -Tenths))" })" 'Small' '40E0FF' 0 131 320 8
    }
    Write-HudText "${load}T = speedrun clock $(if ($script:Speedrun) { 'ON' } else { 'off' })     Esc = quit" 'Small' 'FFE860' 0 123 320 8

    Write-HudText 'CONTROLS' 'Small' '8FB0FF' 0 138 160 8
    $help = "W/S or arrows  move`nA/D  strafe   Shift  run   C  sneak`nCtrl / left mouse  fire`nSpace / E  door, switch, secret wall`n1-9  weapon   M  map   N  minimap   P  pause`nZ -WhatIf  X -Confirm  V -Verbose  F -Force  R Undo`nT / Tab  PowerShell console (or use a terminal)`nF2 mouse look  F3 fps  F4 music  F5 save  F9 load  F12 demo`nXInput game pad: sticks, RT fire, A use, B sneak, LB/RB weapon`nCheats: F6 all  F7 ammo  F8 god  F11 1-hit"
    Write-HudText $help 'Small' 'C0C8D8' 4 144 156 88

    if ($script:Speedrun) {
        Write-HudText 'FASTEST RUNS' 'Small' '8FB0FF' 160 138 160 8
        $y = 148; $runs = @((Get-SpeedrunData).Runs)
        foreach ($run in $runs) { Write-HudText ('{0,-12} {1,8}  {2}' -f $run.Name, (Format-Time $run.Seconds -Tenths), $run.Difficulty) 'Small' 'C0C8D8' 164 $y 152 8; $y += 9 }
        if (-not $runs) { Write-HudText '- no complete run yet -' 'Small' '7080A0' 160 150 160 8 }
    }
    else { Show-HighScoreList }
    Write-HudText "$($script:MapFiles.Count) floors  -  all graphics and sounds are generated procedurally at start-up." 'Small' '506080' 0 217 320 8
    Write-HudText "POLF 3D  $($script:Copyright)" 'Small' '7080A0' 0 226 320 8
}

function Show-HighScoreList {
    Write-HudText 'HIGH SCORES' 'Small' '8FB0FF' 160 138 160 8
    $y = 148
    foreach ($h in $script:HighScores) {
        Write-HudText ('{0,-12} {1,7}  {2}' -f $h.Name, $h.Score, $h.Result) 'Small' 'C0C8D8' 164 $y 152 8
        $y += 9
    }
    if (-not $script:HighScores) { Write-HudText '- empty so far -' 'Small' '7080A0' 160 150 160 8 }
}

function Get-Percent([int]$Count, [int]$Total) { if ($Total -le 0) { 100 } else { [int][Math]::Floor(100 * $Count / $Total) } }

function Complete-Level {
    $st = $script:Stats
    $seconds = [int]($st.Tics / $script:TICRATE)
    if ($script:NetLive -and -not $script:NetClient) { Send-NetMessage "L|$([int][bool]$script:SecretExit)" }
    $r = @{
        Seconds = $seconds
        Kills = Get-Percent $st.Kills $st.KillTotal
        Secrets = Get-Percent $st.Secrets $st.SecretTotal
        Treasures = Get-Percent $st.Treasures $st.TreasureTotal
    }
    $script:P.RunTics += $st.Tics
    $r.Exact = $st.Tics / $script:TICRATE
    # a secret exit leads to maps/bonus<floor>.map, if there is one; afterwards the campaign goes on
    $bonusPath = Join-Path (Split-Path $script:MapFiles[$script:LevelIndex]) "bonus$($script:LevelIndex + 1).map"
    $r.ToBonus = $script:SecretExit -and -not $script:BonusMap -and (Test-Path -LiteralPath $bonusPath)
    $r.BonusPath = $bonusPath
    $r.Last = -not $r.ToBonus -and $script:LevelIndex -ge $script:MapFiles.Count - 1
    if ($script:DungeonSeed) {
        # a dungeon is one floor; its run is saved as a demo, its time kept per seed and difficulty
        $r.ToBonus = $false; $r.Last = $true
        $r.DungeonBest = Get-DungeonBest $script:DungeonSeed
        $r.DungeonDemo = Save-DungeonRun $true
    }
    $r.Previous = Add-SpeedrunResult $r.Exact $r.Last
    $r.Transcript = Stop-RunTranscript $true
    $r.TimeBonus = [Math]::Max(0, $script:ParSeconds - $seconds) * 500
    $r.Bonus = $r.TimeBonus + 10000 * (@($r.Kills, $r.Secrets, $r.Treasures) -eq 100).Count
    $script:Result = $r
    Add-Score $r.Bonus
    if ($r.Last) { Add-HighScore $script:P.Score "VICTORY$(if ($script:P.Cheated) { ' (cheat)' })"; $script:HighScores = Get-HighScores }
    Set-Mode 'done'
}

function Show-DoneScreen {
    $r = $script:Result
    Show-Shade 'FF0A2030'
    $head = if ($r.DungeonDemo) { 'DUNGEON CLEARED!' } elseif ($r.Last) { 'SHELLSTEIN HAS FALLEN!' } elseif ($script:BonusMap) { 'SECRET FLOOR COMPLETED!' } else { "FLOOR $($script:LevelIndex + 1) COMPLETED!" }
    Write-HudText $head 'Big' $(if ($r.Last) { 'F0D040' } else { 'FFFFFF' }) 0 14 320 24
    $best = if ($r.Previous -gt 0 -and $r.Exact -ge $r.Previous) { "best $(Format-Time $r.Previous -Tenths)" } elseif ($script:P.Cheated -or $script:P.RunInvalid) { 'not rated' } else { 'NEW RECORD!' }
    $rows = @(
        @('Time', "$(Format-Time $r.Exact -Tenths)   $best"), @('Par', (Format-Time $script:ParSeconds)), @('Run', (Format-Time ($script:P.RunTics / $script:TICRATE) -Tenths)),
        @('Kills', "$($r.Kills) %"), @('Secrets', "$($r.Secrets) %"), @('Treasures', "$($r.Treasures) %"), @('', ''),
        @('Bonus', "$($r.Bonus)"), @('Score', "$($script:P.Score)")
    )
    $y = 50
    foreach ($row in $rows) {
        if ($row[0]) {
            Write-HudText $row[0] 'Mid' '8FB0FF' 60 $y 100 12
            Write-HudText $row[1] 'Mid' $(if ($row[1] -eq '100 %' -or $row[1] -like '*RECORD*') { '40FF60' } else { 'FFFFFF' }) 150 $y 150 12
        }
        $y += 14
    }
    if ($script:Net -and $script:Net.Mode -eq 'duel') { Write-HudText "FRAGS     you $($script:Net.Frags) : $($script:Net.PeerFrags) opponent" 'Mid' '60C0FF' 0 180 320 12 }
    if ($r.Transcript) { Write-HudText "`"$($r.Transcript.Verdict)`"" 'Small' 'C0C8D8' 0 173 320 8 }
    if ($r.DungeonDemo) {
        $was = if ($r.DungeonBest) { "best so far $(Format-Time ([double]$r.DungeonBest.Seconds) -Tenths)" } else { 'first run of this dungeon' }
        Write-HudText "Dungeon #$($script:DungeonSeed)   $was" 'Small' '40E0FF' 0 182 320 8
        Write-HudText "proof: saves/$($r.DungeonDemo)   (check it with -VerifyDemo)" 'Small' '8FB0FF' 0 190 320 8
    }
    $foot = if ($script:Net -and $script:Net.Role -eq 'client' -and $script:Net.Connected -and -not $r.Last) { 'Waiting for the host to call the lift ...' } elseif ($r.Last) { 'All floors completed - thanks for playing!   Enter = main menu' } elseif ($r.ToBonus) { 'This lift goes somewhere it should not ...   Enter = find out' } else { 'Enter = take the lift to the next floor' }
    Write-HudText $foot 'Small' 'FFE860' 0 200 320 10
}

# ---------------------------------------------------------------------------------------------
# Main loop
# ---------------------------------------------------------------------------------------------
function Start-GameLoop {
    $script:Running = $true
    $script:MouseLook = $false
    $script:ShowMiniMap = $true
    $script:WeaponKey = -1
    $script:HighScores = Get-HighScores
    $vk = $script:VK
    Set-Mode 'title'
    if ($script:AutoDungeon -and (Start-Dungeon $script:AutoDungeon)) { Set-Mode 'play' }
    $last = $script:Clock.Elapsed.TotalSeconds
    $fpsTime = $last; $fpsFrames = 0
    $autoStart = $last; $autoFrames = 0

    while ($script:Running) {
        if ($script:TerminalMode) { Read-TerminalKeys } else { [System.Windows.Forms.Application]::DoEvents() }
        if (-not $script:Running) { break }

        $now = $script:Clock.Elapsed.TotalSeconds
        $dt = $now - $last; $last = $now
        $tics = [Math]::Min($script:MAXTICS, $dt * $script:TICRATE)
        $script:ModeTics += $tics
        $fpsFrames++
        if ($now - $fpsTime -ge 0.5) { $script:Fps = $fpsFrames / ($now - $fpsTime); $fpsFrames = 0; $fpsTime = $now }

        # ---- key presses (edge triggered) ----
        $hits = @()
        while ($script:KeyHit.Count) { $hits += $script:KeyHit.Dequeue() }
        # the pad's menu buttons arrive as the keys they stand for
        Update-Gamepad
        if ($script:PadHit) {
            $pad = $script:PAD
            if ($script:PadHit -band $pad.Start) { $hits += $(if ($script:Mode -in 'play', 'paused') { $vk.P } else { $vk.Enter }) }
            if ($script:Mode -ne 'play') {
                if ($script:PadHit -band $pad.A) { $hits += $vk.Enter }
                if ($script:PadHit -band $pad.Up) { $hits += $vk.Up }
                if ($script:PadHit -band $pad.Down) { $hits += $vk.Down }
            }
            elseif ($script:PadHit -band $pad.Y) { $hits += $vk.N }
        }
        if ($script:PadState) { $script:KeyDown[$vk.M] = [bool]($script:PadButtons -band $script:PAD.Back) }
        if ($hits -contains $vk.F3) { $script:ShowFps = -not $script:ShowFps }
        if ($hits -contains $vk.F4) { Switch-Music }
        Update-Music
        Update-Network $tics

        if ($script:AutoQuit -lt 0) {
            # test aid: watch the attract demo for -AutoQuit seconds, then leave
            if ($script:Mode -eq 'title' -and $script:ModeTics -lt 70 * 14) { $script:ModeTics = 70 * 14 + 1 }
            $autoFrames++
            if ($now - $autoStart -gt - $script:AutoQuit) {
                Write-Step ('Demo window test: {0:0.0} fps on average, mode {1}, frame {2} of {3}' -f ($autoFrames / ($now - $autoStart)), $script:Mode, $script:Playback.Index, $script:Playback.Frames.Count)
                $script:Running = $false
            }
        }
        if ($script:AutoQuit -gt 0) {
            # test aid: no human at the keyboard - start at once, wander about firing, then leave
            if ($script:Mode -eq 'title') { $hits = @($vk.Enter) }
            $script:KeyDown[$vk.W] = $true; $script:KeyDown[$vk.Ctrl] = ([int]($now * 2) % 2 -eq 0); $script:KeyDown[$vk.Right] = ([int]$now % 3 -eq 0)
            $autoFrames++
            if ($now - $autoStart -gt $script:AutoQuit -and $script:TerminalMode) {
                Stop-Terminal
                Write-Step ('Terminal test: {0:0.0} fps on average, mode {1}, {2} frames written, keyboard state polling: {3}' -f ($autoFrames / ($now - $autoStart)), $script:Mode, $script:Term.Frames, $script:Term.Async)
                $script:Running = $false
            }
            elseif ($now - $autoStart -gt $script:AutoQuit) {
                $shotG = [System.Drawing.Graphics]::FromImage($script:BackBmp)
                $script:Buffered.Render($shotG); $shotG.Dispose()
                $null = New-Item -ItemType Directory -Path (Join-Path $script:SaveDir '../selftest') -Force
                $script:BackBmp.Save((Join-Path $script:SaveDir "../selftest/window$(if ($script:Net) { "-$($script:Net.Role)" }).png"))
                Write-Step ('Window test: {0:0.0} fps on average, mode {1}, health {2}' -f ($autoFrames / ($now - $autoStart)), $script:Mode, $script:P.Health)
                if ($script:Con) { Write-Step "Console test: $(($script:Con.Lines | Select-Object -Last 5 | ForEach-Object { $_[0] }) -join ' / ')" }
                if ($script:Net) {
                    $net = $script:Net
                    Write-Step ("Network test ({0}, {1}): connected {2}, live {3}, {4} messages received, other player at {5:0.0},{6:0.0} with health {7}, {8} actors, {9} kills, status '{10}'" -f
                        $net.Role, $net.Mode, $net.Connected, $script:NetLive, $net.Received, $net.Ghost.X, $net.Ghost.Y, $net.PeerHealth, $script:Actors.Count, $script:Stats.Kills, $net.Status)
                }
                $script:Running = $false
            }
        }

        switch ($script:Mode) {
            'title' {
                foreach ($h in $hits) {
                    if ($h -eq $vk.Up) { $script:Difficulty = ($script:Difficulty + 3) % 4 }
                    elseif ($h -eq $vk.Down) { $script:Difficulty = ($script:Difficulty + 1) % 4 }
                    elseif ($h -ge 49 -and $h -le 52) { $script:Difficulty = $h - 49 }
                    elseif ($h -eq $vk.Enter -and -not (Test-NetStart)) { }          # network game: the host starts, once the guest is there
                    elseif ($h -eq $vk.Enter) {
                        $script:LevelIndex = $script:StartLevelIndex; $script:BonusMap = $null; Start-Level $false $false; Set-Mode 'play'
                        if ($script:CheatAllWeapons) { Invoke-Cheat 'GiveAll' }
                    }
                    elseif ($h -eq $vk.L -and -not $script:Net -and (Test-SaveGame)) { $script:LoadReturn = 'title'; Set-Mode 'load' }
                    elseif ($h -eq $vk.G -and -not $script:Net) { if (Start-Dungeon 0) { Set-Mode 'play' } }
                    elseif ($h -eq $vk.T) { $script:Speedrun = -not $script:Speedrun }
                    elseif ($h -eq $vk.Esc) { $script:Running = $false }
                }
                if ($script:Mode -eq 'title') {
                    Show-TitleScreen
                    # nobody home? after a while the attract demo starts
                    if ($script:ModeTics -gt 70 * 14 -and -not $script:Net -and (Test-Path -LiteralPath $script:AttractDemo)) {
                        $keep = $script:Difficulty
                        if (Start-DemoPlayback $script:AttractDemo) { Set-Mode 'demo'; $script:DemoKeepDifficulty = $keep } else { $script:ModeTics = 0.0 }
                    }
                }
            }

            'demo' {
                $frame = Get-DemoFrame
                if ($hits.Count -or -not $frame -or $script:PlayerDied -or $script:LevelDone) {
                    $script:Playback = $null; $script:Difficulty = $script:DemoKeepDifficulty
                    Set-Mode 'title'
                }
                else {
                    Update-World $frame.Tics $frame.In
                    Show-PlayFrame
                    if ([int]($now * 2) % 2 -eq 0) { Write-HudText 'DEMO  -  press any key' 'Mid' 'FFFFFF' 0 186 320 10 }
                    # a demo was recorded with its own tics per frame: do not play it faster than that
                    $wait = $frame.Tics / $script:TICRATE - ($script:Clock.Elapsed.TotalSeconds - $now)
                    if ($wait -gt 0.002) { [System.Threading.Thread]::Sleep([int]($wait * 1000)) }
                }
            }

            'play' {
                foreach ($h in $hits) {
                    if ($h -ge 49 -and $h -le 57) { $script:WeaponKey = $h - 49 }
                    elseif ($h -eq $vk.Esc -or $h -eq $vk.P) { Set-Mode 'paused' }
                    elseif ($h -eq $vk.F2) { Set-MouseLook (-not $script:MouseLook) }
                    elseif ($h -eq $vk.N) { $script:ShowMiniMap = -not $script:ShowMiniMap }
                    elseif ($h -in 9, $vk.T) { Open-Console }                          # Tab or T: the PowerShell console
                    elseif ($h -eq $vk.Z) { $script:AbilityKey = 1 }
                    elseif ($h -eq $vk.X) { $script:AbilityKey = 2 }
                    elseif ($h -eq $vk.V) { $script:AbilityKey = 3 }
                    elseif ($h -eq $vk.F) { $script:AbilityKey = 4 }
                    elseif ($h -eq $vk.R) { $script:AbilityKey = 5 }
                    elseif ($h -eq $vk.F6) { Invoke-Cheat 'GiveAll' }
                    elseif ($h -eq $vk.F7) { Invoke-Cheat 'Ammo' }
                    elseif ($h -eq $vk.F8) { Invoke-Cheat 'God' }
                    elseif ($h -eq $vk.F11) { Invoke-Cheat 'OneHit' }
                    elseif ($script:Net -and $h -in $vk.F12, $vk.F5, $vk.F9) { Show-Message 'Not in a network game' }
                    elseif ($script:DungeonSeed -and $h -in $vk.F12, $vk.F5, $vk.F9) { Show-Message 'Not in the dungeon: one life, no saving, always recorded' }
                    elseif ($h -eq $vk.F12) { if ($script:Recording) { Stop-DemoRecording } else { Start-DemoRecording } }
                    elseif ($h -eq $vk.F5) { Save-Game }
                    elseif ($h -eq $vk.F9) { $null = Restore-Game }
                }
                if ($script:Mode -ne 'play') { break }
                foreach ($h in $hits) { Add-CheatKey $h }
                $in = Get-PlayerInput
                if ($script:Recording) { Add-DemoFrame $tics $in }
                Update-World $tics $in
                Show-PlayFrame
                if ($script:PlayerDied) { $script:ShowWeapon = $false; Set-Mode 'dying' }
                elseif ($script:LevelDone) { Complete-Level }
            }

            'console' {
                if ($script:TerminalMode) { Invoke-TerminalConsole; $last = $script:Clock.Elapsed.TotalSeconds }
                else {
                    Update-Console $hits
                    if ($script:Mode -eq 'console') { Show-PlayFrame; Show-Console }
                }
            }

            'paused' {
                foreach ($h in $hits) {
                    if ($h -eq $vk.Esc -or $h -eq $vk.P) { Set-Mode 'play'; $script:HudDirty = $true }
                    elseif ($h -eq $vk.Q) { Set-Mode 'title' }
                    elseif ($script:Net -or $script:DungeonSeed) { }          # no saving or loading in a network game or in the dungeon
                    elseif ($h -ge 49 -and $h -le 51) { Save-Game "$($h - 48)" }
                    elseif ($h -eq $vk.L -and (Test-SaveGame)) { $script:LoadReturn = 'paused'; Set-Mode 'load' }
                    elseif ($h -eq $vk.F9) { if (Restore-Game) { Set-Mode 'play' } }
                }
                if ($script:Mode -eq 'paused' -and $script:NetLive) {
                    Update-World $tics (New-IdleInput)                       # nobody can stop a world that is shared
                    if ($script:PlayerDied) { $script:ShowWeapon = $false; Set-Mode 'dying' }
                }
                if ($script:Mode -eq 'paused') {
                    Show-PlayFrame
                    Write-HudBar 'A0000000' 0 0 320 200
                    Write-HudText $(if ($script:NetLive) { 'MENU' } else { 'PAUSE' }) 'Big' 'FFFFFF' 0 70 320 24
                    Write-HudText $(if ($script:NetLive) { 'Esc / P = resume     Q = leave the game (the world does not wait!)' } else { 'Esc / P = resume     1-3 = save to slot     L = load     Q = main menu' }) 'Small' 'FFE860' 0 100 320 10
                    if ($script:Message -and $script:Clock.Elapsed.TotalSeconds -lt $script:MessageUntil) { Write-HudText $script:Message 'Mid' '60FF80' 0 116 320 10 }
                }
            }

            'dying' {
                # the view swings round to whoever fired the fatal shot, then everything turns red
                $p = $script:P; $k = $script:Killer
                if ($k -and $script:ModeTics -lt 90) {
                    $want = [Math]::Atan2(- ($k.Y - $p.Y), $k.X - $p.X) * 180.0 / [Math]::PI
                    $diff = (($want - $p.Angle + 540.0) % 360.0) - 180.0
                    $stepA = [Math]::Min([Math]::Abs($diff), 3.0 * $tics)
                    $p.Angle = ($p.Angle + [Math]::Sign($diff) * $stepA + 360.0) % 360.0
                }
                if ($script:NetLive) { Update-World $tics (New-IdleInput) } else { Update-Actors $tics }
                $script:DamageFlash = 0
                Show-PlayFrame
                $alpha = [int][Math]::Min(255, [Math]::Max(0, ($script:ModeTics - 40) * 3))
                Write-HudBar ('{0:X2}A00000' -f $alpha) 0 0 320 200
                if ($script:ModeTics -gt 170 -and $script:NetLive) { Reset-NetPlayer; Set-Mode 'play' }      # no lives: back into the fray
                elseif ($script:ModeTics -gt 170) {
                    $p.Lives--
                    if ($p.Lives -lt 0) {
                        $p.Lives = 0
                        Add-HighScore $p.Score "killed$(if ($p.Cheated) { ' (cheat)' })"
                        $script:HighScores = Get-HighScores
                        Set-Mode 'gameover'
                    }
                    else { $p.Score = $script:LevelStartScore; $p.RunTics += $script:Stats.Tics; Start-Level $true $false; Set-Mode 'play' }
                }
            }

            'load' {
                # pick a saved game by number; Esc goes back to where the menu was opened
                foreach ($h in $hits) {
                    $i = $h - 49
                    if ($i -ge 0 -and $i -lt $script:SaveList.Count) { if (Restore-Game $script:SaveList[$i].Slot) { Set-Mode 'play' }; break }
                    if ($h -eq $vk.Esc) { Set-Mode $script:LoadReturn; $script:HudDirty = $true; break }
                }
                if ($script:Mode -eq 'load') {
                    Show-Shade 'FF0A1020'
                    Write-HudText 'LOAD GAME' 'Big' 'FFFFFF' 0 20 320 24
                    $y = 60
                    for ($i = 0; $i -lt $script:SaveList.Count; $i++) { Write-HudText "$($i + 1)   $($script:SaveList[$i].Text)" 'Small' 'C0C8D8' 0 $y 320 9; $y += 12 }
                    Write-HudText 'press the number of a saved game     Esc = back' 'Small' 'FFE860' 0 200 320 10
                }
            }

            'gameover' {
                Show-Shade 'FF200808'
                Write-HudText 'GAME OVER' 'Huge' 'FF4030' 0 60 320 50
                Write-HudText "Score: $($script:P.Score)" 'Mid' 'FFFFFF' 0 120 320 14
                Write-HudText 'Enter = main menu' 'Small' 'FFE860' 0 150 320 10
                if ($hits -contains $vk.Enter -or $hits -contains $vk.Esc) { Set-Mode 'title' }
            }

            'done' {
                Show-DoneScreen
                if ($script:ModeTics -gt 50 -and ($hits -contains $vk.Enter -or $hits -contains $vk.Esc)) {
                    if ($script:Result.Last) { Set-Mode 'title' }
                    elseif ($script:Net -and $script:Net.Role -eq 'client' -and $script:Net.Connected) { }      # the host calls the lift
                    elseif ($script:Result.ToBonus) { $script:BonusMap = $script:Result.BonusPath; Start-Level $true $true; Set-Mode 'play' }
                    else { $script:BonusMap = $null; $script:LevelIndex++; Start-Level $true $true; Set-Mode 'play' }
                }
            }
        }

        if ($script:TerminalMode) { Show-TerminalFrame } else { Show-Back }
        $spent = $script:Clock.Elapsed.TotalSeconds - $now
        if ($spent -lt 0.012) { [System.Threading.Thread]::Sleep(2) }
    }
    Set-MouseLook $false
}
