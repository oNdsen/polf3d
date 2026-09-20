# POLF 3D - Copyright (c) 2026 oNdsen. Licensed under the MIT License, see LICENSE.

# Actors.ps1 - enemy behaviour. Enemies are driven by the state table from Defs.ps1; the
# functions here are the "think" and "action" routines those states refer to, plus the
# shared building blocks (line of sight, tile-to-tile movement, damage).

# ---------------------------------------------------------------------------------------------
# Line of sight between a point and the player. Walls block; a door blocks unless the line
# passes through the part that has already slid open.
# ---------------------------------------------------------------------------------------------
# ... or, given a second point, to that (a hacked turret looking for a target).
function Test-LineToPlayer([double]$X1, [double]$Y1, [double]$X2 = [double]::NaN, [double]$Y2 = [double]::NaN) {
    if ([double]::IsNaN($X2)) { $x2 = $script:P.X; $y2 = $script:P.Y } else { $x2 = $X2; $y2 = $Y2 }
    $dx = $x2 - $X1; $dy = $y2 - $Y1
    [int]$mx = [Math]::Floor($X1); [int]$my = [Math]::Floor($Y1)
    [int]$ex = [Math]::Floor($x2); [int]$ey = [Math]::Floor($y2)
    if ($mx -eq $ex -and $my -eq $ey) { return $true }

    $ddx = if ($dx -eq 0) { 1e30 } else { [Math]::Abs(1.0 / $dx) }
    $ddy = if ($dy -eq 0) { 1e30 } else { [Math]::Abs(1.0 / $dy) }
    if ($dx -lt 0) { $sx = -1; $sdx = ($X1 - $mx) * $ddx } else { $sx = 1; $sdx = ($mx + 1.0 - $X1) * $ddx }
    if ($dy -lt 0) { $sy = -1; $sdy = ($Y1 - $my) * $ddy } else { $sy = 1; $sdy = ($my + 1.0 - $Y1) * $ddy }
    $w = $script:MapW; $tiles = $script:Tiles

    for ($guard = 0; $guard -lt 200; $guard++) {
        if ($sdx -lt $sdy) { $t = $sdx; $sdx += $ddx; $mx += $sx; $side = 0 } else { $t = $sdy; $sdy += $ddy; $my += $sy; $side = 1 }
        if ($mx -eq $ex -and $my -eq $ey) { return $true }
        $tile = $tiles[$my * $w + $mx]
        if ($tile -eq 0) { continue }
        if ($script:IsWindow[$my * $w + $mx]) { continue }                        # windows do not block the view
        if ($tile -lt $script:TILE_DOOR_BASE -or $tile -ge $script:TILE_PUSHWALL) { return $false }

        $d = $script:Doors[$tile - $script:TILE_DOOR_BASE]
        if ($d.Open -le 0) { return $false }
        if ($d.Vertical) {
            if ($side -ne 0) { return $false }
            $cross = $Y1 + ($t + 0.5 * $ddx) * $dy - $my
        }
        else {
            if ($side -ne 1) { return $false }
            $cross = $X1 + ($t + 0.5 * $ddy) * $dx - $mx
        }
        if ($cross -lt 0 -or $cross -ge 1) { continue }        # leaves the tile before reaching the door leaf
        if ($cross -ge $d.Open) { return $false }
    }
    $false
}

# ---------------------------------------------------------------------------------------------
# Perception
# ---------------------------------------------------------------------------------------------
function Test-Sight([Actor]$a) {
    if (-not $script:AreaByPlayer[$a.Area]) { return $false }
    $dx = $script:P.X - $a.X; $dy = $script:P.Y - $a.Y
    $near = if ($script:P.Sneaking) { 0.7 } else { 1.5 }                                # a sneaking player can get right behind them
    if ([Math]::Abs($dx) -lt $near -and [Math]::Abs($dy) -lt $near) { return $true }     # too close to miss
    # in a dark room nobody sees further than three and a half tiles - unless the player carries a light around
    if (-not $script:P.Light -and $dx * $dx + $dy * $dy -gt 12.25 -and ($script:Stats.PowerOut -gt 0 -or ($script:P.Area -ge 0 -and $script:DarkArea[$script:P.Area]))) { return $false }
    switch ($a.Dir) {                                                                  # looking the other way?
        0 { if ($dx -lt 0) { return $false } }
        2 { if ($dy -gt 0) { return $false } }
        4 { if ($dx -gt 0) { return $false } }
        6 { if ($dy -lt 0) { return $false } }
    }
    Test-LineToPlayer $a.X $a.Y
}

# Footsteps and creaking doors: heard within $script:StepNoise tiles (sneaking makes none).
function Test-Hearing([Actor]$a) {
    $r = $script:StepNoise
    $r -gt 0 -and [Math]::Abs($script:P.X - $a.X) -le $r -and [Math]::Abs($script:P.Y - $a.Y) -le $r
}

# Gunfire this frame: heard in every room connected to the player's - up to a distance that depends on the difficulty.
function Test-Gunfire([Actor]$a) {
    if (-not $script:MadeNoise) { return $false }
    $r = $script:Difficulties[$script:Difficulty].Hear * (Get-Policy).Hear      # a nervous house listens harder
    [Math]::Abs($script:P.X - $a.X) -le $r -and [Math]::Abs($script:P.Y - $a.Y) -le $r
}

function Start-Attack([Actor]$a) {
    if (-not $script:Predicting) { $script:Run.Alerts++ }
    if (-not $script:BossNames.ContainsKey($a.Kind)) { Add-PolicyHeat 7 }      # being seen makes the whole house more nervous
    if (-not $script:Predicting -and -not $script:PolicyQuiet) { Reset-Streak }
    $a.AlertTics = 50
    Start-Sfx (Get-AlertSound $a) $a.X $a.Y
    Set-ActorState $a "$($a.Kind).chase1"
    $a.Speed = $a.Def.Chase
    $a.AttackMode = $true
    $a.FirstAttack = $true
}

# For enemies that have not noticed the player yet. Returns $true once they switch to attack.
function Test-NoticePlayer([Actor]$a, [double]$Tics) {
    if ($a.React -gt 0) {
        $a.React -= $Tics
        if ($a.React -gt 0) { return $false }
        $a.React = 0
        Start-Attack $a
        return $true
    }
    if (-not $script:AreaByPlayer[$a.Area]) { return $false }
    if ($a.Ambush) {
        if (-not (Test-Sight $a)) { return $false }
        $a.Ambush = $false
    }
    elseif (-not (Test-Gunfire $a) -and -not (Test-Sight $a) -and -not (Test-Hearing $a)) { return $false }

    $def = $a.Def
    $a.React = ($def.ReactBase + $(if ($def.ReactDiv) { (Get-Rnd) / $def.ReactDiv } else { 0 })) * $script:Difficulties[$script:Difficulty].React * (Get-Policy).React
    $false
}

