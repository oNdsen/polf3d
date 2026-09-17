# POLF 3D - Copyright (c) 2026 oNdsen. Licensed under the MIT License, see LICENSE.

<#
.SYNOPSIS
    Validates level files with the game's own loader and prints an overview of each.
.DESCRIPTION
    Checks per map: it loads, its border is solid, everything that matters (items, enemies, the
    lift switch) can be reached from the start - walking through doors and through secret walls -,
    the keys for locked doors exist, and every patrol can walk its route without hitting a wall.
.PARAMETER Map
    One or more map files. Default: all maps/*.map (campaign floors and bonus floors).
#>
[CmdletBinding()]
param([string[]]$Map)

$ErrorActionPreference = 'Stop'
$src = Join-Path $PSScriptRoot '../src'
. (Join-Path $src 'Defs.ps1')
. (Join-Path $src 'Map.ps1')
. (Join-Path $src 'Mechanics.ps1')
$script:Spr = @{}; $script:Difficulty = 2
Initialize-States
if (-not $Map) { $Map = Get-ChildItem (Join-Path $PSScriptRoot '../maps') -Filter '*.map' | Sort-Object Name | ForEach-Object FullName }

function Test-LevelFile([string]$Path) {
    Initialize-Level (Resolve-Path $Path).Path
    $w = $script:MapW; $h = $script:MapH
    $problems = [System.Collections.Generic.List[string]]::new()

    for ($x = 0; $x -lt $w; $x++) { foreach ($y in 0, ($h - 1)) { $t = $script:Tiles[$y * $w + $x]; if ($t -eq 0 -or $t -ge 100) { $problems.Add("border open at $x,$y") } } }
    for ($y = 0; $y -lt $h; $y++) { foreach ($x in 0, ($w - 1)) { $t = $script:Tiles[$y * $w + $x]; if ($t -eq 0 -or $t -ge 100) { $problems.Add("border open at $x,$y") } } }

    # flood fill from the start: floor, doors and pushable secret walls are passable
    $reach = [bool[]]::new($w * $h)
    $queue = [System.Collections.Generic.Queue[int]]::new()
    $start = [int][Math]::Floor($script:StartY) * $w + [int][Math]::Floor($script:StartX)
    $reach[$start] = $true; $queue.Enqueue($start)
    while ($queue.Count) {
        $c = $queue.Dequeue()
        foreach ($pad in $script:Teleporters) {                          # a pad also leads to its partner
            if ($pad.Y * $w + $pad.X -ne $c) { continue }
            foreach ($other in $script:Teleporters) { $o = $other.Y * $w + $other.X; if ($other.Id -eq $pad.Id -and -not $reach[$o]) { $reach[$o] = $true; $queue.Enqueue($o) } }
        }
        foreach ($d in -1, 1, (-$w), $w) {
            $n = $c + $d
            if ($n -lt 0 -or $n -ge $w * $h -or $reach[$n]) { continue }
            $t = $script:Tiles[$n]
            $passable = ($t -eq 0 -and -not $script:StaticBlock[$n]) -or ($t -ge 100) -or $script:Breakable[$n]
            if ($script:PushTex[$n] -ne 0) {
                $behind = $n + $d                                   # needs a free tile behind it to move at all
                $passable = $script:Tiles[$behind] -eq 0 -and -not $script:StaticBlock[$behind]
                if (-not $passable) { $problems.Add("push-wall at $($n % $w),$([Math]::Floor($n / $w)) cannot be pushed from $($c % $w),$([Math]::Floor($c / $w))") }
            }
            if ($passable) { $reach[$n] = $true; $queue.Enqueue($n) }
        }
    }
    foreach ($s in $script:Items) { if (-not $reach[$s.Y * $w + $s.X]) { $problems.Add("item '$($s.Item)' at $($s.X),$($s.Y) is unreachable") } }
    foreach ($a in $script:Actors) {
        $ax = [int][Math]::Floor($a.X); $ay = [int][Math]::Floor($a.Y)
        if (-not $reach[$ay * $w + $ax]) { $problems.Add("enemy '$($a.Kind)' at $ax,$ay is unreachable") }
        if ($a.State -like '*.path*') {
            # walk the patrol route: follow the turning points for a while, it must never hit anything solid
            $px = $ax; $py = $ay; $dir = $a.PathDir
            for ($step = 0; $step -lt 300; $step++) {
                $px += $script:DirDX[$dir]; $py += $script:DirDY[$dir]
                $i = $py * $w + $px; $t = $script:Tiles[$i]
                if (($t -ne 0 -and $t -lt 100) -or $script:StaticBlock[$i] -or ($t -ge 100 -and -not $a.Def.Doors)) {
                    $problems.Add("patrol '$($a.Kind)' from $ax,$ay runs into an obstacle at $px,$py"); break
                }
                if ($script:TurnAt[$i] -ge 0) { $dir = $script:TurnAt[$i] }
            }
        }
    }
    $switchOk = $false
    for ($i = 0; $i -lt $w * $h; $i++) {
        if ($script:Tiles[$i] -eq $script:TEX_SWITCH_OFF) { foreach ($d in -1, 1, (-$w), $w) { if ($reach[$i + $d]) { $switchOk = $true } } }
    }
    if (-not $switchOk) { $problems.Add('No reachable lift switch (MX).') }
    foreach ($door in $script:Doors) {
        if ($door.Lock -eq 4 -and $door.Channel -notin $script:LeverAt) { $problems.Add("Remote door $($door.X),$($door.Y) has no lever X$($door.Channel).") }
    }
    for ($i = 0; $i -lt $w * $h; $i++) {
        if ($script:LeverAt[$i] -gt 0 -and -not ($reach[$i - 1] -or $reach[$i + 1] -or $reach[$i - $w] -or $reach[$i + $w])) { $problems.Add("Lever X$($script:LeverAt[$i]) cannot be reached.") }
    }
    foreach ($group in ($script:Teleporters | Group-Object { $_.Id })) { if ($group.Count -ne 2) { $problems.Add("Teleporter @$($group.Name) needs exactly two pads, found $($group.Count).") } }
    $itemNames = @($script:Items | ForEach-Object { $_.Item })      # not $Items.Item: that is the list's indexer
    $kinds = @($script:Actors | ForEach-Object { $_.Kind })
    foreach ($door in $script:Doors) {
        if ($door.Lock -eq 1 -and 'key_gold' -notin $itemNames -and 'boss' -notin $kinds) { $problems.Add('Gold door but no gold key (neither an item nor a commander).') }
        if ($door.Lock -eq 2 -and 'key_silver' -notin $itemNames) { $problems.Add('Silver door but no silver key.') }
    }

    # overview
    for ($y = 0; $y -lt $h; $y++) {
        $line = for ($x = 0; $x -lt $w; $x++) {
            $i = $y * $w + $x; $t = $script:Tiles[$i]
            if ($script:PushTex[$i]) { '?' } elseif ($script:Breakable[$i]) { '%' } elseif ($script:IsWindow[$i]) { '=' } elseif ($script:LeverAt[$i]) { 'L' } elseif ($t -eq $script:TEX_SWITCH_OFF) { 'X' } elseif ($t -eq $script:TEX_SECRET_OFF) { 'Y' } elseif ($t -ge 100) { '+' } elseif ($t -gt 0) { '#' }
            elseif ($script:ActorAt[$i]) { if ($script:ActorAt[$i].Def.Inert) { '*' } else { $script:ActorAt[$i].Kind[0] } } elseif ($script:StaticBlock[$i]) { 'o' }
            elseif ($reach[$i]) { '.' } else { '!' }
        }
        Write-Host (-join $line)
    }
    $st = $script:Stats
    $hp = ($script:Actors | Where-Object { -not $_.Def.Inert } | ForEach-Object { $_.HP } | Measure-Object -Sum).Sum
    Write-Host ("{0}: {1}x{2}, {3} doors, {4} areas, {5} enemies with {6} HP in total ({7}), {8} treasures, {9} push-walls" -f $script:LevelName, $w, $h,
        $script:Doors.Count, $script:AreaCount, @($script:Actors | Where-Object { -not $_.Def.Inert }).Count, $hp, (($script:Actors | Group-Object Kind | Sort-Object Name | ForEach-Object { "$($_.Count) $($_.Name)" }) -join ', '), $st.TreasureTotal, $st.SecretTotal)
    foreach ($p in $problems) { Write-Host "PROBLEM: $p" -ForegroundColor Red }
    Write-Host ''
    $problems.Count
}

$total = 0
foreach ($file in $Map) { Write-Host "=== $(Split-Path $file -Leaf) ===" -ForegroundColor Cyan; $total += Test-LevelFile $file }
if ($total) { throw "$total problem(s) in the maps." }
Write-Host 'All maps are fine.' -ForegroundColor Green
