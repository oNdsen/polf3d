# POLF 3D - Copyright (c) 2026 oNdsen. Licensed under the MIT License, see LICENSE.

# Dungeon.ps1 - the daily dungeon: one floor generated from a number. Today's date is the number
# everybody gets today (G on the title screen); -Dungeon <seed> plays any other.
#
# The rules make a run comparable: a fresh kit, one life, no saving, no console - and every run is
# recorded as a demo. Since a demo is nothing but the seed plus the input of every frame, a time can
# be CHECKED: ./Start-Polf3D.ps1 -VerifyDemo <file> builds the same dungeon, plays the input back
# without a window and says whether it really ends at the lift in that time.
#
# The generator: rooms scattered over the map, joined into a tree by corridors (plus a loop or two),
# doors where corridors meet rooms. The room farthest from the start gets the lift behind a gold
# door, another dead end gets the commander who carries the gold key, and everything in between is
# populated by how far from the start it is.

$script:DungeonSeed = 0
$script:DungeonMap = $null

function Get-DailySeed { [int](Get-Date).ToString('yyyyMMdd') }

function Get-DungeonPath([int]$Seed) { Join-Path $script:SaveDir "dungeon-$Seed.map" }

# Builds the map for $Seed (trying variations of it until one passes its own checks) and returns the file.
function New-DungeonMap([int]$Seed) {
    for ($attempt = 0; $attempt -lt 40; $attempt++) {
        $lines = New-DungeonLayout $Seed $attempt
        if ($lines) {
            $path = Get-DungeonPath $Seed
            $null = New-Item -ItemType Directory -Path (Split-Path $path) -Force
            [System.IO.File]::WriteAllLines($path, [string[]]$lines)
            return $path
        }
    }
    throw "No dungeon could be built for seed $Seed."
}

