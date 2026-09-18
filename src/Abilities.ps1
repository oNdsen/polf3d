# POLF 3D - Copyright (c) 2026 oNdsen. Licensed under the MIT License, see LICENSE.

# Abilities.ps1 - PowerShell's common parameters as powers. They are paid for with PRIVILEGE, which
# trickles back by itself and comes in chunks with every kill.
#
#   Z  -WhatIf    time stands still and everybody's next two seconds are shown as ghosts
#   X  -Confirm   the world drops to a third of its speed; you do not
#   V  -Verbose   writes everybody's name and hit points into the view - through walls
#   F  -Force     kicks in the door in front of you (locked or not), cracked walls, and whoever stands there
#   R  Undo       Restore-Checkpoint: the last five seconds never happened
#
# -WhatIf and Undo need to copy the world and put it back. Saved games do that through JSON, which is
# far too slow to do twice a second - so there is a second, in-memory kind of snapshot here.

$script:PRIVILEGE_MAX = 100
$script:Abilities = @(
    $null
    @{ Id = 1; Name = '-WhatIf';  Key = 'Z'; Cost = 25 }
    @{ Id = 2; Name = '-Confirm'; Key = 'X'; Cost = 30 }
    @{ Id = 3; Name = '-Verbose'; Key = 'V'; Cost = 15 }
    @{ Id = 4; Name = '-Force';   Key = 'F'; Cost = 35 }
    @{ Id = 5; Name = 'Undo';     Key = 'R'; Cost = 60 }
)
$script:WhatIfTics = 0.0; $script:ConfirmTics = 0.0; $script:VerboseTics = 0.0
$script:Predicting = $false
$script:Checkpoints = [System.Collections.Generic.List[object]]::new()
$script:CheckpointTics = 0.0
$script:ActorProps = $null

function Reset-Abilities {
    Stop-WhatIf
    $script:WhatIfTics = 0.0; $script:ConfirmTics = 0.0; $script:VerboseTics = 0.0; $script:UndoFlash = 0.0
    $script:Checkpoints.Clear(); $script:CheckpointTics = 0.0
}

function Add-Privilege([double]$Points) {
    $p = $script:P
    $before = [int]$p.Privilege
    $p.Privilege = [Math]::Max(0.0, [Math]::Min([double]$script:PRIVILEGE_MAX, [double]$p.Privilege + $Points))
}

# ---------------------------------------------------------------------------------------------
# Snapshots of everything that moves
# ---------------------------------------------------------------------------------------------
function Copy-Actor([Actor]$a) {
    if (-not $script:ActorProps) { $script:ActorProps = @([Actor].GetProperties().Name) }
    $c = [Actor]::new()
    foreach ($n in $script:ActorProps) { $c.$n = $a.$n }
    $c
}

function New-WorldSnapshot {
    $p = $script:P.Clone(); $p.Owned = $script:P.Owned.Clone()
    $actors = [System.Collections.Generic.List[object]]::new($script:Actors.Count)
    $killer = -1
    for ($i = 0; $i -lt $script:Actors.Count; $i++) {
        $a = $script:Actors[$i]
        if ($a -eq $script:Killer) { $killer = $i }
        # the dead never change again: no need to copy them
        $actors.Add($(if ($a.Corpse -and $a.State.EndsWith('.dead')) { $a } else { Copy-Actor $a }))
    }
    @{
        P = $p; Stats = $script:Stats.Clone(); PW = $script:PW.Clone()
        Tiles = $script:Tiles.Clone(); PushTex = $script:PushTex.Clone(); Breakable = $script:Breakable.Clone(); StaticBlock = $script:StaticBlock.Clone()
        AreaConnect = $script:AreaConnect.Clone()
        Doors = @(foreach ($d in $script:Doors) { , @($d.Action, $d.Open, $d.Timer, $d.Unlocked, $d.Lock, $d.TexId, $d.Jam) })
        Traps = @(foreach ($t in $script:Traps) { , @($t.Phase, $t.State, $t.Hurt, $t.Static.Sprite, [bool]$t.Disabled) })
        Items = $script:Items.ToArray(); Statics = $script:Statics.ToArray()          # what lies around (enemies drop things) ...
        Removed = @(foreach ($item in $script:Items) { [bool]$item.Removed })              # ... and what has been picked up
        Actors = $actors; Killer = $killer; NextNetId = $script:NextNetId
        TeleLock = $script:TeleLock; LevelDone = $script:LevelDone; PlayerDied = $script:PlayerDied; SecretExit = $script:SecretExit
    }
}