# ---------------------------------------------------------------------------------------------
# Tile-to-tile movement
# ---------------------------------------------------------------------------------------------
# 0 = free, 1 = blocked, 2 = door that still has to open (index in $script:BlockDoor)
function Get-TileBlock([int]$X, [int]$Y) {
    $idx = $Y * $script:MapW + $X
    $t = $script:Tiles[$idx]
    if ($t -ne 0) {
        if ($t -ge $script:TILE_DOOR_BASE -and $t -lt $script:TILE_PUSHWALL) {
            $di = $t - $script:TILE_DOOR_BASE
            if ($script:Doors[$di].Action -eq 'open') {
                if ($null -ne $script:ActorAt[$idx]) { return 1 }
                return 0
            }
            $script:BlockDoor = $di
            return 2
        }
        return 1
    }
    if ($script:StaticBlock[$idx]) { return 1 }
    $other = $script:ActorAt[$idx]
    if ($null -ne $other -and $other.Shootable) { return 1 }
    0
}

# Tries to start walking one tile in $a.Dir. Reserves the destination tile.
function Step-Actor([Actor]$a) {
    $dir = $a.Dir
    if ($dir -eq $script:DIR_NONE) { return $false }
    $dx = $script:DirDX[$dir]; $dy = $script:DirDY[$dir]
    $nx = $a.TX + $dx; $ny = $a.TY + $dy
    $door = -1
    if ($dx -ne 0 -and $dy -ne 0) {
        # diagonal: both neighbours must be free as well, and never through doors
        if ((Get-TileBlock $nx $ny) -ne 0) { return $false }
        if ((Get-TileBlock $nx $a.TY) -ne 0) { return $false }
        if ((Get-TileBlock $a.TX $ny) -ne 0) { return $false }
    }
    else {
        $b = Get-TileBlock $nx $ny
        if ($b -eq 1) { return $false }
        if ($b -eq 2) {
            if (-not $a.Def.Doors) { return $false }
            $door = $script:BlockDoor
            if ($script:Doors[$door].Lock -eq 4 -and -not $script:Doors[$door].Unlocked) { return $false }      # lever doors are shut for everybody
            Open-Door $door
        }
    }
    $a.TX = $nx; $a.TY = $ny
    $a.Dist = 1.0
    $a.WaitDoor = $door
    $area = $script:AreaOf[$ny * $script:MapW + $nx]
    if ($area -ge 0) { $a.Area = $area }                        # door tiles belong to no area: keep the old one
    $true
}

function Select-PathDir([Actor]$a) {
    # A blocked patrol loses its direction (Dir = none) but remembers the route in PathDir,
    # so it walks on as soon as the way is clear again.
    $dir = if ($a.Dir -ne $script:DIR_NONE) { $a.Dir } else { $a.PathDir }
    $turn = $script:TurnAt[$a.TY * $script:MapW + $a.TX]
    if ($turn -ge 0) { $dir = $turn }
    $a.Dir = $dir; $a.PathDir = $dir
    if (-not (Step-Actor $a)) { $a.Dir = $script:DIR_NONE }
}

# Head for the player: prefer the axis with the larger distance, never reverse unless stuck.
function Select-ChaseDir([Actor]$a) {
    $old = $a.Dir
    $turn = if ($old -eq $script:DIR_NONE) { $script:DIR_NONE } else { ($old + 4) % 8 }
    $dx = [Math]::Floor($script:P.X) - $a.TX
    $dy = [Math]::Floor($script:P.Y) - $a.TY
    $d1 = if ($dx -gt 0) { 0 } elseif ($dx -lt 0) { 4 } else { $script:DIR_NONE }
    $d2 = if ($dy -gt 0) { 6 } elseif ($dy -lt 0) { 2 } else { $script:DIR_NONE }
    if ([Math]::Abs($dy) -gt [Math]::Abs($dx)) { $d1, $d2 = $d2, $d1 }
    if ($d1 -eq $turn) { $d1 = $script:DIR_NONE }
    if ($d2 -eq $turn) { $d2 = $script:DIR_NONE }

    foreach ($try in $d1, $d2, $old) {
        if ($try -ne $script:DIR_NONE) { $a.Dir = $try; if (Step-Actor $a) { return } }
    }
    $search = if ((Get-Rnd) -gt 128) { 2, 0, 6, 4 } else { 4, 6, 0, 2 }
    foreach ($try in $search) {
        if ($try -ne $turn) { $a.Dir = $try; if (Step-Actor $a) { return } }
    }
    if ($turn -ne $script:DIR_NONE) { $a.Dir = $turn; if (Step-Actor $a) { return } }
    $a.Dir = $script:DIR_NONE
}

# Like chasing, but zig-zags: shuffled preference and the diagonal towards the player first.
function Select-DodgeDir([Actor]$a) {
    if ($a.FirstAttack) { $turn = $script:DIR_NONE; $a.FirstAttack = $false }      # may turn around once
    elseif ($a.Dir -eq $script:DIR_NONE) { $turn = $script:DIR_NONE }
    else { $turn = ($a.Dir + 4) % 8 }

    $dx = [Math]::Floor($script:P.X) - $a.TX
    $dy = [Math]::Floor($script:P.Y) - $a.TY
    if ($dx -gt 0) { $h1 = 0; $h2 = 4 } else { $h1 = 4; $h2 = 0 }
    if ($dy -gt 0) { $v1 = 6; $v2 = 2 } else { $v1 = 2; $v2 = 6 }
    $t1 = $h1; $t2 = $v1; $t3 = $h2; $t4 = $v2
    if ([Math]::Abs($dx) -gt [Math]::Abs($dy)) { $t1, $t2 = $t2, $t1; $t3, $t4 = $t4, $t3 }
    if ((Get-Rnd) -lt 128) { $t1, $t2 = $t2, $t1; $t3, $t4 = $t4, $t3 }

    # diagonal between the two preferred directions
    $hx = if ($dx -gt 0) { 1 } else { -1 }
    $vy = if ($dy -gt 0) { 1 } else { -1 }
    $diag = if ($hx -gt 0) { if ($vy -lt 0) { 1 } else { 7 } } else { if ($vy -lt 0) { 3 } else { 5 } }

    foreach ($try in $diag, $t1, $t2, $t3, $t4) {
        if ($try -eq $turn) { continue }
        $a.Dir = $try
        if (Step-Actor $a) { return }
    }
    if ($turn -ne $script:DIR_NONE) { $a.Dir = $turn; if (Step-Actor $a) { return } }
    $a.Dir = $script:DIR_NONE
}

# Moves along $a.Dir; refuses to walk into the player.
function Move-Actor([Actor]$a, [double]$Move) {
    $dx = $script:DirDX[$a.Dir] * $Move; $dy = $script:DirDY[$a.Dir] * $Move
    $nx = $a.X + $dx; $ny = $a.Y + $dy
    if ($script:AreaByPlayer[$a.Area]) {
        $min = $script:MIN_ACTOR_DIST
        if ([Math]::Abs($nx - $script:P.X) -lt $min -and [Math]::Abs($ny - $script:P.Y) -lt $min) { return }
    }
    $a.X = $nx; $a.Y = $ny
    $a.Dist -= $Move
}

