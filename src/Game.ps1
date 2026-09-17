# POLF 3D - Copyright (c) 2026 oNdsen. Licensed under the MIT License, see LICENSE.

# Game.ps1 - window, input, the game modes (title, play, dying, level done, game over) and
# the main loop. One pass of the loop = one frame: read input, advance the world by the tics
# that have passed since the last frame, render.

# virtual key codes (index into $script:KeyDown)
$script:VK = @{
    LButton = 1; RButton = 2; Enter = 13; Shift = 16; Ctrl = 17; Esc = 27; Space = 32
    Left = 37; Up = 38; Right = 39; Down = 40
    A = 65; D = 68; E = 69; L = 76; M = 77; P = 80; Q = 81; S = 83; W = 87
    F2 = 113; F3 = 114; F4 = 115; F5 = 116; F6 = 117; F7 = 118; F8 = 119; F9 = 120; F11 = 122
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
            $e.Handled = $true; $e.SuppressKeyPress = $true
        })
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
    $script:MapFile = $script:MapFiles[$script:LevelIndex]
    Initialize-Level $script:MapFile
    if (-not $KeepPlayer) { New-Player }
    if (-not $KeepKit) { Reset-PlayerKit }
    $script:LevelStartScore = $script:P.Score
    Reset-PlayerForLevel
    Set-Background
    Reset-ScreenEffects
    $script:PlayerDied = $false; $script:LevelDone = $false; $script:Killer = $null
    $script:MadeNoise = $false
    $script:MapBmp = $null
    $script:Message = $null
    $script:ShowWeapon = $true
    $script:HudDirty = $true
    Show-Message "Floor $($script:LevelIndex + 1): $($script:LevelName)"
    $script:MusicWanted = $script:LevelIndex + 1
    Start-Music $script:MusicWanted
}

function Set-Mode([string]$Mode) {
    $script:Mode = $Mode
    $script:ModeTics = 0.0
    $script:KeyHit.Clear()
    if ($Mode -ne 'play') { Set-MouseLook $false }
    if ($Mode -eq 'title') { $script:MusicWanted = 0; Start-Music 0 }
}