# Puts a snapshot back. The snapshot is used up by this: its objects become the live ones.
function Restore-WorldSnapshot([hashtable]$s) {
    $script:P = $s.P; $script:Stats = $s.Stats; $script:PW = $s.PW
    $script:Tiles = $s.Tiles; $script:PushTex = $s.PushTex; $script:Breakable = $s.Breakable; $script:StaticBlock = $s.StaticBlock
    $script:AreaConnect = $s.AreaConnect
    for ($i = 0; $i -lt $script:Doors.Count; $i++) {
        $d = $script:Doors[$i]; $v = $s.Doors[$i]
        $d.Action = $v[0]; $d.Open = $v[1]; $d.Timer = $v[2]; $d.Unlocked = $v[3]; $d.Lock = $v[4]; $d.TexId = $v[5]; $d.Jam = $v[6]
    }
    for ($i = 0; $i -lt $script:Traps.Count; $i++) {
        $t = $script:Traps[$i]; $v = $s.Traps[$i]
        $t.Phase = $v[0]; $t.State = $v[1]; $t.Hurt = $v[2]; $t.Static.Sprite = $v[3]; $t.Disabled = $v[4]
    }
    # whatever has been dropped since then was never dropped
    $script:Items.Clear(); $script:Items.AddRange($s.Items)
    $script:Statics.Clear(); $script:Statics.AddRange($s.Statics)
    for ($i = 0; $i -lt $s.Items.Count; $i++) { $s.Items[$i].Removed = $s.Removed[$i] }

    $script:Actors = $s.Actors
    $script:NewActors.Clear()
    [Array]::Clear($script:ActorAt, 0, $script:ActorAt.Length)
    $w = $script:MapW
    foreach ($a in $script:Actors) { if (-not $a.Corpse) { $script:ActorAt[$a.TY * $w + $a.TX] = $a } }
    $script:Killer = if ($s.Killer -ge 0) { $script:Actors[$s.Killer] } else { $null }
    $script:NextNetId = $s.NextNetId
    $script:TeleLock = $s.TeleLock; $script:LevelDone = $s.LevelDone; $script:PlayerDied = $s.PlayerDied; $script:SecretExit = $s.SecretExit
    Update-AreaByPlayer
    $script:MapBmp = $null; $script:HudDirty = $true
}

# Twice a second the world is copied, so that Undo has something to go back to.
function Update-Checkpoints([double]$Tics) {
    $script:CheckpointTics += $Tics
    if ($script:CheckpointTics -lt 35) { return }
    $script:CheckpointTics = 0.0
    $script:Checkpoints.Add((New-WorldSnapshot))
    if ($script:Checkpoints.Count -gt 11) { $script:Checkpoints.RemoveAt(0) }
}

# ---------------------------------------------------------------------------------------------
# The abilities
# ---------------------------------------------------------------------------------------------
function Invoke-Ability([int]$Id) {
    $ab = $script:Abilities[$Id]; $p = $script:P
    if (-not $ab -or $p.Health -le 0) { return }
    if ($Id -eq 1 -and $script:WhatIfTics -gt 0) { Stop-WhatIf; return }               # pressing it again ends it
    if ($script:NetLive -and $Id -ne 3) { Show-Message "$($ab.Name) does not work in a shared world"; Start-Sfx 'noway'; return }
    if ($p.Privilege -lt $ab.Cost -and -not $script:InfiniteAmmo) { Show-Message "$($ab.Name) needs $($ab.Cost) privilege - you have $([int]$p.Privilege)"; Start-Sfx 'noway'; return }
    $ok = switch ($Id) {
        1 { Start-WhatIf }
        2 { $script:ConfirmTics = 350.0; Start-Sfx 'sudo'; Show-Message '-Confirm: are you sure? Take your time.'; $true }
        3 { $script:VerboseTics = 700.0; Start-Sfx 'key'; Show-Message '-Verbose'; $true }
        4 { Invoke-Force }
        5 { Undo-World }
    }
    if ($ok) { $script:Run.Powers++; Add-TranscriptLine "Invoke-Ability $($ab.Name)" }
    if ($ok -and -not $script:InfiniteAmmo) { Add-Privilege (- $ab.Cost) }
}