# Shared walking loop of patrol and chase. $Select picks the next direction at tile centres.
function Invoke-Walk([Actor]$a, [double]$Tics, [string]$Select) {
    $move = $a.Speed * $Tics
    while ($move -gt 0) {
        if ($a.WaitDoor -ge 0) {
            Open-Door $a.WaitDoor
            if ($script:Doors[$a.WaitDoor].Action -ne 'open') { return }
            $a.WaitDoor = -1
        }
        if ($move -lt $a.Dist) { Move-Actor $a $move; return }

        # reached the tile centre: snap (kills rounding drift) and choose where to go next
        $a.X = $a.TX + 0.5; $a.Y = $a.TY + 0.5
        $move -= $a.Dist
        $a.Dist = 0
        switch ($Select) {
            'Path'  { Select-PathDir $a }
            'Chase' { Select-ChaseDir $a }
            'Dodge' { Select-DodgeDir $a }
            'Terminal' { Select-TerminalDir $a }
        }
        if ($a.Dir -eq $script:DIR_NONE) { return }
    }
}

# ---------------------------------------------------------------------------------------------
# Think routines (called every frame while their state is active)
# ---------------------------------------------------------------------------------------------
function Invoke-ThinkStand([Actor]$a, [double]$Tics) { $null = Test-NoticePlayer $a $Tics }

function Invoke-ThinkPath([Actor]$a, [double]$Tics) {
    if (Test-NoticePlayer $a $Tics) { return }
    if ($a.Dir -eq $script:DIR_NONE) {
        Select-PathDir $a
        if ($a.Dir -eq $script:DIR_NONE) { return }
    }
    Invoke-Walk $a $Tics 'Path'
}

function Invoke-ThinkChase([Actor]$a, [double]$Tics) {
    $dodge = $false
    if (Test-LineToPlayer $a.X $a.Y) {
        $dist = [Math]::Max([Math]::Abs([Math]::Floor($script:P.X) - $a.TX), [Math]::Abs([Math]::Floor($script:P.Y) - $a.TY))
        $chance = if ($dist -eq 0 -or ($dist -eq 1 -and $a.Dist -lt 0.25)) { 300 } else { $Tics * 16 / $dist }
        if ((Get-Rnd) -lt $chance) { Set-ActorState $a "$($a.Kind).shoot1"; return }
        $dodge = $true
    }
    $select = if ($dodge) { 'Dodge' } else { 'Chase' }
    if ($a.Dir -eq $script:DIR_NONE) {
        if ($dodge) { Select-DodgeDir $a } else { Select-ChaseDir $a }
        if ($a.Dir -eq $script:DIR_NONE) { return }
    }
    Invoke-Walk $a $Tics $select
}

function Invoke-ThinkDogChase([Actor]$a, [double]$Tics) {
    if ($a.Dir -eq $script:DIR_NONE) {
        Select-DodgeDir $a
        if ($a.Dir -eq $script:DIR_NONE) { return }
    }
    $reach = 1.0 + $a.Speed * $Tics
    if ([Math]::Abs($script:P.X - $a.X) -le $reach -and [Math]::Abs($script:P.Y - $a.Y) -le $reach -and (Test-LineToPlayer $a.X $a.Y)) {
        Set-ActorState $a "$($a.Kind).jump1"                     # the dog - and the bugs, who have learnt it from him
        return
    }
    Invoke-Walk $a $Tics 'Dodge'
}

function Invoke-ThinkBotChase([Actor]$a, [double]$Tics) {
    if ($a.Dir -eq $script:DIR_NONE) {
        Select-ChaseDir $a
        if ($a.Dir -eq $script:DIR_NONE) { return }
    }
    if ([Math]::Abs($script:P.X - $a.X) -le 1.1 -and [Math]::Abs($script:P.Y - $a.Y) -le 1.1) { Stop-Actor $a $true; return }   # close enough: boom
    Invoke-Walk $a $Tics 'Chase'
}

# ---- the engineer ------------------------------------------------------------------------------------
# Once in a while he looks around (six tiles, line of sight): a hacked sentry gun is taken back, a destroyed sentry gun
# or camera is put back on its feet, somebody wounded is patched up. Returns $true if there was something to do.
function Invoke-EngineerRepair([Actor]$a) {
    $best = $null; $bestRank = 0
    foreach ($o in $script:Actors) {
        if ($o -eq $a -or $o.Kind -in 'peer', 'whatif') { continue }
        $rank = 0
        if ($o.Kind -eq 'turret' -and $o.Hacked -and $o.Shootable) { $rank = 3 }
        elseif ($o.Kind -in 'turret', 'camera' -and $o.Corpse -and $o.State.EndsWith('.dead')) { $rank = 2 }
        elseif ($o.Shootable -and $o.Def.HP -and -not $o.Def.Inert -and -not $script:BossNames.ContainsKey($o.Kind) -and -not $o.Hacked -and $o.HP -lt 0.7 * $o.Def.HP[$script:Difficulty]) { $rank = 1 }
        if ($rank -le $bestRank) { continue }
        if (($o.X - $a.X) * ($o.X - $a.X) + ($o.Y - $a.Y) * ($o.Y - $a.Y) -gt 36 -or -not (Test-LineToPlayer $a.X $a.Y $o.X $o.Y)) { continue }
        $best = $o; $bestRank = $rank
    }
    if (-not $best) { return $false }
    $what = ''
    switch ($bestRank) {
        3 { $best.Hacked = $false; $best.AttackMode = $false; Set-ActorState $best 'turret.stand'; $what = 'has taken the sentry gun back' }
        2 {
            $idx = $best.TY * $script:MapW + $best.TX
            if ($null -ne $script:ActorAt[$idx] -or ([int][Math]::Floor($script:P.X) -eq $best.TX -and [int][Math]::Floor($script:P.Y) -eq $best.TY)) { return $false }
            $best.HP = $best.Def.HP[$script:Difficulty]; $best.Shootable = $true; $best.Corpse = $false; $best.Hacked = $false; $best.AttackMode = $false; $best.Active = $false
            Set-ActorState $best "$($best.Kind).stand"; $script:ActorAt[$idx] = $best
            $what = "has repaired the $(if ($best.Kind -eq 'turret') { 'sentry gun' } else { 'camera' })"
        }
        1 { $best.HP = [Math]::Min([int]$best.Def.HP[$script:Difficulty], $best.HP + 20) }
    }
    Add-Effect 'puff' $best.X $best.Y; Start-Sfx 'lever' $best.X $best.Y
    if ($what -and -not $script:Predicting) { Show-Message "The engineer $what" }
    $true
}

function Invoke-ThinkEngineerChase([Actor]$a, [double]$Tics) {
    $a.Cool -= $Tics
    if ($a.Cool -le 0) { $a.Cool = 90.0; if (Invoke-EngineerRepair $a) { return } }
    Invoke-ThinkChase $a $Tics
}

# ---- the auditor -------------------------------------------------------------------------------------
# How far it is from every tile to the nearest terminal (rack, desk or console), through doors. Made when first asked for.
function Get-TerminalField {
    if ($script:TerminalField) { return , $script:TerminalField }
    $w = $script:MapW; $h = $script:MapH
    $field = [int[]]::new($w * $h); for ($i = 0; $i -lt $field.Length; $i++) { $field[$i] = 9999 }
    $queue = [System.Collections.Generic.Queue[int]]::new()
    $open = {
        param([int]$i)
        $t = $script:Tiles[$i]
        if ($t -eq 0) { return -not $script:StaticBlock[$i] }
        if ($t -ge $script:TILE_DOOR_BASE -and $t -lt $script:TILE_PUSHWALL) { $d = $script:Doors[$t - $script:TILE_DOOR_BASE]; return ($d.Lock -ne 4 -or $d.Unlocked) }
        $false
    }
    foreach ($at in $script:TerminalAt.Keys) {
        foreach ($n in -1, 1, (- $w), $w) { $i = [int]$at + $n; if ($i -ge 0 -and $i -lt $field.Length -and $field[$i] -ne 0 -and (& $open $i)) { $field[$i] = 0; $queue.Enqueue($i) } }
    }
    while ($queue.Count) {
        $c = $queue.Dequeue()
        foreach ($n in -1, 1, (- $w), $w) { $i = $c + $n; if ($i -ge 0 -and $i -lt $field.Length -and $field[$i] -gt $field[$c] + 1 -and (& $open $i)) { $field[$i] = $field[$c] + 1; $queue.Enqueue($i) } }
    }
    $script:TerminalField = $field
    , $field
}