# ---------------------------------------------------------------------------------------------
# One frame of actual game play
# ---------------------------------------------------------------------------------------------
function Get-PlayerInput {
    $k = $script:KeyDown; $vk = $script:VK
    $in = @{ Forward = 0; Strafe = 0; Turn = 0; MouseTurn = 0.0; Run = $k[$vk.Shift]; Weapon = $script:WeaponKey
        Fire = ($k[$vk.Ctrl] -or $k[$vk.LButton]); Use = ($k[$vk.Space] -or $k[$vk.E] -or $k[$vk.RButton])
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
    $script:WeaponKey = -1
    $in
}

function Update-World([double]$Tics, [hashtable]$In) {
    $script:MadeNoise = $false
    Update-Doors $Tics
    Update-PushWall $Tics
    Update-Player $Tics $In          # the player acts first: enemies hear this frame's shots
    Update-Actors $Tics
    if ($script:DamageFlash -gt 0) { $script:DamageFlash = [Math]::Max(0.0, $script:DamageFlash - $Tics) }
    if ($script:BonusFlash -gt 0) { $script:BonusFlash = [Math]::Max(0.0, $script:BonusFlash - $Tics) }
    if ($script:BeamFlash -gt 0) { $script:BeamFlash = [Math]::Max(0.0, $script:BeamFlash - $Tics) }
    if ($script:ForceFlash -gt 0) { $script:ForceFlash = [Math]::Max(0.0, $script:ForceFlash - $Tics) }
    if ($script:MuzzleFlash -gt 0) { $script:MuzzleFlash = [Math]::Max(0.0, $script:MuzzleFlash - $Tics) }
    if ($script:Shake -gt 0) { $script:Shake = [Math]::Max(0.0, $script:Shake - $Tics) }
    $script:Stats.Tics += $Tics
}

function Show-PlayFrame {
    Update-View
    Copy-ViewToBack
    Show-Overlays
    if ($script:KeyDown[$script:VK.M] -and $script:Mode -eq 'play') { Show-AutoMap }
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
    $load = if (Test-SaveGame) { 'L = load saved game     ' } else { '' }
    Write-HudText "${load}Esc = quit" 'Small' 'FFE860' 0 123 320 8

    Write-HudText 'CONTROLS' 'Small' '8FB0FF' 0 138 160 8
    $help = "W/S or arrows  move`nA/D  strafe   Shift  run`nCtrl / left mouse  fire`nSpace / E  door, switch, secret wall`n1-6  weapon    M  map    P  pause`nF2 mouse look  F3 fps  F4 music  F5 save  F9 load`nCheats: F6 all  F7 ammo  F8 god  F11 1-hit"
    Write-HudText $help 'Small' 'C0C8D8' 4 146 156 68

    Write-HudText 'HIGH SCORES' 'Small' '8FB0FF' 160 138 160 8
    $y = 148
    foreach ($h in $script:HighScores) {
        Write-HudText ('{0,-12} {1,7}  {2}' -f $h.Name, $h.Score, $h.Result) 'Small' 'C0C8D8' 164 $y 152 8
        $y += 9
    }
    if (-not $script:HighScores) { Write-HudText '- empty so far -' 'Small' '7080A0' 160 150 160 8 }
    Write-HudText "$($script:MapFiles.Count) floors  -  all graphics and sounds are generated procedurally at start-up." 'Small' '506080' 0 217 320 8
    Write-HudText "POLF 3D  $($script:Copyright)" 'Small' '7080A0' 0 226 320 8
}

function Get-Percent([int]$Count, [int]$Total) { if ($Total -le 0) { 100 } else { [int][Math]::Floor(100 * $Count / $Total) } }

function Complete-Level {
    $st = $script:Stats
    $seconds = [int]($st.Tics / $script:TICRATE)
    $r = @{
        Seconds = $seconds
        Kills = Get-Percent $st.Kills $st.KillTotal
        Secrets = Get-Percent $st.Secrets $st.SecretTotal
        Treasures = Get-Percent $st.Treasures $st.TreasureTotal
    }
    $r.TimeBonus = [Math]::Max(0, $script:ParSeconds - $seconds) * 500
    $r.Bonus = $r.TimeBonus + 10000 * (@($r.Kills, $r.Secrets, $r.Treasures) -eq 100).Count
    $script:Result = $r
    $r.Last = $script:LevelIndex -ge $script:MapFiles.Count - 1
    Add-Score $r.Bonus
    if ($r.Last) { Add-HighScore $script:P.Score "VICTORY$(if ($script:P.Cheated) { ' (cheat)' })"; $script:HighScores = Get-HighScores }
    Set-Mode 'done'
}

function Show-DoneScreen {
    $r = $script:Result
    Show-Shade 'FF0A2030'
    $head = if ($r.Last) { 'SHELLSTEIN HAS FALLEN!' } else { "FLOOR $($script:LevelIndex + 1) COMPLETED!" }
    Write-HudText $head 'Big' $(if ($r.Last) { 'F0D040' } else { 'FFFFFF' }) 0 14 320 24
    $fmt = { param($s) '{0}:{1:00}' -f [int][Math]::Floor($s / 60), ($s % 60) }
    $rows = @(
        @('Time', (& $fmt $r.Seconds)), @('Par', (& $fmt $script:ParSeconds)), @('', ''),
        @('Kills', "$($r.Kills) %"), @('Secrets', "$($r.Secrets) %"), @('Treasures', "$($r.Treasures) %"), @('', ''),
        @('Bonus', "$($r.Bonus)"), @('Score', "$($script:P.Score)")
    )
    $y = 50
    foreach ($row in $rows) {
        if ($row[0]) {
            Write-HudText $row[0] 'Mid' '8FB0FF' 60 $y 100 12
            Write-HudText $row[1] 'Mid' $(if ($row[1] -eq '100 %') { '40FF60' } else { 'FFFFFF' }) 160 $y 100 12
        }
        $y += 14
    }
    $foot = if ($r.Last) { 'All floors completed - thanks for playing!   Enter = main menu' } else { 'Enter = take the lift to the next floor' }
    Write-HudText $foot 'Small' 'FFE860' 0 200 320 10
}

# ---------------------------------------------------------------------------------------------
# Main loop
# ---------------------------------------------------------------------------------------------
function Start-GameLoop {
    $script:Running = $true
    $script:MouseLook = $false
    $script:WeaponKey = -1
    $script:HighScores = Get-HighScores
    $vk = $script:VK
    Set-Mode 'title'
    $last = $script:Clock.Elapsed.TotalSeconds
    $fpsTime = $last; $fpsFrames = 0
    $autoStart = $last; $autoFrames = 0

    while ($script:Running) {
        [System.Windows.Forms.Application]::DoEvents()
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
        if ($hits -contains $vk.F3) { $script:ShowFps = -not $script:ShowFps }
        if ($hits -contains $vk.F4) { Switch-Music }
        Update-Music

        if ($script:AutoQuit -gt 0) {
            # test aid: no human at the keyboard - start at once, wander about firing, then leave
            if ($script:Mode -eq 'title') { $hits = @($vk.Enter) }
            $script:KeyDown[$vk.W] = $true; $script:KeyDown[$vk.Ctrl] = ([int]($now * 2) % 2 -eq 0); $script:KeyDown[$vk.Right] = ([int]$now % 3 -eq 0)
            $autoFrames++
            if ($now - $autoStart -gt $script:AutoQuit) {
                $shotG = [System.Drawing.Graphics]::FromImage($script:BackBmp)
                $script:Buffered.Render($shotG); $shotG.Dispose()
                $null = New-Item -ItemType Directory -Path (Join-Path $script:SaveDir '../selftest') -Force
                $script:BackBmp.Save((Join-Path $script:SaveDir '../selftest/window.png'))
                Write-Step ('Window test: {0:0.0} fps on average, mode {1}, health {2}' -f ($autoFrames / ($now - $autoStart)), $script:Mode, $script:P.Health)
                $script:Running = $false
            }
        }

        switch ($script:Mode) {
            'title' {
                foreach ($h in $hits) {
                    if ($h -eq $vk.Up) { $script:Difficulty = ($script:Difficulty + 3) % 4 }
                    elseif ($h -eq $vk.Down) { $script:Difficulty = ($script:Difficulty + 1) % 4 }
                    elseif ($h -ge 49 -and $h -le 52) { $script:Difficulty = $h - 49 }
                    elseif ($h -eq $vk.Enter) {
                        $script:LevelIndex = $script:StartLevelIndex; Start-Level $false $false; Set-Mode 'play'
                        if ($script:CheatAllWeapons) { Invoke-Cheat 'GiveAll' }
                    }
                    elseif ($h -eq $vk.L) { if (Restore-Game) { Set-Mode 'play' } }
                    elseif ($h -eq $vk.Esc) { $script:Running = $false }
                }
                if ($script:Mode -eq 'title') { Show-TitleScreen }
            }

            'play' {
                foreach ($h in $hits) {
                    if ($h -ge 49 -and $h -le 54) { $script:WeaponKey = $h - 49 }
                    elseif ($h -eq $vk.Esc -or $h -eq $vk.P) { Set-Mode 'paused' }
                    elseif ($h -eq $vk.F2) { Set-MouseLook (-not $script:MouseLook) }
                    elseif ($h -eq $vk.F6) { Invoke-Cheat 'GiveAll' }
                    elseif ($h -eq $vk.F7) { Invoke-Cheat 'Ammo' }
                    elseif ($h -eq $vk.F8) { Invoke-Cheat 'God' }
                    elseif ($h -eq $vk.F11) { Invoke-Cheat 'OneHit' }
                    elseif ($h -eq $vk.F5) { Save-Game }
                    elseif ($h -eq $vk.F9) { $null = Restore-Game }
                }
                if ($script:Mode -ne 'play') { break }
                foreach ($h in $hits) { Add-CheatKey $h }
                Update-World $tics (Get-PlayerInput)
                Show-PlayFrame
                if ($script:PlayerDied) { $script:ShowWeapon = $false; Set-Mode 'dying' }
                elseif ($script:LevelDone) { Complete-Level }
            }

            'paused' {
                foreach ($h in $hits) {
                    if ($h -eq $vk.Esc -or $h -eq $vk.P) { Set-Mode 'play'; $script:HudDirty = $true }
                    elseif ($h -eq $vk.Q) { Set-Mode 'title' }
                    elseif ($h -eq $vk.F9) { if (Restore-Game) { Set-Mode 'play' } }
                }
                if ($script:Mode -eq 'paused') {
                    Show-PlayFrame
                    Write-HudBar 'A0000000' 0 0 320 200
                    Write-HudText 'PAUSE' 'Big' 'FFFFFF' 0 70 320 24
                    Write-HudText 'Esc / P = resume     F9 = load     Q = main menu' 'Small' 'FFE860' 0 100 320 10
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
                Update-Actors $tics
                $script:DamageFlash = 0
                Show-PlayFrame
                $alpha = [int][Math]::Min(255, [Math]::Max(0, ($script:ModeTics - 40) * 3))
                Write-HudBar ('{0:X2}A00000' -f $alpha) 0 0 320 200
                if ($script:ModeTics -gt 170) {
                    $p.Lives--
                    if ($p.Lives -lt 0) {
                        $p.Lives = 0
                        Add-HighScore $p.Score "killed$(if ($p.Cheated) { ' (cheat)' })"
                        $script:HighScores = Get-HighScores
                        Set-Mode 'gameover'
                    }
                    else { $p.Score = $script:LevelStartScore; Start-Level $true $false; Set-Mode 'play' }
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
                    else { $script:LevelIndex++; Start-Level $true $true; Set-Mode 'play' }
                }
            }
        }

        Show-Back
        $spent = $script:Clock.Elapsed.TotalSeconds - $now
        if ($spent -lt 0.012) { [System.Threading.Thread]::Sleep(2) }
    }
    Set-MouseLook $false
}