# -WhatIf: run the world ahead for two seconds with a throw-away random generator, note where everybody
# goes, put the world back - and mark the way with ghosts.
function Start-WhatIf {
    $snapshot = New-WorldSnapshot
    $count = $script:Actors.Count
    $paths = [object[]]::new($count); $threat = [bool[]]::new($count)
    for ($i = 0; $i -lt $count; $i++) { $paths[$i] = [System.Collections.Generic.List[double]]::new() }
    $rng = $script:Rng; $script:Rng = [System.Random]::new(4711)
    $script:Predicting = $true
    try {
        for ($step = 0; $step -lt 14; $step++) {
            Update-Doors 10.0; Update-Actors 10.0
            for ($i = 0; $i -lt $count -and $i -lt $script:Actors.Count; $i++) {
                $a = $script:Actors[$i]
                if (-not $a.Shootable -or $a.Def.Inert) { continue }
                if ($a.State -like '*.shoot*' -or $a.State -like '*.jump*') { $threat[$i] = $true }
                $paths[$i].Add($a.X); $paths[$i].Add($a.Y)
            }
        }
    }
    finally { $script:Predicting = $false; $script:Rng = $rng; Restore-WorldSnapshot $snapshot }

    $script:WhatIfMarks = [System.Collections.Generic.List[object]]::new()
    for ($i = 0; $i -lt $count; $i++) {
        $a = $script:Actors[$i]; $pts = $paths[$i]
        if ($pts.Count -lt 2) { continue }
        $lastX = $a.X; $lastY = $a.Y
        for ($k = 0; $k -lt $pts.Count; $k += 2) {
            $final = $k -ge $pts.Count - 2
            $far = [Math]::Abs($pts[$k] - $lastX) + [Math]::Abs($pts[$k + 1] - $lastY)
            if (-not $final -and $far -lt 0.45) { continue }
            if ($final -and -not $threat[$i] -and [Math]::Abs($pts[$k] - $a.X) + [Math]::Abs($pts[$k + 1] - $a.Y) -lt 0.3) { continue }      # he is not going anywhere
            $m = [Actor]::new()
            $m.Kind = 'whatif'; $m.Def = $script:MiscDefs.fx; $m.Corpse = $true; $m.Active = $true
            $m.State = if (-not $final) { 'whatif.dot' } elseif ($threat[$i]) { 'whatif.threat' } else { 'whatif.ghost' }
            $m.X = $pts[$k]; $m.Y = $pts[$k + 1]; $m.TX = [int][Math]::Floor($m.X); $m.TY = [int][Math]::Floor($m.Y)
            $script:Actors.Add($m); $script:WhatIfMarks.Add($m)
            $lastX = $m.X; $lastY = $m.Y
        }
    }
    $script:WhatIfTics = 280.0
    Start-Sfx 'teleport'
    Show-Message "What if: the next two seconds ($(@($threat -eq $true).Count) of them will open fire)"
    $true
}

function Stop-WhatIf {
    if ($script:WhatIfMarks) { foreach ($m in $script:WhatIfMarks) { $null = $script:Actors.Remove($m) } }
    $script:WhatIfMarks = $null; $script:WhatIfTics = 0.0
}