# The next step towards a terminal: the neighbour that is nearer to one.
function Select-TerminalDir([Actor]$a) {
    $field = Get-TerminalField; $w = $script:MapW
    $here = $field[$a.TY * $w + $a.TX]
    $a.Dir = $script:DIR_NONE
    foreach ($try in 0, 2, 4, 6) {
        $nx = $a.TX + $script:DirDX[$try]; $ny = $a.TY + $script:DirDY[$try]
        if ($field[$ny * $w + $nx] -lt $here) { $a.Dir = $try; if (Step-Actor $a) { return } }
    }
    $a.Dir = $script:DIR_NONE
}

# He runs for the nearest terminal ($a.VX: 1 once the report has been filed - after that he just stands there and shakes).
function Invoke-ThinkAuditorChase([Actor]$a, [double]$Tics) {
    if ($a.VX -ne 0) { return }
    $field = Get-TerminalField
    $here = $field[$a.TY * $script:MapW + $a.TX]
    if ($here -ge 9999) { return }                              # no terminal he could get to
    if ($here -eq 0 -and $a.Dist -le 0.001) {
        $a.VX = 1
        if ($script:Predicting) { return }
        $level = [Math]::Min(3, [int]$script:Stats.Policy + 1)
        $script:Stats.Heat = [Math]::Max([double]$script:Stats.Heat, [double]$script:PolicyLevels[$level].From + 5)
        Start-Sfx 'noway' $a.X $a.Y
        Show-Message 'The auditor has filed his report.'
        Add-TranscriptLine 'an auditor reached a terminal and filed his report' 'WARNING'
        return
    }
    if ($a.Dir -eq $script:DIR_NONE) { Select-TerminalDir $a; if ($a.Dir -eq $script:DIR_NONE) { return } }
    Invoke-Walk $a $Tics 'Terminal'
}

# ---- Start-Job: the drone ---------------------------------------------------------------------
# It flies - through the ventilation, so walls do not bother it - to whatever lies around in the rooms that are
# connected to the player's right now, nearest first, and picks it up. Six things or thirty seconds later it comes
# back and hovers next to the player until Receive-Job takes the load off it. What it carries is kept in
# $script:Stats.Cargo (a new array with every change), so Undo and saved games take it along.
# Fields: HP = the item it is heading for (-1: none), Cool = flying time left, Hacked = on its way back / waiting.
function Get-Drone { foreach ($a in $script:Actors) { if ($a.Kind -eq 'drone' -and $a.State -ne 'gone') { return $a } } }

function Start-Drone {
    $a = [Actor]::new()
    $a.Kind = 'drone'; $a.Def = $script:MiscDefs.drone
    $a.X = $script:P.X; $a.Y = $script:P.Y; $a.TX = [int][Math]::Floor($a.X); $a.TY = [int][Math]::Floor($a.Y)
    $a.Area = $script:P.Area; $a.Active = $true; $a.Corpse = $true; $a.Visible = $true
    $a.HP = -1; $a.Cool = $a.Def.Life
    Set-ActorState $a 'drone.fly1'
    $a.NetId = ++$script:NextNetId
    $script:Actors.Add($a)
    $script:Stats.Cargo = @()
    $a
}

function Invoke-ThinkDrone([Actor]$a, [double]$Tics) {
    $items = $script:Items; $w = $script:MapW
    if (-not $a.Hacked) {
        $a.Cool -= $Tics
        if ($a.Cool -le 0 -or @($script:Stats.Cargo).Count -ge $(if (Test-Perk 'ThreadJob') { 10 } else { $a.Def.Capacity })) { $a.Hacked = $true }
    }
    if (-not $a.Hacked -and ($a.HP -lt 0 -or $a.HP -ge $items.Count -or $items[$a.HP].Removed)) {
        $a.HP = -1; $best = 1e9
        for ($i = 0; $i -lt $items.Count; $i++) {
            $s = $items[$i]
            if ($s.Removed -or -not $script:AreaByPlayer[$script:AreaOf[$s.Y * $w + $s.X]]) { continue }
            $d = ($s.X + 0.5 - $a.X) * ($s.X + 0.5 - $a.X) + ($s.Y + 0.5 - $a.Y) * ($s.Y + 0.5 - $a.Y)
            if ($d -lt $best) { $best = $d; $a.HP = $i }
        }
        if ($a.HP -lt 0) { $a.Hacked = $true }                   # nothing left in reach
    }
    if ($a.Hacked) { $tx = $script:P.X; $ty = $script:P.Y; $stop = 0.9 } else { $tx = $items[$a.HP].X + 0.5; $ty = $items[$a.HP].Y + 0.5; $stop = 0.25 }
    $dx = $tx - $a.X; $dy = $ty - $a.Y; $len = [Math]::Sqrt($dx * $dx + $dy * $dy)
    if ($len -gt $stop) {
        $move = [Math]::Min($len - $stop + 0.01, $a.Def.Speed * $Tics * $(if ($a.Hacked) { 1.6 } else { 1.0 }) * $(if (Test-Perk 'ThreadJob') { 1.5 } else { 1.0 }))
        $a.X += $dx / $len * $move; $a.Y += $dy / $len * $move
        $a.TX = [int][Math]::Floor($a.X); $a.TY = [int][Math]::Floor($a.Y)
        return
    }
    if ($a.Hacked) { return }                                   # back home: hovering
    $items[$a.HP].Removed = $true
    $script:Stats.Cargo = @($script:Stats.Cargo) + $items[$a.HP].Item
    Start-Sfx 'pickup' $a.X $a.Y
    $a.HP = -1
}

# Receive-Job: what the drone carries lands at the player's feet - picking it up is the player's business.
function Receive-Drone {
    $cargo = @($script:Stats.Cargo)
    foreach ($name in $cargo) { Add-Item $name ([int][Math]::Floor($script:P.X)) ([int][Math]::Floor($script:P.Y)) }
    $script:Stats.Cargo = @()
    $drone = Get-Drone
    if ($drone -and $drone.Hacked) { $drone.State = 'gone' }     # the job is done and has been received: it goes away
    $cargo
}

# A camera sweeps: ahead, a quarter turn to one side, ahead, a quarter turn to the other ($a.VX counts the steps).
function Invoke-ThinkCameraStand([Actor]$a, [double]$Tics) {
    $a.Cool -= $Tics
    if ($a.Cool -le 0) {
        $a.Cool = 170.0; $a.VX = ($a.VX + 1) % 4
        $a.Dir = ($a.PathDir + (0, 2, 0, 6)[[int]$a.VX]) % 8
    }
    $null = Test-NoticePlayer $a $Tics
}

