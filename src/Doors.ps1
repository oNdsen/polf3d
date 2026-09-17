# POLF 3D - Copyright (c) 2026 oNdsen. Licensed under the MIT License, see LICENSE.

# Doors.ps1 - sliding doors, the area graph they control, and secret push-walls.

# ---- areas ----------------------------------------------------------------------------------
# Two areas are connected while at least one door between them is not fully closed. Enemies
# only hear, see and think if their area is connected to the player's.
function Update-AreaByPlayer {
    $n = $script:AreaCount
    $reach = [bool[]]::new($n)
    $starts = @($script:P.Area)
    if ($script:NetLive -and -not $script:NetClient) { $starts += $script:Net.Home.Area, $script:Net.Proxy.Area }      # the host thinks for both players
    $queue = [System.Collections.Generic.Queue[int]]::new()
    foreach ($start in $starts) { if ($start -ge 0 -and -not $reach[$start]) { $reach[$start] = $true; $queue.Enqueue($start) } }
    if ($queue.Count) {
        while ($queue.Count) {
            $a = $queue.Dequeue()
            for ($b = 0; $b -lt $n; $b++) {
                if (-not $reach[$b] -and $script:AreaConnect[$a, $b] -gt 0) { $reach[$b] = $true; $queue.Enqueue($b) }
            }
        }
    }
    $script:AreaByPlayer = $reach
}

# ---- doors ----------------------------------------------------------------------------------
function Open-Door([int]$Index) {
    $d = $script:Doors[$Index]
    if ($d.Action -eq 'open') { $d.Timer = 0 }
    elseif ($d.Action -ne 'opening') { $d.Action = 'opening' }
}

function Test-PlayerInDoorway([Door]$d) {
    $reach = 0.5 + $script:PLAYER_RADIUS
    ([Math]::Abs($script:P.X - ($d.X + 0.5)) -lt $reach) -and ([Math]::Abs($script:P.Y - ($d.Y + 0.5)) -lt $reach)
}

function Close-Door([int]$Index) {
    $d = $script:Doors[$Index]
    $idx = $d.Y * $script:MapW + $d.X
    if ($null -ne $script:ActorAt[$idx]) { return }          # never close on somebody
    if (Test-PlayerInDoorway $d) { return }
    foreach ($a in $script:Actors) {                           # ... or on somebody still leaving
        if ($a.Corpse) { continue }
        if ([Math]::Abs($a.X - ($d.X + 0.5)) -lt 0.9 -and [Math]::Abs($a.Y - ($d.Y + 0.5)) -lt 0.9) { return }
    }
    if ($script:AreaByPlayer[$d.Area1] -or $script:AreaByPlayer[$d.Area2]) { Start-Sfx 'door_close' }
    $d.Action = 'closing'
}

# The player pressed "use" on a door.
function Invoke-DoorUse([int]$Index) {
    $d = $script:Doors[$Index]
    if ($d.Lock -eq 4 -and -not $d.Unlocked) { Start-Sfx 'noway'; Show-Message 'This door is opened from somewhere else'; return }
    if ($d.Lock -eq 1 -and -not $script:P.KeyGold)   { Start-Sfx 'noway'; Show-Message 'Locked - you need the gold key';   return }
    if ($d.Lock -eq 2 -and -not $script:P.KeySilver) { Start-Sfx 'noway'; Show-Message 'Locked - you need the silver key'; return }
    if ($script:NOISE_DOOR -gt $script:StepNoise) { $script:StepNoise = $script:NOISE_DOOR }      # doors creak
    if ($d.Action -in 'closed', 'closing') { Open-Door $Index } else { Close-Door $Index }
}