# -Force: the tile straight ahead gives way, and so does anybody standing close in front.
function Invoke-Force {
    $p = $script:P; $w = $script:MapW
    $quad = [int][Math]::Floor((($p.Angle + 45.0) % 360.0) / 90.0) % 4
    $dx = (1, 0, -1, 0)[$quad]; $dy = (0, -1, 0, 1)[$quad]
    $tx = [int][Math]::Floor($p.X) + $dx; $ty = [int][Math]::Floor($p.Y) + $dy
    $idx = $ty * $w + $tx; $t = $script:Tiles[$idx]
    $script:MadeNoise = $true; $script:ForceFlash = 10.0; $script:Shake = 10.0
    Start-Sfx 'shot_force'
    if ($t -ge $script:TILE_DOOR_BASE -and $t -lt $script:TILE_PUSHWALL) {
        $d = $script:Doors[$t - $script:TILE_DOOR_BASE]
        if ($d.Lock -in 1, 2, 4) { $d.Unlocked = $true; if ($d.Lock -ne 4) { $d.Lock = 0; $d.TexId = $script:TEX_DOOR }; Show-Message '-Force: who needs a key' }
        Open-Door ($t - $script:TILE_DOOR_BASE); $d.Open = [Math]::Max($d.Open, 0.6)
    }
    elseif ($script:Breakable[$idx]) {
        Set-MapTile $idx 0; $script:Breakable[$idx] = $false; $script:Stats.Secrets++; $script:MapBmp = $null
        foreach ($o in @(-0.25, -0.2), @(0.2, 0.1), @(0.0, 0.3)) { Add-Effect 'puff' ($tx + 0.5 + $o[0]) ($ty + 0.5 + $o[1]) }
        Show-Message '-Force: the wall crumbles!'
    }
    elseif ($script:PushTex[$idx] -ne 0) { Start-PushWall $tx $ty $dx $dy }
    $rad = $p.Angle * [Math]::PI / 180.0; $fx = [Math]::Cos($rad); $fy = - [Math]::Sin($rad)
    foreach ($a in @($script:Actors)) {
        if (-not $a.Shootable) { continue }
        $ax = $a.X - $p.X; $ay = $a.Y - $p.Y
        $dist = [Math]::Sqrt($ax * $ax + $ay * $ay)
        if ($dist -lt 2.6 -and ($ax * $fx + $ay * $fy) / [Math]::Max(0.01, $dist) -gt 0.5 -and (Test-LineToPlayer $a.X $a.Y)) { Invoke-ActorDamage $a (35 + ((Get-Rnd) -shr 3)) 'blast' }
    }
    $true
}

# Undo: back to the oldest checkpoint (about five seconds ago). The clock and the privilege do not go back.
function Undo-World {
    if ($script:Checkpoints.Count -lt 3) { Show-Message 'Undo: nothing to go back to yet'; Start-Sfx 'noway'; return $false }
    $tics = $script:Stats.Tics; $privilege = $script:P.Privilege; $seconds = [Math]::Round($script:Checkpoints.Count / 2.0)
    Stop-WhatIf
    Restore-WorldSnapshot $script:Checkpoints[0]
    $script:Checkpoints.Clear(); $script:CheckpointTics = 0.0
    $script:Stats.Tics = $tics; $script:P.Privilege = $privilege
    $script:P.UseHeld = $true; $script:P.FireHeld = $true
    Reset-ScreenEffects
    $script:UndoFlash = 20.0
    Start-Sfx 'teleport'
    Show-Message "Restore-Checkpoint: the last $seconds seconds never happened"
    $true
}

# Called first thing in Update-World. Returns the tics the WORLD may advance by this frame
# (0 while -WhatIf has stopped time, a third while -Confirm is asking).
function Update-Abilities([double]$Tics, [hashtable]$In) {
    $p = $script:P
    if ($null -eq $p.Privilege) { $p.Privilege = 50.0 }
    if ($In.Ability) { Invoke-Ability ([int]$In.Ability) }
    Add-Privilege ($Tics / 45.0)
    if ($script:UndoFlash -gt 0) { $script:UndoFlash -= $Tics }
    if ($script:VerboseTics -gt 0) { $script:VerboseTics -= $Tics }
    if ($script:WhatIfTics -gt 0) {
        $script:WhatIfTics -= $Tics
        if ($script:WhatIfTics -le 0 -or $In.Fire -or $In.Forward -or $In.Strafe) { Stop-WhatIf } else { return 0.0 }
    }
    if ($script:ConfirmTics -gt 0) { $script:ConfirmTics -= $Tics; return $Tics * 0.3 }
    $Tics
}