# It has seen the player: as long as it can still see them the building heats up. Three seconds without, and it goes back to sweeping.
function Invoke-ThinkCameraChase([Actor]$a, [double]$Tics) {
    if ($script:AreaByPlayer[$a.Area] -and (Test-LineToPlayer $a.X $a.Y)) { $a.Cool = 210.0; $a.AlertTics = 20; Add-PolicyHeat (0.12 * $Tics); return }
    $a.Cool -= $Tics
    if ($a.Cool -le 0) { $a.AttackMode = $false; $a.Cool = 100.0; Set-ActorState $a 'camera.stand' }
}

# A sentry gun does not walk. Its own: fires at the player when it has a line. Hacked: fires at the nearest of the others.
function Invoke-ThinkTurretChase([Actor]$a, [double]$Tics) {
    if (-not $a.Hacked) {
        if (-not $script:AreaByPlayer[$a.Area] -or -not (Test-LineToPlayer $a.X $a.Y)) { return }
        $dist = [Math]::Max(1, [Math]::Max([Math]::Abs([Math]::Floor($script:P.X) - $a.TX), [Math]::Abs([Math]::Floor($script:P.Y) - $a.TY)))
        if ($dist -le 12 -and (Get-Rnd) -lt $Tics * 16 / $dist) { Set-ActorState $a 'turret.shoot1' }
        return
    }
    $a.Cool -= $Tics
    if ($a.Cool -gt 0) { return }
    $a.Cool = 14.0                                               # looks around five times a second
    $best = $null; $bestD = 100.0                                # ten tiles
    foreach ($o in $script:Actors) {
        if (-not $o.Shootable -or $o.Hacked -or $o.Def.Inert -or $o.Kind -in 'peer', 'whatif') { continue }
        $d = ($o.X - $a.X) * ($o.X - $a.X) + ($o.Y - $a.Y) * ($o.Y - $a.Y)
        if ($d -lt $bestD -and (Test-LineToPlayer $a.X $a.Y $o.X $o.Y)) { $best = $o; $bestD = $d }
    }
    if (-not $best) { return }
    Start-Sfx 'shot_elite' $a.X $a.Y
    $a.AlertTics = 0; $a.Cool = 24.0
    Invoke-ActorDamage $best (9 + ((Get-Rnd) -band 7)) 'turret'
}

# ---------------------------------------------------------------------------------------------
# Actions (called once when their state runs out)
# ---------------------------------------------------------------------------------------------
function Invoke-ActionShoot([Actor]$a) {
    if ($a.Hacked) { return }                                   # it changed sides in the middle of a burst
    if (-not $script:AreaByPlayer[$a.Area]) { return }
    if (-not (Test-LineToPlayer $a.X $a.Y)) { return }
    Start-Sfx $a.Def.ShotSnd $a.X $a.Y
    $aim = $script:Difficulties[$script:Difficulty].Aim         # beginners are shot at by worse marksmen

    if ($a.Def.Marksman) {                                     # snipers: distance means nothing, only your speed helps
        if ((Get-Rnd) -lt $(if ($script:P.Running) { 110 } else { 225 }) * $aim) { Invoke-PlayerDamage (25 + ((Get-Rnd) -shr 3)) $a }
        return
    }
    $dist = [Math]::Max([Math]::Abs($script:P.X - $a.X), [Math]::Abs($script:P.Y - $a.Y))
    $dist = [Math]::Floor($dist / $a.Def.Accuracy)             # good marksmen "stand closer"
    $base = if ($script:P.Running) { 160 } else { 256 }        # a running target is harder to hit
    $perTile = if ($a.Visible) { 16 } else { 8 }               # ... and one who sees it coming can duck
    if ((Get-Rnd) -ge ($base - $dist * $perTile) * $aim) { return }

    $r = Get-Rnd
    $damage = if ($dist -lt 2) { 8 + ($r -shr 3) } elseif ($dist -lt 4) { $r -shr 3 } else { $r -shr 4 }      # point blank: 8..39
    Invoke-PlayerDamage $damage $a
}

function Invoke-ActionBite([Actor]$a) {
    Start-Sfx 'bite' $a.X $a.Y
    if ([Math]::Abs($script:P.X - $a.X) -gt 1.6 -or [Math]::Abs($script:P.Y - $a.Y) -gt 1.6) { return }
    if ((Get-Rnd) -lt 180 * $script:Difficulties[$script:Difficulty].Aim) { Invoke-PlayerDamage ((Get-Rnd) -shr 4) $a }
}

# Spawns a short-lived effect sprite ('blood' or 'puff').
function Add-Effect([string]$Name, [double]$X, [double]$Y) {
    $e = [Actor]::new()
    $e.Kind = 'fx'; $e.Def = $script:MiscDefs.fx
    $e.X = $X; $e.Y = $Y; $e.TX = [int][Math]::Floor($X); $e.TY = [int][Math]::Floor($Y)
    $e.Area = $script:P.Area; $e.Active = $true; $e.Corpse = $true
    Set-ActorState $e "fx.${Name}1"
    $script:NewActors.Add($e)
}

# Blood appears a little in front of the victim so it is drawn over them.
function Add-HitEffect([Actor]$a) {
    if ($a.Def.Inert -or $a.Def.Machine) { Add-Effect 'puff' $a.X $a.Y; return }
    $dx = $script:P.X - $a.X; $dy = $script:P.Y - $a.Y
    $len = [Math]::Max(0.01, [Math]::Sqrt($dx * $dx + $dy * $dy))
    Add-Effect 'blood' ($a.X + $dx / $len * 0.2) ($a.Y + $dy / $len * 0.2)
}

# Where does a bullet fired straight ahead hit a wall? Returns the point just in front of it.
function Find-WallPoint {
    $rad = $script:P.Angle * [Math]::PI / 180.0
    $dx = [Math]::Cos($rad); $dy = - [Math]::Sin($rad)
    $x = $script:P.X; $y = $script:P.Y; $w = $script:MapW
    for ($i = 0; $i -lt 400; $i++) {
        $x += $dx * 0.1; $y += $dy * 0.1
        $idx = [int][Math]::Floor($y) * $w + [int][Math]::Floor($x)
        $t = $script:Tiles[$idx]
        $open = $t -eq 0 -or $script:IsWindow[$idx] -or ($t -ge $script:TILE_DOOR_BASE -and $t -lt $script:TILE_PUSHWALL -and $script:Doors[$t - $script:TILE_DOOR_BASE].Action -eq 'open')
        if (-not $open -or $script:StaticBlock[$idx]) { return @(($x - $dx * 0.15), ($y - $dy * 0.15)) }
    }
    $null
}