function New-DungeonLayout([int]$Seed, [int]$Attempt) {
    $rng = [System.Random]::new(($Seed % 50000000) * 41 + $Attempt)
    $W = 50; $H = 40
    $g = New-Object 'string[,]' $W, $H
    $wallRx = '^([SBWRMGT][A-Za-z]|D.)$'
    $themes = 'SS', 'BB', 'WW', 'RR', 'MM', 'TT', 'GG'

    # ---- rooms ----
    $rooms = [System.Collections.Generic.List[hashtable]]::new()
    for ($try = 0; $try -lt 90 -and $rooms.Count -lt 11; $try++) {
        $rw = $rng.Next(5, 11); $rh = $rng.Next(4, 8)
        $rx = $rng.Next(2, $W - $rw - 2); $ry = $rng.Next(2, $H - $rh - 2)
        $clash = $false
        foreach ($o in $rooms) { if ($rx -lt $o.X + $o.W + 3 -and $o.X -lt $rx + $rw + 3 -and $ry -lt $o.Y + $o.H + 3 -and $o.Y -lt $ry + $rh + 3) { $clash = $true; break } }
        if (-not $clash) { $rooms.Add(@{ X = $rx; Y = $ry; W = $rw; H = $rh; CX = $rx + [int]($rw / 2); CY = $ry + [int]($rh / 2); Wall = $themes[$rng.Next($themes.Count)]; Links = 0; Id = $rooms.Count }) }
    }
    if ($rooms.Count -lt 8) { return $null }
    foreach ($r in $rooms) {
        for ($y = $r.Y - 1; $y -le $r.Y + $r.H; $y++) {
            for ($x = $r.X - 1; $x -le $r.X + $r.W; $x++) {
                $inside = $x -ge $r.X -and $x -lt $r.X + $r.W -and $y -ge $r.Y -and $y -lt $r.Y + $r.H
                if ($inside) { $g[$x, $y] = '..' } elseif ($null -eq $g[$x, $y]) { $g[$x, $y] = $r.Wall }
            }
        }
    }

    # ---- corridors: every room to the nearest one before it, plus two loops ----
    $carve = {
        param($x, $y, $wall)
        if ($g[$x, $y] -ne '..') { $g[$x, $y] = '..' }
        for ($dy = -1; $dy -le 1; $dy++) { for ($dx = -1; $dx -le 1; $dx++) { if ($null -eq $g[($x + $dx), ($y + $dy)]) { $g[($x + $dx), ($y + $dy)] = $wall } } }
    }
    $join = {
        param($a, $b)
        $x = $a.CX; $y = $a.CY
        $horizontalFirst = $rng.Next(2) -eq 0
        foreach ($leg in $(if ($horizontalFirst) { 'x', 'y' } else { 'y', 'x' })) {
            if ($leg -eq 'x') { while ($x -ne $b.CX) { $x += [Math]::Sign($b.CX - $x); & $carve $x $y $a.Wall } }
            else { while ($y -ne $b.CY) { $y += [Math]::Sign($b.CY - $y); & $carve $x $y $a.Wall } }
        }
        $a.Links++; $b.Links++
    }
    for ($i = 1; $i -lt $rooms.Count; $i++) {
        $best = $null; $bestD = 1e9
        for ($j = 0; $j -lt $i; $j++) { $d = [Math]::Abs($rooms[$i].CX - $rooms[$j].CX) + [Math]::Abs($rooms[$i].CY - $rooms[$j].CY); if ($d -lt $bestD) { $bestD = $d; $best = $rooms[$j] } }
        & $join $rooms[$i] $best
    }

    # ---- how far is everything from the start? ----
    $dist = New-Object 'int[,]' $W, $H
    for ($y = 0; $y -lt $H; $y++) { for ($x = 0; $x -lt $W; $x++) { $dist[$x, $y] = -1 } }
    $flood = {
        for ($y = 0; $y -lt $H; $y++) { for ($x = 0; $x -lt $W; $x++) { $dist[$x, $y] = -1 } }
        $queue = [System.Collections.Generic.Queue[int]]::new(); $queue.Enqueue($rooms[0].CY * $W + $rooms[0].CX); $dist[$rooms[0].CX, $rooms[0].CY] = 0
        while ($queue.Count) {
            $c = $queue.Dequeue(); $cx = $c % $W; $cy = [int][Math]::Floor($c / $W)
            foreach ($n in @(1, 0), @(-1, 0), @(0, 1), @(0, -1)) {
                $nx = $cx + $n[0]; $ny = $cy + $n[1]
                if ($nx -lt 0 -or $ny -lt 0 -or $nx -ge $W -or $ny -ge $H -or $dist[$nx, $ny] -ge 0) { continue }
                $cell = $g[$nx, $ny]
                if ($null -eq $cell -or ($cell -cmatch '^[SBWRMGT]') -or $cell -in '*c', '*e', 'MX') { continue }
                $dist[$nx, $ny] = $dist[$cx, $cy] + 1; $queue.Enqueue($ny * $W + $nx)
            }
        }
    }
    & $flood
    foreach ($r in $rooms) { $r.Dist = $dist[$r.CX, $r.CY] }
    $far = ($rooms | Measure-Object Dist -Maximum).Maximum
    # the lift goes into the farthest dead end, the commander into another one (or simply far away)
    $leaves = @($rooms | Where-Object { $_.Links -eq 1 -and $_.Id -ne 0 } | Sort-Object Dist -Descending)
    if (-not $leaves.Count) { return $null }
    $exit = $leaves[0]
    $bossRoom = if ($leaves.Count -gt 1) { $leaves[1] } else { $rooms | Where-Object { $_.Id -notin 0, $exit.Id } | Sort-Object Dist -Descending | Select-Object -First 1 }
    # two loops, so that there is more than one way round - but not into the two special rooms
    $others = @($rooms | Where-Object { $_.Id -notin $exit.Id, $bossRoom.Id })
    for ($k = 0; $k -lt 2 -and $others.Count -gt 3; $k++) { $a = $others[$rng.Next($others.Count)]; $b = $others[$rng.Next($others.Count)]; if ($a.Id -ne $b.Id) { & $join $a $b } }

    # ---- doors: where a corridor meets a room, if the masonry allows ----
    $inRoom = { param($x, $y) foreach ($r in $rooms) { if ($x -ge $r.X -and $x -lt $r.X + $r.W -and $y -ge $r.Y -and $y -lt $r.Y + $r.H) { return $r } }; $null }
    $exitDoors = 0
    for ($y = 1; $y -lt $H - 1; $y++) {
        for ($x = 1; $x -lt $W - 1; $x++) {
            if ($g[$x, $y] -ne '..' -or (& $inRoom $x $y)) { continue }
            $solidNS = ($g[$x, ($y - 1)] -cmatch '^[SBWRMGT]') -and ($g[$x, ($y + 1)] -cmatch '^[SBWRMGT]')
            $solidWE = ($g[($x - 1), $y] -cmatch '^[SBWRMGT]') -and ($g[($x + 1), $y] -cmatch '^[SBWRMGT]')
            if (-not ($solidNS -xor $solidWE)) { continue }
            $ends = if ($solidNS) { @(($x - 1), $y), @(($x + 1), $y) } else { @($x, ($y - 1)), @($x, ($y + 1)) }
            if ($g[$ends[0][0], $ends[0][1]] -ne '..' -or $g[$ends[1][0], $ends[1][1]] -ne '..') { continue }
            $room = (& $inRoom $ends[0][0] $ends[0][1]); if (-not $room) { $room = (& $inRoom $ends[1][0] $ends[1][1]) }
            if (-not $room) { continue }
            if ($room.Id -eq $exit.Id) { $g[$x, $y] = 'DG'; $exitDoors++ }
            elseif ($rng.Next(100) -lt 80) { $g[$x, $y] = 'DD' }
        }
    }
    if ($exitDoors -ne 1) { return $null }                        # the gold door must be the only way in

    # ---- the lift switch: in the wall of the exit room, as far from its door as possible ----
    $spots = foreach ($x in $exit.X..($exit.X + $exit.W - 1)) { , @($x, ($exit.Y - 1), $x, $exit.Y); , @($x, ($exit.Y + $exit.H), $x, ($exit.Y + $exit.H - 1)) }
    $spots += foreach ($y in $exit.Y..($exit.Y + $exit.H - 1)) { , @(($exit.X - 1), $y, $exit.X, $y); , @(($exit.X + $exit.W), $y, ($exit.X + $exit.W - 1), $y) }
    $switch = $spots | Where-Object { $g[$_[0], $_[1]] -cmatch '^[SBWRMGT]' } | Sort-Object { - $dist[$_[2], $_[3]] } | Select-Object -First 1
    if (-not $switch) { return $null }
    $g[$switch[0], $switch[1]] = 'MX'

    # ---- things ----
    $free = {
        param($r, [int]$margin = 0)
        for ($t = 0; $t -lt 30; $t++) {
            $x = $rng.Next($r.X + $margin, $r.X + $r.W - $margin); $y = $rng.Next($r.Y + $margin, $r.Y + $r.H - $margin)
            if ($g[$x, $y] -ne '..') { continue }
            $nearDoor = $false
            foreach ($n in @(1, 0), @(-1, 0), @(0, 1), @(0, -1), @(2, 0), @(-2, 0), @(0, 2), @(0, -2)) { $c = $g[($x + $n[0]), ($y + $n[1])]; if ($c -and $c[0] -ceq 'D') { $nearDoor = $true } }
            if (-not $nearDoor) { return @($x, $y) }
        }
        $null
    }
    $put = { param($r, $code, [int]$margin = 0) $s = & $free $r $margin; if ($s) { $g[$s[0], $s[1]] = $code } }
    $start = $rooms[0]
    $g[$start.CX, $start.CY] = 'P' + '>v<^'[$rng.Next(4)]
    & $put $start '+a'; & $put $start '+a'
    $byDist = @($rooms | Where-Object { $_.Id -ne 0 } | Sort-Object Dist)
    $gunRooms = @{ ($byDist[[int]($byDist.Count * 0.25)].Id) = '+m'; ($byDist[[int]($byDist.Count * 0.55)].Id) = '+c' }
    $special = $byDist | Where-Object { $_.Id -notin $exit.Id, $bossRoom.Id } | Select-Object -Last 1
    foreach ($r in $rooms) {
        $rank = if ($far -gt 0) { $r.Dist / $far } else { 0 }
        if ($r.W -ge 8 -and $r.H -ge 6) { foreach ($c in @(($r.X + 1), ($r.Y + 1)), @(($r.X + $r.W - 2), ($r.Y + 1)), @(($r.X + 1), ($r.Y + $r.H - 2)), @(($r.X + $r.W - 2), ($r.Y + $r.H - 2))) { if ($g[$c[0], $c[1]] -eq '..') { $g[$c[0], $c[1]] = '*c' } } }
        if ($r.Id -ne 0) {
            if ($r.Id -eq $bossRoom.Id) { if ($g[$r.CX, $r.CY] -eq '..') { $g[$r.CX, $r.CY] = 'b' + 'nesw'[$rng.Next(4)] } else { & $put $r 'bs' }; & $put $r 'e<'; & $put $r 'e>' }
            $pool = if ($rank -lt 0.35) { 'g', 'g', 'g', 'd', 'o' } elseif ($rank -lt 0.7) { 'g', 'o', 'e', 'm', 'd', 'h' } else { 'e', 'e', 'm', 'h', 's', 'k', 'o' }
            $count = 2 + [int]($r.W * $r.H / 14) + [int]($rank * 2)
            for ($i = 0; $i -lt $count; $i++) { & $put $r ($pool[$rng.Next($pool.Count)] + $(if ($rng.Next(100) -lt 30) { 'nesw' } else { '^>v<' })[$rng.Next(4)]) }
            if ($rng.Next(100) -lt 30) { & $put $r '*e' 1 }
        }
        if ($gunRooms.ContainsKey($r.Id)) { & $put $r $gunRooms[$r.Id] }
        if ($special -and $r.Id -eq $special.Id) { $kind = ('+p', '+l', '+t')[$rng.Next(3)]; & $put $r $kind; if ($kind -eq '+l') { & $put $r '+o' } }
        if ($rng.Next(100) -lt 65) { & $put $r '+a' }
        if ($rng.Next(100) -lt 40) { & $put $r $(if ($rng.Next(2)) { '+h' } else { '+f' }) }
        if ($rng.Next(100) -lt 30) { & $put $r ('+1', '+2', '+3')[$rng.Next(3)] }
        if ($rng.Next(100) -lt 45) { & $put $r '*n' 1 }
        if ($g[$r.CX, ($r.Y)] -eq '..' -and $rng.Next(100) -lt 70) { $g[$r.CX, $r.Y] = '*l' }
    }

    # ---- everything that matters must be reachable (columns and barrels block) ----
    & $flood
    for ($y = 0; $y -lt $H; $y++) { for ($x = 0; $x -lt $W; $x++) { $c = $g[$x, $y]; if ($c -and $c -cnotmatch '^[SBWRMGT]' -and $c -notin '*c', '*e', 'MX' -and $dist[$x, $y] -lt 0) { return $null } } }

    # ---- PowerShell on the walls ----
    $variants = @{ SS = 'St', 'Sh', 'Sg'; BB = 'Bt', 'Bt'; WW = 'Wt', 'Wh'; RR = 'Rt', 'Rh', 'Rg'; MM = 'Mt', 'Me', 'Mn'; GG = 'Gt', 'Gt'; TT = 'Tt', 'Te', 'Tn' }
    for ($y = 1; $y -lt $H - 1; $y++) {
        for ($x = 1; $x -lt $W - 1; $x++) {
            $c = $g[$x, $y]
            if (-not $c -or -not $variants.ContainsKey($c) -or $rng.Next(100) -ge 16) { continue }
            $faces = $false; $frame = $false
            foreach ($n in @(1, 0), @(-1, 0), @(0, 1), @(0, -1)) { $o = $g[($x + $n[0]), ($y + $n[1])]; if ($o -and $o -cnotmatch $wallRx -and $o -ne 'MX') { $faces = $true } elseif ($o -and $o[0] -ceq 'D') { $frame = $true } }
            if ($faces -and -not $frame) { $g[$x, $y] = $variants[$c][$rng.Next($variants[$c].Count)] }
        }
    }

    $look = @(
        @('flat_stone', 'ceil_plain', '101010 15'), @('flat_wood', 'ceil_plain', '14100C 15'), @('flat_moss', 'ceil_rock', '060C06 10'),
        @('flat_tech', 'ceil_tech', '0A1018 14'), @('flat_carpet', 'ceil_plain', '140A1C 14'))[$rng.Next(5)]
    $enemies = 0; for ($y = 0; $y -lt $H; $y++) { for ($x = 0; $x -lt $W; $x++) { if ($g[$x, $y] -cmatch '^[gdeomshkb][\^>v<nesw]$') { $enemies++ } } }
    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add("; POLF 3D - the dungeon for seed $Seed. Generated by src/Dungeon.ps1; do not edit - everybody must get the same one.")
    $lines.Add("@name Dungeon #$Seed"); $lines.Add("@par $(60 + $enemies * 6)"); $lines.Add('@ceiling 383838'); $lines.Add('@floor 6E6E6E')
    $lines.Add("@floortex $($look[0])"); $lines.Add("@ceiltex $($look[1])"); $lines.Add("@fog $($look[2])")
    $lines.Add('@map')
    $rock = $rooms[0].Wall
    for ($y = 0; $y -lt $H; $y++) {
        $sb = [System.Text.StringBuilder]::new()
        for ($x = 0; $x -lt $W; $x++) { $null = $sb.Append($(if ($null -eq $g[$x, $y]) { $rock } else { $g[$x, $y] })) }
        $lines.Add($sb.ToString())
    }
    $lines
}

