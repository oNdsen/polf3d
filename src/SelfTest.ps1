# POLF 3D - Copyright (c) 2026 oNdsen. Licensed under the MIT License, see LICENSE.

# SelfTest.ps1 - headless smoke test (Start-Polf3D.ps1 -SelfTest): renders views and asset
# sheets to PNG files, measures the frame time, plays a few hundred scripted frames and does
# a save/load round trip. No window needed, so it also works over a remote session.

function Save-BackBuffer([string]$Path) { $script:BackBmp.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png) }

function Set-TestCamera([double]$X, [double]$Y, [double]$Angle) {
    $script:P.X = $X; $script:P.Y = $Y; $script:P.Angle = $Angle
    $area = $script:AreaOf[[int][Math]::Floor($Y) * $script:MapW + [int][Math]::Floor($X)]
    if ($area -ge 0) { $script:P.Area = $area }
    Update-AreaByPlayer
}

# All sprites (or wall textures) on one sheet, 4x enlarged, on a magenta background.
function Save-ArtSheet([string]$Path, [object[]]$Images, [string[]]$Labels) {
    $cols = 10; $cell = 64 * 3 + 8
    $rows = [int][Math]::Ceiling($Images.Count / $cols)
    $bmp = [System.Drawing.Bitmap]::new($cols * $cell, $rows * ($cell + 14))
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.Clear([System.Drawing.Color]::FromArgb(255, 90, 40, 90))
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::NearestNeighbor
    $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::Half
    $font = [System.Drawing.Font]::new('Consolas', 8)
    for ($i = 0; $i -lt $Images.Count; $i++) {
        $tile = [System.Drawing.Bitmap]::new(64, 64, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
        $bd = $tile.LockBits([System.Drawing.Rectangle]::new(0, 0, 64, 64), 'WriteOnly', $tile.PixelFormat)
        [System.Runtime.InteropServices.Marshal]::Copy([int[]]$Images[$i], 0, $bd.Scan0, 4096)
        $tile.UnlockBits($bd)
        $x = ($i % $cols) * $cell; $y = [int][Math]::Floor($i / $cols) * ($cell + 14)
        $g.DrawImage($tile, [System.Drawing.Rectangle]::new($x + 4, $y + 2, 192, 192))
        $g.DrawString($Labels[$i], $font, [System.Drawing.Brushes]::White, $x + 2, $y + 194)
        $tile.Dispose()
    }
    $bmp.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
    $g.Dispose(); $bmp.Dispose()
}

function Set-TestAim([Actor]$Target) {
    $script:P.Angle = ([Math]::Atan2(- ($Target.Y - $script:P.Y), $Target.X - $script:P.X) * 180 / [Math]::PI + 360) % 360
}

function Invoke-SelfTest([string]$OutDir) {
    $null = New-Item -ItemType Directory -Path $OutDir -Force
    $script:SaveDir = Join-Path $OutDir 'saves'
    $script:GodMode = $true
    $script:KeyDown = [bool[]]::new(256)
    $script:KeyHit = [System.Collections.Generic.Queue[int]]::new()
    $script:Mode = 'play'

    # ---- art sheets ----
    $imgs = @(); $labels = @()
    for ($i = 1; $i -lt $script:WallNames.Count; $i++) { $imgs += , $script:WallLight[$i]; $labels += $script:WallNames[$i] }
    Save-ArtSheet (Join-Path $OutDir 'sheet-walls.png') $imgs $labels
    $imgs = @(); $labels = @()
    foreach ($k in ($script:Spr.Keys | Sort-Object)) {
        $v = $script:Spr[$k]
        if ($v[0] -is [int]) { $imgs += , $v; $labels += $k }
        else { for ($j = 0; $j -lt $v.Count; $j++) { $imgs += , $v[$j]; $labels += "$k[$j]" } }
    }
    Save-ArtSheet (Join-Path $OutDir 'sheet-sprites.png') $imgs $labels
    Write-Step "art sheets written ($($imgs.Count) sprite images)"

    # ---- views ----
    Start-Level $false $false
    Show-PlayFrame; Save-BackBuffer (Join-Path $OutDir 'view-1-start.png')
    $shots = @(
        @('view-2-corridor', 7.5, 34.5, 90), @('view-3-hub', 20.5, 24.5, 45), @('view-4-kennels', 24.5, 29.5, 250),
        @('view-5-officers', 21.5, 10.5, 110), @('view-6-storage', 32.5, 19.5, 0), @('view-7-lab', 38.5, 26.5, 270),
        @('view-8-commander', 45.5, 19.5, 0), @('view-9-arena', 34.5, 10.5, 90), @('view-10-lift', 40.5, 7.5, 0)
    )
    foreach ($s in $shots) {
        Set-TestCamera $s[1] $s[2] $s[3]
        Show-PlayFrame; $script:HudDirty = $true; Show-PlayFrame
        Save-BackBuffer (Join-Path $OutDir "$($s[0]).png")
    }

    # ---- frame time ----
    Set-TestCamera 20.5 24.5 45
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    for ($i = 0; $i -lt 40; $i++) { $script:P.Angle = ($script:P.Angle + 3) % 360; Show-PlayFrame }
    Write-Step ('rendering: {0:0.0} ms per frame ({1} rays)' -f ($sw.ElapsedMilliseconds / 40), (320 / $script:ColumnStep))

    # ---- combat: sneak up behind the corridor guard and shoot him; the noise must wake his colleagues ----
    Start-Level $false $false
    Set-TestCamera 7.5 30.5 90
    $fire = @{ Forward = 0; Strafe = 0; Turn = 0; MouseTurn = 0.0; Run = $false; Fire = $true; Use = $false; Weapon = -1 }
    $idle = @{ Forward = 0; Strafe = 0; Turn = 0; MouseTurn = 0.0; Run = $false; Fire = $false; Use = $false; Weapon = -1 }
    $script:P.Ammo = 99                                     # the dice decide every shot - do not let the test depend on 8 bullets
    $target = $script:Actors | Where-Object { $_.Kind -eq 'guard' -and [Math]::Floor($_.X) -eq 7 -and [Math]::Floor($_.Y) -eq 27 }
    for ($f = 0; $f -lt 900 -and $script:Stats.Kills -eq 0; $f++) {
        if ($f -gt 0) { Set-TestAim $target }                     # after the first shot he moves - keep him in the sights like a player would
        Show-PlayFrame; Update-World 2.0 $(if ($f % 20 -lt 10) { $fire } else { $idle })
    }
    if ($script:Stats.Kills -lt 1) { throw 'combat test: the guard in the cell corridor was never hit.' }
    Show-PlayFrame; Save-BackBuffer (Join-Path $OutDir 'view-0-combat.png')
    # open the door to the guard room: its occupants should come for us
    Set-TestCamera 7.5 24.5 90
    $use = $idle.Clone(); $use.Use = $true
    Update-World 1.0 $use
    for ($f = 0; $f -lt 400; $f++) { Show-PlayFrame; Update-World 2.0 $(if ($f % 20 -lt 10) { $fire } else { $idle }) }
    $alert = @($script:Actors | Where-Object AttackMode).Count
    Write-Step "combat test: kills $($script:Stats.Kills), alerted enemies $alert, health $($script:P.Health), ammo $($script:P.Ammo)"
    Show-PlayFrame; Save-BackBuffer (Join-Path $OutDir 'view-0-combat2.png')

    # ---- cheats ----
    Start-Level $false $false
    $p = $script:P
    Invoke-Cheat 'GiveAll'
    if (-not $p.Owned[5] -or $p.Ammo -ne 99 -or -not $p.KeyGold) { throw 'cheat test: GiveAll' }
    Invoke-Cheat 'Ammo'; Invoke-Cheat 'OneHit'
    $target = $script:Actors | Where-Object { $_.Kind -eq 'guard' -and [Math]::Floor($_.X) -eq 7 -and [Math]::Floor($_.Y) -eq 27 }
    Set-TestCamera 7.5 30.5 90
    $p.Weapon = 1; $p.ChosenWeapon = 1
    for ($f = 0; $f -lt 900 -and $target.Shootable; $f++) { Set-TestAim $target; Show-PlayFrame; Update-World 2.0 $(if ($f % 20 -lt 10) { $fire } else { $idle }) }
    if ($target.Shootable -or $p.Ammo -ne 99) { throw "cheat test: one-hit kill / infinite ammo (ammo $($p.Ammo))" }
    $script:GodMode = $false; $p.Health = 100
    Invoke-PlayerDamage 1 $target
    if ($p.Health -ne 0) { throw 'cheat test: one-hit kill must apply to the player as well' }
    $script:GodMode = $true; $script:PlayerDied = $false
    Invoke-Cheat 'Ammo'; Invoke-Cheat 'OneHit'
    foreach ($c in 'R', 'O', 'O', 'T') { Add-CheatKey ([int][char]$c) }          # typed code word toggles god mode
    if ($script:GodMode) { throw 'cheat test: code word ROOT' }
    $script:GodMode = $true
    Write-Step "cheat test ok (GiveAll, infinite ammo, one-hit kill both ways, code word)"

    # ---- a dog must complete its leap (jump1..jump5) and bite ----
    Start-Level $false $false
    $dog = $script:Actors | Where-Object Kind -eq 'dog' | Select-Object -First 1
    Set-TestCamera ($dog.X + 3 * $script:DirDX[$dog.PathDir]) ($dog.Y + 3 * $script:DirDY[$dog.PathDir]) ((($dog.PathDir * 45) + 180) % 360)   # right in its path, face to face
    $script:GodMode = $false; $script:P.Health = 100
    $dogStates = [System.Collections.Generic.List[string]]::new()
    for ($f = 0; $f -lt 400; $f++) { Show-PlayFrame; Update-World 1.0 $idle; if ($dogStates.Count -eq 0 -or $dogStates[-1] -ne $dog.State) { $dogStates.Add($dog.State) } }
    $script:GodMode = $true
    Write-Step "dog test: health $($script:P.Health), states: $(($dogStates | Select-Object -Unique) -join ' > ')"
    if ('dog.jump5' -notin $dogStates) { throw 'dog test: the leap is never completed.' }

    # ---- boss fight (floor 4): war machine -> rockets -> pilot, fought with both special weapons ----
    $script:LevelIndex = [Math]::Min(3, $script:MapFiles.Count - 1)
    Start-Level $false $false
    $p = $script:P
    $p.Owned = [bool[]]($true, $true, $true, $true, $true, $true); $p.Ammo = 99; $p.Charges = 40
    $mech = $script:Actors | Where-Object Kind -eq 'uber' | Select-Object -First 1
    if ($mech) {
        Set-TestCamera $mech.X ($mech.Y - 5) 270
        $sawRocket = $false; $sawPilot = $false; $shot = $false
        for ($f = 0; $f -lt 2500; $f++) {
            $in = $fire.Clone(); $in.Fire = ($f % 12 -lt 6)
            if ($f -eq 0) { $in.Weapon = 4 } elseif ($p.Ammo -lt 4 -and $p.Weapon -ne 5) { $in.Weapon = 5 }
            Show-PlayFrame; Update-World 2.0 $in
            if (@($script:Actors | Where-Object Kind -eq 'rocket').Count) { $sawRocket = $true }
            if (@($script:Actors | Where-Object Kind -eq 'pilot').Count) { $sawPilot = $true }
            if (-not $shot -and $script:BeamFlash -gt 0) { Show-PlayFrame; Save-BackBuffer (Join-Path $OutDir 'view-0-beam.png'); $shot = $true }
            if ($f -eq 300) { Save-BackBuffer (Join-Path $OutDir 'view-0-bossfight.png') }
            if ($sawPilot -and -not @($script:Actors | Where-Object { $_.Kind -in 'uber', 'pilot' -and $_.Shootable }).Count) { break }
        }
        Write-Step "boss test: after $f frames - rocket seen: $sawRocket, pilot seen: $sawPilot, kills $($script:Stats.Kills)"
        if (-not $sawRocket -or -not $sawPilot -or $f -ge 2500) { throw 'boss test failed.' }
        Show-PlayFrame; Save-BackBuffer (Join-Path $OutDir 'view-0-bossdead.png')
    }
    $script:LevelIndex = 0

    # ---- scripted play: walk, turn, shoot, use - everything that could throw ----
    Start-Level $false $false
    $p = $script:P
    $p.Owned = [bool[]]($true, $true, $true, $true, $true, $true); $p.Ammo = 99; $p.Charges = 3
    $sw.Restart()
    for ($f = 0; $f -lt 900; $f++) {
        $in = @{ Forward = 1; Strafe = 0; Turn = 0; MouseTurn = 0.0; Run = ($f % 200 -gt 100); Fire = ($f % 40 -lt 25); Use = ($f % 30 -eq 0); Weapon = -1 }
        if ($f % 150 -eq 0) { $in.Weapon = [int]($f / 150) % 6 }
        if ($f % 90 -gt 70) { $in.Turn = 1 }
        if ($f -eq 300) { Set-TestCamera 20.5 19.5 0 }               # into the hub: lots of company
        if ($f -eq 600) { Set-TestCamera 34.5 9.5 90; $script:P.KeyGold = $true }   # face the war machine
        Update-World 2.0 $in
        if ($f % 10 -eq 0) { Show-PlayFrame }
    }
    Write-Step ('simulation: 900 frames in {0:0.0}s, kills {1}/{2}, actors {3}' -f $sw.Elapsed.TotalSeconds, $script:Stats.Kills, $script:Stats.KillTotal, $script:Actors.Count)
    Show-PlayFrame; Save-BackBuffer (Join-Path $OutDir 'view-11-after-sim.png')

    # ---- save / load round trip ----
    $before = "$($p.X);$($p.Y);$($p.Ammo);$($script:Stats.Kills);$($script:Actors.Count);$(($script:Tiles | Measure-Object -Sum).Sum)"
    Save-Game
    $ok = Restore-Game
    $p = $script:P
    $after = "$($p.X);$($p.Y);$($p.Ammo);$($script:Stats.Kills);$($script:Actors.Count);$(($script:Tiles | Measure-Object -Sum).Sum)"
    if (-not $ok -or $before -ne $after) { throw "savegame test failed: '$before' <> '$after' ($($script:Message))" }
    for ($f = 0; $f -lt 60; $f++) { Update-World 2.0 @{ Forward = 0; Strafe = 0; Turn = 1; MouseTurn = 0.0; Run = $false; Fire = $true; Use = $false; Weapon = -1 } }
    Show-PlayFrame; Save-BackBuffer (Join-Path $OutDir 'view-12-after-load.png')
    Write-Step 'savegame round trip ok'

    # ---- every floor: load, look around, let the world run for a while ----
    $script:StatesSeen = @()
    for ($li = 0; $li -lt $script:MapFiles.Count; $li++) {
        $script:LevelIndex = $li
        Start-Level $true $true
        Show-PlayFrame; Save-BackBuffer (Join-Path $OutDir "floor-$($li + 1)-start.png")
        # soak: every door open, constant noise - the whole floor wakes up and comes for the (immortal) player
        $seen = @{}
        for ($f = 0; $f -lt 1500; $f++) {
            if ($f % 100 -eq 0) { for ($d = 0; $d -lt $script:Doors.Count; $d++) { Open-Door $d } }
            $in = $idle.Clone(); $in.Turn = 1; $in.Fire = ($f % 30 -lt 5)
            Update-World 2.0 $in
            $script:MadeNoise = $true
            if ($f % 5 -eq 0) { Show-PlayFrame; foreach ($a in $script:Actors) { $seen[$a.State] = $true } }
        }
        # bosses only react to what they see: visit each one and fight it out with the Force-Blaster
        $p = $script:P
        $p.Owned = [bool[]]($true, $true, $true, $true, $true, $true); $p.Charges = 500; $p.Weapon = 5; $p.ChosenWeapon = 5
        foreach ($b in @($script:Actors | Where-Object { $_.Kind -in 'boss', 'uber' -and $_.Shootable })) {
            $spot = $null
            foreach ($dist in 3, 2, 4, 1) {
                foreach ($dir in 0, 2, 4, 6) {
                    $sx = [Math]::Floor($b.X) + $script:DirDX[$dir] * $dist; $sy = [Math]::Floor($b.Y) + $script:DirDY[$dir] * $dist
                    $i = $sy * $script:MapW + $sx
                    if (-not $spot -and $script:Tiles[$i] -eq 0 -and -not $script:StaticBlock[$i] -and $script:AreaOf[$i] -eq $b.Area) { $spot = @(($sx + 0.5), ($sy + 0.5)) }
                }
            }
            if (-not $spot) { continue }
            $angle = [Math]::Atan2(- ($b.Y - $spot[1]), $b.X - $spot[0]) * 180 / [Math]::PI
            Set-TestCamera $spot[0] $spot[1] (($angle + 360) % 360)
            for ($f = 0; $f -lt 1500; $f++) {
                $in = $idle.Clone(); $in.Fire = ($f % 60 -lt 30 -and $f -gt 200)
                Show-PlayFrame; Update-World 2.0 $in
                foreach ($a in $script:Actors) { $seen[$a.State] = $true }
                if ($f -gt 200 -and -not @($script:Actors | Where-Object { $_.Kind -in 'boss', 'uber', 'pilot' -and $_.Shootable -and $_.Area -eq $b.Area }).Count) { $f = [Math]::Max($f, 1400) }
            }
        }
        Save-BackBuffer (Join-Path $OutDir "floor-$($li + 1)-soak.png")
        $script:StatesSeen += @($seen.Keys)
        Write-Step ("floor {0} '{1}': {2}x{3}, {4} enemies, {5} doors, {6} secrets" -f ($li + 1), $script:LevelName, $script:MapW, $script:MapH, $script:Stats.KillTotal, $script:Doors.Count, $script:Stats.SecretTotal)
    }
    $script:LevelIndex = 0
    $never = @($script:States.Keys | Where-Object { $_ -notin $script:StatesSeen } | Sort-Object)
    Write-Step "states visited: $(@($script:StatesSeen | Sort-Object -Unique).Count) of $($script:States.Count); never seen: $($never -join ', ')"

    # ---- title screen ----
    $script:HighScores = @()
    Show-TitleScreen; Save-BackBuffer (Join-Path $OutDir 'screen-title.png')
    Write-Step "self-test finished: $OutDir"
}

# =============================================================================================
# Screenshots for the README (Start-Polf3D.ps1 -Screenshots <dir>): headless, staged scenes.
# =============================================================================================
function Save-Shot([string]$Dir, [string]$Name) {
    # staged scenes run in god mode; hide that (and any damage tint) for the picture
    $god = $script:GodMode; $script:GodMode = $false
    $script:DamageFlash = 0.0; $script:P.Health = [Math]::Max($script:P.Health, 87); $script:HudDirty = $true
    Show-PlayFrame
    Save-BackBuffer (Join-Path $Dir "$Name.png")
    $script:GodMode = $god
}

function Export-Screenshots([string]$OutDir) {
    $null = New-Item -ItemType Directory -Path $OutDir -Force
    $script:SaveDir = Join-Path $OutDir '_tmp'
    $script:GodMode = $true
    $script:KeyDown = [bool[]]::new(256)
    $script:KeyHit = [System.Collections.Generic.Queue[int]]::new()
    $script:Mode = 'play'
    $idle = @{ Forward = 0; Strafe = 0; Turn = 0; MouseTurn = 0.0; Run = $false; Fire = $false; Use = $false; Weapon = -1 }
    $fire = $idle.Clone(); $fire.Fire = $true

    # title
    $script:HighScores = @([pscustomobject]@{ Name = 'root'; Score = 184300; Result = 'VICTORY' }, [pscustomobject]@{ Name = 'sysadmin'; Score = 96500; Result = 'killed' }, [pscustomobject]@{ Name = 'intern'; Score = 12400; Result = 'killed' })
    Show-TitleScreen; Save-BackBuffer (Join-Path $OutDir 'title.png')

    # floor 1: the hub hall
    $script:LevelIndex = 0; Start-Level $false $false; $script:Message = $null
    Set-TestCamera 20.5 24.5 45
    Save-Shot $OutDir 'hub'

    # floor 1: a fire fight at the guard room door
    Set-TestCamera 7.5 24.5 90
    $use = $idle.Clone(); $use.Use = $true
    Update-World 1.0 $idle; Update-World 1.0 $use             # release, then press: 'use' is edge triggered
    $script:P.Ammo = 60
    for ($f = 0; $f -lt 600; $f++) {
        Show-PlayFrame; Update-World 2.0 $(if ($f % 40 -lt 6) { $fire } else { $idle })
        $shooter = @($script:Actors | Where-Object { $_.Visible -and $_.State -like '*.shoot2' -and $_.Depth -gt 1.2 -and $_.Depth -lt 5 -and [Math]::Abs($_.ScreenX - 160) -lt 90 })
        if ($f -gt 60 -and $shooter.Count) { break }
    }
    $script:Message = $null; Save-Shot $OutDir 'firefight'

    # floor 1: automap of what has been seen so far, plus a stroll through the hub
    foreach ($c in @(7.5, 30.5, 90), @(8.5, 19.5, 0), @(15.5, 19.5, 0), @(24.5, 19.5, 0), @(24.5, 19.5, 180), @(24.5, 19.5, 90), @(24.5, 19.5, 270), @(24.5, 28.5, 270), @(20.5, 32.5, 0), @(20.5, 32.5, 180), @(20.5, 10.5, 90), @(20.5, 8.5, 0), @(20.5, 8.5, 180), @(33.5, 19.5, 0), @(38.5, 19.5, 90), @(38.5, 19.5, 270)) { Set-TestCamera $c[0] $c[1] $c[2]; Show-PlayFrame }
    Set-TestCamera 24.5 20.5 60
    $script:KeyDown[77] = $true; $script:MapBmp = $null
    Save-Shot $OutDir 'automap'
    $script:KeyDown[77] = $false

    # floor 1: the kennels
    Start-Level $false $false; $script:Message = $null
    Set-TestCamera 20.5 35.5 60
    for ($f = 0; $f -lt 40; $f++) { Show-PlayFrame; Update-World 2.0 $idle }
    Save-Shot $OutDir 'kennels'

    # floor 3: catacombs
    $script:LevelIndex = 2; Start-Level $false $false; $script:Message = $null
    Set-TestCamera 26.5 30.5 135
    Save-Shot $OutDir 'catacombs'

    # floor 4: the ring corridor with a patrol coming
    $script:LevelIndex = 3; Start-Level $false $false; $script:Message = $null
    Set-TestCamera 22.5 7.5 180
    for ($f = 0; $f -lt 25; $f++) { Show-PlayFrame; Update-World 2.0 $idle }
    Save-Shot $OutDir 'lab'

    # floor 4: pipeline cannon versus the war machine
    $p = $script:P
    $p.Owned = [bool[]]($true, $true, $true, $true, $true, $true); $p.Ammo = 99; $p.Charges = 3; $p.Weapon = 4; $p.ChosenWeapon = 4
    $mech = $script:Actors | Where-Object Kind -eq 'uber' | Select-Object -First 1
    Set-TestCamera ($mech.X + 0.4) ($mech.Y - 5.5) 270
    for ($f = 0; $f -lt 900; $f++) {
        Show-PlayFrame; Update-World 2.0 $(if ($f % 30 -lt 15 -and $f -gt 120) { $fire } else { $idle })
        $rockets = @($script:Actors | Where-Object { $_.Kind -eq 'rocket' -and $_.State -eq 'rocket.fly' -and $_.Visible -and $_.Depth -gt 1.5 })
        if ($script:BeamFlash -gt 5 -and $rockets.Count -and $mech.Shootable) { break }
    }
    $script:Message = $null; $p.Ammo = 71; Save-Shot $OutDir 'warmachine'

    # floor 5: the great hall
    $script:LevelIndex = 4; Start-Level $false $false; $script:Message = $null
    $p = $script:P; $p.Owned = [bool[]]($true, $true, $true, $true, $false, $false); $p.Ammo = 84; $p.Weapon = 3; $p.ChosenWeapon = 3
    Set-TestCamera 23.5 29.5 90
    for ($f = 0; $f -lt 30; $f++) { Show-PlayFrame; Update-World 2.0 $idle }
    Save-Shot $OutDir 'citadel'

    # the cast: front views of every enemy, 3x
    $cast = 'guard.s', 'dog.s', 'officer.s', 'elite.s', 'mutant.s', 'boss.s', 'uber.s', 'pilot.s'
    $names = 'Guard', 'Dog', 'Officer', 'Elite', 'Mutant', 'Commander', 'War machine', 'Pilot'
    $cell = 200
    $bmp = [System.Drawing.Bitmap]::new($cell * $cast.Count, 236)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.Clear([System.Drawing.Color]::FromArgb(255, 10, 16, 32))
    $g.FillRectangle((Get-Brush '6E6E6E'), 0, 150, $bmp.Width, 60); $g.FillRectangle((Get-Brush '0A1428'), 0, 206, $bmp.Width, 30)
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::NearestNeighbor
    $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::Half
    $font = [System.Drawing.Font]::new('Consolas', 11, [System.Drawing.FontStyle]::Bold)
    $fmt = [System.Drawing.StringFormat]::new(); $fmt.Alignment = [System.Drawing.StringAlignment]::Center
    for ($i = 0; $i -lt $cast.Count; $i++) {
        $px = $script:Spr[$cast[$i]]; if ($px[0] -isnot [int]) { $px = $px[0] }
        $tile = [System.Drawing.Bitmap]::new(64, 64, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
        $bd = $tile.LockBits([System.Drawing.Rectangle]::new(0, 0, 64, 64), 'WriteOnly', $tile.PixelFormat)
        [System.Runtime.InteropServices.Marshal]::Copy([int[]]$px, 0, $bd.Scan0, 4096); $tile.UnlockBits($bd)
        $g.DrawImage($tile, [System.Drawing.Rectangle]::new($i * $cell + 4, 8, 192, 192)); $tile.Dispose()
        $g.DrawString($names[$i], $font, [System.Drawing.Brushes]::White, [System.Drawing.RectangleF]::new($i * $cell, 212, $cell, 22), $fmt)
    }
    $bmp.Save((Join-Path $OutDir 'cast.png'), [System.Drawing.Imaging.ImageFormat]::Png); $g.Dispose(); $bmp.Dispose()

    Remove-Item -LiteralPath $script:SaveDir -Recurse -Force -ErrorAction SilentlyContinue
    Write-Step "screenshots written: $OutDir"
}