# A blast: hurts the player and every shootable actor within $Radius, fading with distance.
# Exploding barrels set each other off, which is where the chain reactions come from.
function Invoke-Explosion([double]$X, [double]$Y, [double]$Radius, [double]$Damage, [Actor]$Owner) {
    Start-Sfx 'boom' $X $Y
    $script:MadeNoise = $true
    $px = $script:P.X - $X; $py = $script:P.Y - $Y
    $d = [Math]::Sqrt($px * $px + $py * $py)
    if ($d -lt $Radius) { Invoke-PlayerDamage ([int]($Damage * 0.6 * (1 - $d / $Radius))) $Owner }
    if ($script:NetLive) { Invoke-NetBlast $X $Y $Radius $Damage $Owner }      # ... and the second player
    foreach ($a in @($script:Actors)) {
        if (-not $a.Shootable -or $a -eq $Owner -or $a.Kind -eq 'peer') { continue }
        $ax = $a.X - $X; $ay = $a.Y - $Y
        $d = [Math]::Sqrt($ax * $ax + $ay * $ay)
        if ($d -lt $Radius) { Invoke-ActorDamage $a ([int]($Damage * (1 - $d / $Radius))) 'explosion' }
    }
    # cracked walls within reach come down
    $w = $script:MapW; $reach = $Radius + 0.4
    for ($ty = [int][Math]::Floor($Y - $reach); $ty -le [int][Math]::Floor($Y + $reach); $ty++) {
        for ($tx = [int][Math]::Floor($X - $reach); $tx -le [int][Math]::Floor($X + $reach); $tx++) {
            if ($tx -lt 0 -or $ty -lt 0 -or $tx -ge $w -or $ty -ge $script:MapH) { continue }
            $idx = $ty * $w + $tx
            if (-not $script:Breakable[$idx]) { continue }
            $bx = $tx + 0.5 - $X; $by = $ty + 0.5 - $Y
            if ([Math]::Sqrt($bx * $bx + $by * $by) -gt $reach) { continue }
            Set-MapTile $idx 0; $script:Breakable[$idx] = $false
            $script:Stats.Secrets++
            foreach ($o in @(-0.25, -0.2), @(0.2, 0.1), @(0.0, 0.3)) { Add-Effect 'puff' ($tx + 0.5 + $o[0]) ($ty + 0.5 + $o[1]) }
            Show-Message 'The wall crumbles!'
        }
    }
}

# The super boss launches a rocket: a separate actor that flies straight at where the player is now.
function Invoke-ActionRocket([Actor]$a) {
    if (-not $script:AreaByPlayer[$a.Area]) { return }
    $dx = $script:P.X - $a.X; $dy = $script:P.Y - $a.Y
    $len = [Math]::Sqrt($dx * $dx + $dy * $dy)
    if ($len -lt 0.01) { return }
    $spread = ($script:Rng.NextDouble() - 0.5) * 0.12
    $speed = $script:MiscDefs.rocket.Speed
    $r = [Actor]::new()
    $r.Kind = 'rocket'; $r.Def = $script:MiscDefs.rocket
    $r.X = $a.X + $dx / $len * 0.6; $r.Y = $a.Y + $dy / $len * 0.6
    $r.TX = [int][Math]::Floor($r.X); $r.TY = [int][Math]::Floor($r.Y)
    $r.VX = ($dx / $len - $dy / $len * $spread) * $speed
    $r.VY = ($dy / $len + $dx / $len * $spread) * $speed
    $r.Area = $a.Area; $r.Active = $true; $r.Corpse = $true        # "corpse": never blocks tiles or doors
    Set-ActorState $r 'rocket.fly'
    $script:NewActors.Add($r)
    Start-Sfx 'rocket' $a.X $a.Y
}

function Invoke-ThinkProjectile([Actor]$a, [double]$Tics) {
    $a.X += $a.VX * $Tics; $a.Y += $a.VY * $Tics
    $tx = [int][Math]::Floor($a.X); $ty = [int][Math]::Floor($a.Y)
    $a.TX = $tx; $a.TY = $ty
    $hitPlayer = [Math]::Abs($a.X - $script:P.X) -lt 0.55 -and [Math]::Abs($a.Y - $script:P.Y) -lt 0.55
    $t = $script:Tiles[$ty * $script:MapW + $tx]
    if ($t -eq 0 -and $script:StaticBlock[$ty * $script:MapW + $tx]) { $t = 1 }      # columns and crates make good cover
    $hitWall = $t -ne 0 -and -not ($t -ge $script:TILE_DOOR_BASE -and $t -lt $script:TILE_PUSHWALL -and $script:Doors[$t - $script:TILE_DOOR_BASE].Action -eq 'open')
    if (-not $hitPlayer -and -not $hitWall) { return }
    if ($hitWall) { $a.X -= $a.VX * $Tics; $a.Y -= $a.VY * $Tics }  # explode in front of the wall, not inside it
    # a direct hit hurts on top of the blast, which also catches bystanders and barrels
    if ($hitPlayer) { Invoke-PlayerDamage (((Get-Rnd) -shr 4) + 12) $a }
    Invoke-Explosion $a.X $a.Y 1.6 32 $a
    Set-ActorState $a 'rocket.boom1'
}

# Rockets and throwing knives of the player: fly straight, stop at the first wall or enemy.
function Invoke-ThinkPlayerProjectile([Actor]$a, [double]$Tics) {
    $travel = $a.Def.Speed * $Tics
    $steps = [int][Math]::Ceiling($travel / 0.2)
    $len = [Math]::Sqrt($a.VX * $a.VX + $a.VY * $a.VY)
    $sx = $a.VX / $len * $travel / $steps; $sy = $a.VY / $len * $travel / $steps
    $w = $script:MapW
    for ($i = 0; $i -lt $steps; $i++) {
        $a.X += $sx; $a.Y += $sy
        $idx = [int][Math]::Floor($a.Y) * $w + [int][Math]::Floor($a.X)
        $t = $script:Tiles[$idx]
        $open = ($t -eq 0 -and -not $script:StaticBlock[$idx]) -or ($t -ge $script:TILE_DOOR_BASE -and $t -lt $script:TILE_PUSHWALL -and $script:Doors[$t - $script:TILE_DOOR_BASE].Action -eq 'open')
        $victim = $null
        foreach ($o in $script:Actors) {
            if ($o.Shootable -and [Math]::Abs($o.X - $a.X) -lt 0.45 -and [Math]::Abs($o.Y - $a.Y) -lt 0.45) { $victim = $o; break }
        }
        if ($open -and -not $victim) { continue }

        $a.X -= $sx; $a.Y -= $sy                                  # impact just in front of the obstacle
        if ($a.Kind -eq 'procket') {
            $script:NetBlastByPlayer = $true                     # network games: who gets the blame
            try { Invoke-Explosion $a.X $a.Y $a.Def.BlastRadius $a.Def.BlastDamage $null } finally { $script:NetBlastByPlayer = $false }
            Set-ActorState $a 'rocket.boom1'
        }
        else {
            if ($victim) { Invoke-ActorDamage $victim (20 + ((Get-Rnd) -shr 3)) 'knife' } else { Add-Effect 'puff' $a.X $a.Y }
            $a.State = 'gone'
        }
        return
    }
    $a.TX = [int][Math]::Floor($a.X); $a.TY = [int][Math]::Floor($a.Y)
}

function Add-PlayerProjectile([string]$Kind) {
    $p = $script:P
    if ($script:NetClient) { Send-NetMessage "P|$Kind|$([Math]::Round($p.X, 3))|$([Math]::Round($p.Y, 3))|$([Math]::Round($p.Angle, 2))"; return }      # projectiles fly on the host
    $rad = $p.Angle * [Math]::PI / 180.0
    $a = [Actor]::new()
    $a.Kind = $Kind; $a.Def = $script:MiscDefs[$Kind]
    $a.VX = [Math]::Cos($rad); $a.VY = - [Math]::Sin($rad)
    $a.X = $p.X + $a.VX * 0.5; $a.Y = $p.Y + $a.VY * 0.5
    $a.TX = [int][Math]::Floor($a.X); $a.TY = [int][Math]::Floor($a.Y)
    $a.Area = $p.Area; $a.Active = $true; $a.Corpse = $true
    Set-ActorState $a "$Kind.fly"
    $script:NewActors.Add($a)
}