# ---------------------------------------------------------------------------------------------
# Playing it
# ---------------------------------------------------------------------------------------------
function Start-Dungeon([int]$Seed) {
    if ($script:Net) { Show-Message 'The dungeon is a solo affair'; return $false }
    if ($Seed -le 0) { $Seed = Get-DailySeed }
    $script:DungeonSeed = $Seed
    $script:DungeonMap = New-DungeonMap $Seed
    $script:BonusMap = $null
    Start-DemoRecording $Seed                                     # a run is always recorded: that is what makes it checkable
    $script:P.Lives = 0                                           # one life
    Show-Message "Dungeon #$Seed - one life, no saving. Find the commander, take his key, reach the lift."
    $true
}

function Stop-Dungeon { $script:DungeonSeed = 0; $script:DungeonMap = $null }

# The demo of a finished (or failed) run goes next to the saved games, its time into the name.
function Save-DungeonRun([bool]$Completed) {
    if (-not $script:Recording) { return $null }
    $seconds = $script:Stats.Tics / $script:TICRATE
    $name = 'dungeon-{0}-d{1}-{2}-{3}.json' -f $script:DungeonSeed, ($script:Difficulty + 1), $(if ($Completed) { (Format-Time $seconds -Tenths).Replace(':', 'm').Replace('.', 's') } else { 'died' }), (Get-Date).ToString('HHmmss')
    $path = Join-Path $script:SaveDir $name
    Stop-DemoRecording $path
    if ($Completed) {
        $file = Join-Path $script:SaveDir 'dungeon.json'
        $all = @{}
        if (Test-Path -LiteralPath $file) { try { $all = Get-Content -LiteralPath $file -Raw | ConvertFrom-Json -AsHashtable } catch { $all = @{} } }
        $key = "$($script:DungeonSeed)|$($script:Difficulty)"
        if (-not $all[$key] -or $seconds -lt [double]$all[$key].Seconds) { $all[$key] = @{ Seconds = $seconds; Kills = $script:Stats.Kills; Demo = $name; Cheated = [bool]$script:P.Cheated } }
        $all | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $file -Encoding utf8
    }
    $name
}