# ---------------------------------------------------------------------------------------------
# What the abilities draw over the view (called by Show-Overlays)
# ---------------------------------------------------------------------------------------------
function Show-AbilityOverlays {
    $viewH = $script:ViewH; $p = $script:P
    if ($script:UndoFlash -gt 0) { Write-HudBar ('{0:X2}C0F0FF' -f [int][Math]::Min(200, $script:UndoFlash * 10)) 0 0 320 $viewH }
    if ($script:WhatIfTics -gt 0) {
        foreach ($b in @(0, 0, 320, 3), @(0, ($viewH - 3), 320, 3), @(0, 0, 3, $viewH), @(317, 0, 3, $viewH)) { Write-HudBar 'A040E0FF' $b[0] $b[1] $b[2] $b[3] }
        Write-HudBar '2840E0FF' 0 0 320 $viewH
        Write-HudText ("What if: time stands still for {0:0.0}s   (look around; moving or firing ends it)" -f ($script:WhatIfTics / 70)) 'Small' '40E0FF' 0 20 320 8
    }
    if ($script:ConfirmTics -gt 0) {
        Write-HudBar '20F9F1A5' 0 0 320 $viewH
        Write-HudText 'Confirm' 'Small' 'FFFFFF' 60 20 200 8
        Write-HudText ("Are you sure you want to perform this action?  [Y] Yes  [A] Yes to All  [N] No   ({0:0.0}s)" -f ($script:ConfirmTics / 70)) 'Small' 'F9F1A5' 0 28 320 8
    }
    if ($script:VerboseTics -gt 0) {
        # everybody within 14 tiles, walls or no walls - in the yellow of the verbose stream
        $rad = $p.Angle * [Math]::PI / 180.0; $dirX = [Math]::Cos($rad); $dirY = - [Math]::Sin($rad)
        $plane = $script:PlaneLen; if (-not $plane) { $plane = 0.66 }
        foreach ($a in $script:Actors) {
            if (-not $a.Shootable -or $a.Def.Inert -or $a.Kind -eq 'peer') { continue }
            $rx = $a.X - $p.X; $ry = $a.Y - $p.Y
            if ([Math]::Abs($rx) -gt 14 -or [Math]::Abs($ry) -gt 14) { continue }
            $depth = $rx * $dirX + $ry * $dirY
            if ($depth -lt 0.4) { continue }
            $lat = $ry * $dirX - $rx * $dirY
            $sx = 160.0 * (1.0 + $lat / ($depth * $plane))
            if ($sx -lt 8 -or $sx -gt 312) { continue }
            $size = [Math]::Min(150.0, $script:ProjH / $depth)
            $top = 100 - $size * 0.42; $half = $size * 0.2
            if (-not $a.Visible) { foreach ($b in @(($sx - $half), $top, ($half * 2), 0.7), @(($sx - $half), ($top + $size * 0.9), ($half * 2), 0.7), @(($sx - $half), $top, 0.7, ($size * 0.9)), @(($sx + $half), $top, 0.7, ($size * 0.9))) { Write-HudBar 'C0F9F1A5' $b[0] $b[1] $b[2] $b[3] } }
            Write-HudText "VERBOSE: $($a.Kind) $($a.HP)" 'Small' 'F9F1A5' ($sx - 40) ([Math]::Max(10, $top - 9)) 80 8
        }
    }
    # the privilege gauge and what it buys
    $x = 236; $y = $viewH - 19
    Write-HudText 'PRIVILEGE' 'Small' '8FB0FF' $x $y 34 8
    Write-HudBar '60101A2C' ($x + 36) ($y + 1.5) 44 5
    Write-HudBar $(if ($p.Privilege -ge 60) { '40E0FF' } elseif ($p.Privilege -ge 25) { '2C8AC4' } else { '2C4A86' }) ($x + 36) ($y + 1.5) (44 * [Math]::Min(1.0, [double]$p.Privilege / $script:PRIVILEGE_MAX)) 5
    $px = 196
    for ($i = 1; $i -lt $script:Abilities.Count; $i++) {
        $ab = $script:Abilities[$i]
        $lit = $p.Privilege -ge $ab.Cost
        Write-HudText "$($ab.Key) $($ab.Name.TrimStart('-'))" 'Small' $(if ($lit) { 'C0D0F0' } else { '4A5670' }) $px ($viewH - 10) 26 8
        $px += 24.5
    }
}