# Phase two of the super boss: when the machine has burnt out, its pilot climbs out of the wreck.
function Invoke-ActionSpawnPilot([Actor]$a) {
    $tx = [int][Math]::Floor($a.X); $ty = [int][Math]::Floor($a.Y)
    $pilot = New-Enemy 'pilot' $tx $ty 6 'stand'
    $pilot.Active = $true
    $script:NewActors.Add($pilot)
    Start-Attack $pilot
    Show-Message 'The pilot bails out!'
}

# THE PRINTER, after every second salvo: a paper jam. For four seconds it only blinks and takes triple damage -
# but the first three times it also finishes two print jobs ($a.VX counts the salvos, $a.VY the print runs).
function Invoke-ActionJam([Actor]$a) {
    $a.VX += 1
    if ([int]$a.VX % 2 -ne 0) { return }
    Set-ActorState $a 'uber.jam1'
    Start-Sfx 'clang' $a.X $a.Y
    Show-Message 'PAPER JAM!  Now - it takes triple damage'
    if ($a.VY -ge 3) { return }
    $a.VY += 1; $printed = 0
    foreach ($n in @(1, 0), @(-1, 0), @(0, 1), @(0, -1), @(1, 1), @(-1, -1), @(1, -1), @(-1, 1)) {
        $x = $a.TX + $n[0]; $y = $a.TY + $n[1]
        if ($printed -ge 2 -or -not (Test-TileFree $x $y) -or ([int][Math]::Floor($script:P.X) -eq $x -and [int][Math]::Floor($script:P.Y) -eq $y)) { continue }
        $job = New-Enemy 'bot' $x $y 6 'stand'
        $job.Active = $true
        $script:ActorAt[$y * $script:MapW + $x] = $job
        $script:NewActors.Add($job); $script:Stats.KillTotal++
        Start-Attack $job
        $printed++
    }
}

# BLUE SCREEN's crash: the picture tears (Render.ps1) and the player's controls hang (Update-Player). Only with a line of sight.
function Invoke-ActionGlitch([Actor]$a) {
    if ($script:NetAsPeer -or -not $script:AreaByPlayer[$a.Area] -or -not (Test-LineToPlayer $a.X $a.Y)) { return }
    $script:Stats.Freeze = 50.0
    if ($script:Predicting) { return }
    $script:GlitchTics = 110.0
    Start-Sfx 'noway' $a.X $a.Y
    Show-Message ':(   Your admin ran into a problem and needs to restart.   0 % complete'
}

# ... and its end: everything that depended on it stands still for twenty seconds.
function Invoke-ActionHalt([Actor]$a) {
    foreach ($o in $script:Actors) { if ($o.Shootable -and -not $o.Def.Inert -and $o.Kind -notin 'peer', 'whatif') { $o.Stun = 1400.0 } }
    Show-Message 'The system has halted. Whatever depended on it stands still.'
}

# ---------------------------------------------------------------------------------------------
# State machine driver
# ---------------------------------------------------------------------------------------------
function Set-ActorState([Actor]$a, [string]$Name) {
    $a.State = $Name
    $a.Tics = $script:States[$Name].Tics
}

function Invoke-Think([Actor]$a, [string]$Think, [double]$Tics) {
    switch ($Think) {
        'Stand'    { Invoke-ThinkStand $a $Tics }
        'Path'     { Invoke-ThinkPath $a $Tics }
        'Chase'    { Invoke-ThinkChase $a $Tics }
        'DogChase' { Invoke-ThinkDogChase $a $Tics }
        'BotChase' { Invoke-ThinkBotChase $a $Tics }
        'CameraStand' { Invoke-ThinkCameraStand $a $Tics }
        'CameraChase' { Invoke-ThinkCameraChase $a $Tics }
        'TurretChase' { Invoke-ThinkTurretChase $a $Tics }
        'Drone' { Invoke-ThinkDrone $a $Tics }
        'EngineerChase' { Invoke-ThinkEngineerChase $a $Tics }
        'AuditorChase' { Invoke-ThinkAuditorChase $a $Tics }
        'Projectile' { Invoke-ThinkProjectile $a $Tics }
        'PlayerProjectile' { Invoke-ThinkPlayerProjectile $a $Tics }
    }
}

function Update-Actor([Actor]$a, [double]$Tics) {
    if ($a.Corpse -and $a.State.EndsWith('.dead')) { return }
    if ($a.AlertTics -gt 0) { $a.AlertTics -= $Tics }
    if ($a.Stun -gt 0) { $a.Stun -= $Tics; return }                             # suspended from the console
    if (-not $a.Active -and -not $script:AreaByPlayer[$a.Area]) { return }      # rooms far away sleep

    $w = $script:MapW
    if (-not $a.Corpse) { $script:ActorAt[$a.TY * $w + $a.TX] = $null }

    $st = $script:States[$a.State]
    if ($st.Tics -gt 0) {
        $a.Tics -= $Tics
        while ($a.Tics -le 0) {
            switch ($st.Action) {
                'Shoot'       { Invoke-ActionShoot $a }
                'Bite'        { Invoke-ActionBite $a }
                'DeathScream' { Start-Sfx (Get-DeathSound $a) $a.X $a.Y }
                'Rocket'      { Invoke-ActionRocket $a }
                'SpawnPilot'  { Invoke-ActionSpawnPilot $a }
                'Jam'         { Invoke-ActionJam $a }
                'Glitch'      { Invoke-ActionGlitch $a }
                'Halt'        { Invoke-ActionHalt $a }
                'Explode'     { Invoke-Explosion $a.X $a.Y $a.Def.BlastRadius $a.Def.BlastDamage $a }
                'Remove'      { $a.State = 'gone'; return }
            }
            if ($a.State -eq $st.Name) { $a.State = $st.Next }               # unless the action changed it
            $st = $script:States[$a.State]
            if ($st.Tics -le 0) { $a.Tics = 0; break }
            $a.Tics += $st.Tics
        }
    }
    if ($st.Think) { Invoke-Think $a $st.Think $Tics }

    if (-not $a.Corpse) { $script:ActorAt[$a.TY * $w + $a.TX] = $a }
}