function Get-DungeonBest([int]$Seed) {
    $file = Join-Path $script:SaveDir 'dungeon.json'
    if (-not (Test-Path -LiteralPath $file)) { return $null }
    try { (Get-Content -LiteralPath $file -Raw | ConvertFrom-Json -AsHashtable)["$Seed|$($script:Difficulty)"] } catch { $null }
}

# -VerifyDemo: play a demo back without a window and report. Returns $true if it checks out.
function Test-DemoFile([string]$Path) {
    $script:KeyDown = [bool[]]::new(256); $script:KeyHit = [System.Collections.Generic.Queue[int]]::new(); $script:Mode = 'play'
    $script:GodMode = $false; $script:InfiniteAmmo = $false; $script:OneHitKill = $false
    if (-not (Start-DemoPlayback $Path)) { Write-Step "NOT VALID: $($script:Message)"; return $false }
    $frames = 0
    while ($null -ne ($frame = Get-DemoFrame)) { Update-View; Update-World $frame.Tics $frame.In; $frames++; if ($script:PlayerDied -or $script:LevelDone) { break } }
    $sync = Test-DemoInSync
    $seconds = $script:Stats.Tics / $script:TICRATE
    Write-Step ("{0}: {1} on '{2}', difficulty {3}, {4} frames - {5} after {6} with {7} kills" -f $(if ($sync) { 'VALID' } else { 'NOT VALID (the playback ends somewhere else than the recording did)' }),
        (Split-Path $Path -Leaf), $script:LevelName, ($script:Difficulty + 1), $frames, $(if ($script:LevelDone) { 'reached the lift' } elseif ($script:PlayerDied) { 'died' } else { 'stopped' }), (Format-Time $seconds -Tenths), $script:Stats.Kills)
    Stop-Dungeon
    $sync
}