function Update-Doors([double]$Tics) {
    $step = $Tics / $script:DOOR_OPEN_TICS
    for ($i = 0; $i -lt $script:Doors.Count; $i++) {
        $d = $script:Doors[$i]
        switch ($d.Action) {
            'open' {
                if ($d.Lock -eq 4) { break }                              # lever doors stay open for good
                $d.Timer += $Tics
                if ($d.Timer -ge $script:DOOR_STAY_TICS) { Close-Door $i }
            }
            'opening' {
                if ($d.Open -le 0) {
                    # first movement: from now on sound and sight pass through
                    $script:AreaConnect[$d.Area1, $d.Area2]++
                    $script:AreaConnect[$d.Area2, $d.Area1]++
                    Update-AreaByPlayer
                    if ($script:AreaByPlayer[$d.Area1]) { Start-Sfx 'door_open' }
                }
                $d.Open += $step
                if ($d.Open -ge 1) { $d.Open = 1; $d.Timer = 0; $d.Action = 'open' }
            }
            'closing' {
                if ($null -ne $script:ActorAt[$d.Y * $script:MapW + $d.X] -or (Test-PlayerInDoorway $d)) { Open-Door $i; break }
                $d.Open -= $step
                if ($d.Open -le 0) {
                    $d.Open = 0; $d.Action = 'closed'
                    $script:AreaConnect[$d.Area1, $d.Area2]--
                    $script:AreaConnect[$d.Area2, $d.Area1]--
                    Update-AreaByPlayer
                }
            }
        }
    }
}

# The player pulled a wall lever: every remote door on its channel opens and stays open.
function Invoke-Lever([int]$TileIndex) {
    $channel = $script:LeverAt[$TileIndex]
    Set-MapTile $TileIndex $script:TEX_LEVER_ON
    Start-Sfx 'lever'
    $count = 0
    for ($i = 0; $i -lt $script:Doors.Count; $i++) {
        $d = $script:Doors[$i]
        if ($d.Lock -eq 4 -and $d.Channel -eq $channel) { $d.Unlocked = $true; Open-Door $i; $count++ }
    }
    Show-Message $(if ($count) { 'A door opens somewhere ...' } else { 'Nothing happens' })
}

# A wall changes its face or disappears (switches, levers, cracked walls). In a network game the guest is told.
function Set-MapTile([int]$Index, [int]$Value) {
    $script:Tiles[$Index] = $Value
    if ($script:NetLive -and -not $script:NetClient) { Send-NetMessage "T|$Index|$Value" }
}

# ---- push-walls -------------------------------------------------------------------------------
function Test-TileFree([int]$X, [int]$Y) {
    if ($X -lt 0 -or $Y -lt 0 -or $X -ge $script:MapW -or $Y -ge $script:MapH) { return $false }
    $idx = $Y * $script:MapW + $X
    ($script:Tiles[$idx] -eq 0) -and (-not $script:StaticBlock[$idx]) -and ($null -eq $script:ActorAt[$idx])
}

function Start-PushWall([int]$X, [int]$Y, [int]$DX, [int]$DY) {
    $pw = $script:PW
    if ($pw.Active) { return }                                 # only one wall moves at a time
    $idx = $Y * $script:MapW + $X
    $tex = $script:PushTex[$idx]
    if ($tex -eq 0) { return }
    if (-not (Test-TileFree ($X + $DX) ($Y + $DY))) { Start-Sfx 'noway'; return }
    if ($script:NetLive -and -not $script:NetClient) { Send-NetMessage "W|$X|$Y|$DX|$DY" }      # the guest moves his copy of the wall himself

    $script:Tiles[($Y + $DY) * $script:MapW + ($X + $DX)] = $tex   # reserve the destination right away
    $script:Tiles[$idx] = $script:TILE_PUSHWALL
    $script:PushTex[$idx] = 0
    $pw.Active = $true; $pw.X = $X; $pw.Y = $Y; $pw.DX = $DX; $pw.DY = $DY; $pw.Pos = 0.0; $pw.Moved = 0; $pw.TexId = $tex
    $script:Stats.Secrets++
    Start-Sfx 'pushwall'
    Show-Message 'A secret passage!'
}

function Update-PushWall([double]$Tics) {
    $pw = $script:PW
    if (-not $pw.Active) { return }
    $pw.Pos += $Tics / $script:PUSHWALL_TICS_PER_TILE
    if ($pw.Pos -lt 1) { return }

    # crossed into the next tile: the old one becomes walkable floor
    $w = $script:MapW
    $script:Tiles[$pw.Y * $w + $pw.X] = 0
    $pw.X += $pw.DX; $pw.Y += $pw.DY; $pw.Moved++
    $nx = $pw.X + $pw.DX; $ny = $pw.Y + $pw.DY
    if ($pw.Moved -ge 2 -or -not (Test-TileFree $nx $ny)) {
        $pw.Active = $false                                     # stays here as an ordinary wall
        return
    }
    $script:Tiles[$ny * $w + $nx] = $pw.TexId
    $script:Tiles[$pw.Y * $w + $pw.X] = $script:TILE_PUSHWALL
    $pw.Pos -= 1
}