# ---------------------------------------------------------------------------------------------
# Damage dealt BY the player
# ---------------------------------------------------------------------------------------------
# Source: bullet | knife | beam | blast | explosion
function Invoke-ActorDamage([Actor]$a, [int]$Damage, [string]$Source = 'bullet') {
    if ($script:NetLive) {
        if ($a.Kind -eq 'peer') { Invoke-PeerDamage $a $Damage $Source; return }
        if ($script:NetClient) { Send-NetMessage "D|$($a.NetId)|$Damage|$Source"; return }       # the host decides what that does
    }
    if ($a.Def.Inert) {                                       # barrels and the like: no AI, no noise, just hit points
        if ($Source -in 'bullet', 'knife', 'beam') { Add-HitEffect $a }
        $a.HP -= $Damage
        if ($a.HP -le 0) { Stop-Actor $a }
        return
    }
    if ($Source -ne 'knife') { $script:MadeNoise = $true }     # blades are silent: nobody else wakes up
    if ($Source -eq 'bullet' -and (Test-Signed 'ArmorPiercing')) { $Damage = [int]($Damage * 1.5) }
    if ($a.Def.Shield -and $Source -in 'bullet', 'knife' -and (Test-ShieldBlocks $a) -and -not ($Source -eq 'bullet' -and (Test-Signed 'ArmorPiercing'))) {        # flames lick around it
        Add-Effect 'puff' ($a.X + ($script:P.X - $a.X) * 0.15) ($a.Y + ($script:P.Y - $a.Y) * 0.15)
        Start-Sfx 'clang' $a.X $a.Y
        if (-not $a.AttackMode) { $a.React = 0; Start-Attack $a }
        return
    }
    if ($Source -in 'bullet', 'knife', 'beam') { Add-HitEffect $a }
    if (-not $a.AttackMode) { $Damage *= $(if (Test-Perk 'Pester') { 3 } else { 2 }) }      # caught off guard: double damage
    if ($a.State.StartsWith('uber.jam')) { $Damage *= 3 }     # THE PRINTER's paper jam: the one moment it is soft
    if ($script:P.SudoTics -gt 0) { $Damage *= 2 }            # sudo: elevated damage
    if ($script:OneHitKill) { $Damage = [Math]::Max($Damage, $a.HP) }
    $a.HP -= $Damage
    if ($a.HP -le 0) { $script:KillCause = $Source; Stop-Actor $a; $script:KillCause = $null; return }
    if (-not $a.AttackMode) { $a.React = 0; Start-Attack $a }
    if ($a.Def.Pain) { Set-ActorState $a "$($a.Kind).pain" }
}

# The shield covers the front (about 140 degrees) - unless it is lowered for shooting.
function Test-ShieldBlocks([Actor]$a) {
    if ($a.State -like '*.shoot*') { return $false }
    if ($a.Dir -eq $script:DIR_NONE) { return $true }
    $toPlayer = [Math]::Atan2(- ($script:P.Y - $a.Y), $script:P.X - $a.X) * 180.0 / [Math]::PI
    $diff = [Math]::Abs((($toPlayer - $a.Dir * 45.0 + 540.0) % 360.0) - 180.0)
    $diff -lt 70
}

function Stop-Actor([Actor]$a, [bool]$NoScore = $false) {     # killed
    $tx = [int][Math]::Floor($a.X); $ty = [int][Math]::Floor($a.Y)
    if ($a.Def.Inert) {
        Set-ActorState $a "$($a.Kind).fuse"
        $a.Shootable = $false; $a.Corpse = $true; $a.Active = $true
        $idx = $a.TY * $script:MapW + $a.TX
        if ($script:ActorAt[$idx] -eq $a) { $script:ActorAt[$idx] = $null }
        return
    }
    if (-not $NoScore) { Add-Score $a.Def.Points }
    if (-not $script:NetAsPeer) {
        $cause = switch ($script:KillCause) { 'explosion' { 'an explosion' } 'console' { 'the console' } 'trap' { 'a crusher' } 'turret' { 'a turret that had changed sides' } default { "the $($script:Weapons[$script:P.Weapon].Name.ToLower())" } }
        Add-TranscriptLine "Stop-Enemy -Kind $($a.Kind)$(if (-not $a.AttackMode) { ' -Unaware' })   # with $cause"
    }
    Set-ActorState $a "$($a.Kind).die1"
    if (-not $NoScore) { Update-Streak (-not $a.AttackMode) }
    foreach ($drop in @(Get-Loot $a)) { switch ($drop) {
        'key_gold'     {
            # the commander's gold key - but only where it opens something: a floor without a gold lock (or a player who
            # has the key already) gets his strongbox instead. A key for a door that does not exist only confuses.
            $locked = $false
            foreach ($d in $script:Doors) { if ($d.Lock -eq 1) { $locked = $true; break } }
            if ($locked -and -not $script:P.KeyGold) { Add-Item 'key_gold' $tx $ty } else { Add-Item 'chest' $tx $ty; $script:Stats.TreasureTotal++ }
        }
        'crown'        { Add-Item 'crown' $tx $ty; $script:Stats.TreasureTotal++ }
        'mgun_or_clip' { if (-not $script:P.Owned[2]) { Add-Item 'mgun' $tx $ty } else { Add-Item 'clip_small' $tx $ty } }
        default        { Add-Item $drop $tx $ty }
    } }
    if (-not $a.Def.NoCount) { $script:Stats.Kills++ }
    if ($a.Def.SplitInto -and $script:KillCause -eq 'explosion') {
        # a bug that has been blown up: two smaller ones crawl out of what is left
        $made = 0
        foreach ($n in @(1, 0), @(-1, 0), @(0, 1), @(0, -1), @(1, 1), @(-1, -1), @(1, -1), @(-1, 1)) {
            $x = $a.TX + $n[0]; $y = $a.TY + $n[1]
            if ($made -ge 2 -or -not (Test-TileFree $x $y) -or ([int][Math]::Floor($script:P.X) -eq $x -and [int][Math]::Floor($script:P.Y) -eq $y)) { continue }
            $small = New-Enemy $a.Def.SplitInto $x $y 6 'stand'
            $small.Active = $true; $script:ActorAt[$y * $script:MapW + $x] = $small
            $script:NewActors.Add($small); $script:Stats.KillTotal++
            $script:PolicyQuiet = $true; Start-Attack $small; $script:PolicyQuiet = $false
            $made++
        }
        if ($made -and -not $script:Predicting) { Show-Message 'Fix one, get two.' }
    }
    if (-not $script:NetAsPeer) { Add-Privilege 6 }
    $a.Shootable = $false
    $a.Corpse = $true
    $a.Active = $true
    $idx = $a.TY * $script:MapW + $a.TX
    if ($script:ActorAt[$idx] -eq $a) { $script:ActorAt[$idx] = $null }
}

# Runs every actor once. Actors born during the frame (rockets, the pilot) join afterwards,
# finished ones (exploded rockets) are dropped.
function Update-Actors([double]$Tics) {
    if ($script:NetLive) {
        # hosting a network game: some actors deal with the remote player instead (see Network.ps1)
        $script:NetFrame++
        foreach ($a in $script:Actors) {
            $slot = Get-NetTargetSlot $a
            if ($slot -gt 0) { Enter-PeerContext $slot; try { Update-Actor $a $Tics } finally { Exit-PeerContext } }
            else { Update-Actor $a $Tics }
        }
    }
    else { foreach ($a in $script:Actors) { Update-Actor $a $Tics } }
    if ($script:NewActors.Count) {
        foreach ($n in $script:NewActors) { $n.NetId = ++$script:NextNetId; $script:Actors.Add($n) }
        $script:NewActors.Clear()
    }
    for ($i = $script:Actors.Count - 1; $i -ge 0; $i--) {
        if ($script:Actors[$i].State -eq 'gone') {
            if ($script:NetLive) { $script:Net.Gone.Add($script:Actors[$i].NetId) }
            $script:Actors.RemoveAt($i)
        }
    }
}
