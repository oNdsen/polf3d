# POLF 3D - Copyright (c) 2026 oNdsen. Licensed under the MIT License, see LICENSE.

# Demo.ps1 - demo recording and playback, and the bot that records the attract demo.
#
# A demo is the random seed of the floor plus, for every frame, the tics that passed and the
# player's input. Playing it back feeds the same numbers into the same simulation - so it only
# stays in sync as long as the game logic has not changed since it was recorded (the classic
# demo problem; tools and self-test can re-record the attract demo at any time).

$script:Recording = $null          # while recording: @{ Frames = List; ... }
$script:Playback = $null           # while playing:   @{ Frames; Index; ... }

# ---------------------------------------------------------------------------------------------
# Recording
# ---------------------------------------------------------------------------------------------
function Start-DemoRecording([int]$Seed = 0) {
    # a demo always starts from a fresh floor with a known seed
    $script:NextSeed = if ($Seed) { $Seed } else { [int]($script:Clock.ElapsedTicks % 1000000) + 1 }
    $script:BonusMap = $null
    Start-Level $false $false
    Update-View                                                   # prime what the enemies can see, exactly as playback does
    $script:Recording = @{ Seed = $script:LevelSeed; Frames = [System.Collections.Generic.List[object]]::new() }
    Show-Message 'RECORDING - F12 stops and saves'
}

function Add-DemoFrame([double]$Tics, [hashtable]$In) {
    $flags = [int][bool]$In.Run + 2 * [int][bool]$In.Sneak + 4 * [int][bool]$In.Fire + 8 * [int][bool]$In.Use
    $script:Recording.Frames.Add(@($Tics, [double]$In.Forward, [double]$In.Strafe, [double]$In.Turn, [double]$In.MouseTurn, $flags, [int]$In.Weapon, [int]$In.Ability))
}

function Stop-DemoRecording([string]$Path) {
    $rec = $script:Recording; $script:Recording = $null
    if (-not $rec -or $rec.Frames.Count -eq 0) { return }
    if (-not $Path) { $Path = Join-Path $script:SaveDir ("demo-{0:yyyyMMdd-HHmmss}.json" -f (Get-Date)) }
    $demo = [ordered]@{
        Version = 1; Game = $script:PolfVersion; Map = Split-Path $script:MapFile -Leaf; Difficulty = $script:Difficulty; Seed = $rec.Seed
        Mods = @($script:Mods)                                                    # they change the rules
        Dungeon = $script:DungeonSeed; ColumnStep = $script:ColumnStep           # a dungeon is rebuilt from its number; the ray count decides who is seen
        Completed = [bool]$script:LevelDone; Seconds = [Math]::Round($script:Stats.Tics / $script:TICRATE, 2)
        # where the recording ended - playback must arrive at exactly the same numbers
        End = [ordered]@{ X = $script:P.X; Y = $script:P.Y; Health = $script:P.Health; Kills = $script:Stats.Kills; Score = $script:P.Score }
        Frames = $rec.Frames
    }
    $null = New-Item -ItemType Directory -Path (Split-Path $Path) -Force
    $demo | ConvertTo-Json -Depth 4 -Compress | Set-Content -LiteralPath $Path -Encoding utf8
    Show-Message "Demo saved: $(Split-Path $Path -Leaf) ($($rec.Frames.Count) frames)"
}

# ---------------------------------------------------------------------------------------------
# Playback
# ---------------------------------------------------------------------------------------------
function Start-DemoPlayback([string]$Path) {
    try {
        $demo = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -AsHashtable
        if ((@($demo.Mods) -join '|') -ne (@($script:Mods) -join '|')) { throw "recorded with the mods '$(@($demo.Mods) -join ', ')', running with '$(@($script:Mods) -join ', ')'" }
        $index = -1
        if ($demo.Dungeon) { $script:DungeonSeed = [int]$demo.Dungeon; $script:DungeonMap = New-DungeonMap $script:DungeonSeed; $index = 0 }
        else {
            Stop-Dungeon
            for ($i = 0; $i -lt $script:MapFiles.Count; $i++) { if ((Split-Path $script:MapFiles[$i] -Leaf) -eq $demo.Map) { $index = $i } }
        }
        if ($index -lt 0) { throw "map '$($demo.Map)' not found" }
        if ($demo.ColumnStep -and [int]$demo.ColumnStep -ne $script:ColumnStep) { $script:KeepColumnStep = $script:ColumnStep; $script:ColumnStep = [int]$demo.ColumnStep }
        $script:Difficulty = [int]$demo.Difficulty
        $script:LevelIndex = $index; $script:BonusMap = $null
        $script:NextSeed = [int]$demo.Seed
        Start-Level $false $false
        Update-View
        $script:Playback = @{ Frames = $demo.Frames; Index = 0; End = $demo.End; Game = [string]$demo.Game }      # Game: the version that recorded it (demos before 1.3.0 do not say)
        return $true
    }
    catch { Show-Message "Demo: $($_.Exception.Message)"; return $false }
}

# The next recorded frame as @{ Tics; In }, or $null at the end of the demo.
function Get-DemoFrame {
    $pb = $script:Playback
    if (-not $pb -or $pb.Index -ge $pb.Frames.Count) { return $null }
    $f = $pb.Frames[$pb.Index++]
    $flags = [int]$f[5]
    @{
        Tics = [double]$f[0]
        In = @{ Forward = [double]$f[1]; Strafe = [double]$f[2]; Turn = [double]$f[3]; MouseTurn = [double]$f[4]; Weapon = [int]$f[6]; Ability = $(if ($f.Count -gt 7) { [int]$f[7] } else { 0 })
            Run = [bool]($flags -band 1); Sneak = [bool]($flags -band 2); Fire = [bool]($flags -band 4); Use = [bool]($flags -band 8) }
    }
}

# Did playback end exactly where the recording did?
function Test-DemoInSync {
    $e = $script:Playback.End
    $e -and [Math]::Abs($e.X - $script:P.X) -lt 1e-6 -and [Math]::Abs($e.Y - $script:P.Y) -lt 1e-6 -and
    [int]$e.Health -eq $script:P.Health -and [int]$e.Kills -eq $script:Stats.Kills -and [int]$e.Score -eq $script:P.Score
}

# ---------------------------------------------------------------------------------------------
# The demo bot: hunts the nearest enemy along the shortest path, opens doors, shoots what it
# sees. Not a great player - but good enough for thirty seconds of attract mode. It is meant to
# look like somebody playing, not like an aimbot: it stays with the enemy it is fighting instead
# of darting between targets, turns with some inertia, steers for the far end of a corridor
# rather than the next tile, fires in bursts and takes a breath after a kill.
# ---------------------------------------------------------------------------------------------
$script:BotPath = $null            # the way to whatever the bot is after, as tile indexes
$script:BotFoe = $null             # the enemy it is fighting
$script:BotTurn = 0.0              # how fast it is turning right now (degrees per frame)
$script:BotHold = 0                # frames of standing still after a kill
$script:BotReact = 0               # frames until it has noticed a new enemy

function Reset-Bot { $script:BotPath = $null; $script:BotFoe = $null; $script:BotTurn = 0.0; $script:BotHold = 0; $script:BotReact = 0 }

# One flood fill from the player finds the NEAREST REACHABLE enemy (or clip, or first aid kit when needed)
# and returns the way there as tile indexes, the first step first - or nothing if nothing can be reached.
function Find-BotPath([int]$FromX, [int]$FromY) {
    $w = $script:MapW; $n = $w * $script:MapH
    $goals = [bool[]]::new($n)
    foreach ($a in $script:Actors) { if ($a.Shootable -and -not $a.Def.Inert) { $goals[[int][Math]::Floor($a.Y) * $w + [int][Math]::Floor($a.X)] = $true } }
    foreach ($s in $script:Items) {                              # ... or the nearest thing worth picking up
        if ($s.Removed) { continue }
        $wanted = switch -Regex ($s.Item) {
            '^(clip|clip_small|mgun|chaingun)$' { $script:P.Ammo -lt 80; break }
            '^(dogfood|food|medkit)$'           { $script:P.Health -lt 70; break }
            '^key_'                             { $true; break }
            default                             { $false }
        }
        if ($wanted) { $goals[$s.Y * $w + $s.X] = $true }
    }
    $prev = [int[]]::new($n); [Array]::Fill($prev, -1)
    $start = $FromY * $w + $FromX
    $queue = [System.Collections.Generic.Queue[int]]::new(); $queue.Enqueue($start); $prev[$start] = $start
    $tiles = $script:Tiles; $block = $script:StaticBlock
    while ($queue.Count) {
        $c = $queue.Dequeue()
        if ($goals[$c] -and $c -ne $start) {
            $path = [System.Collections.Generic.List[int]]::new()
            while ($c -ne $start) { $path.Insert(0, $c); $c = $prev[$c] }        # walk back to the start
            return $path.ToArray()                                  # unrolled into the caller's @( ): one tile per element
        }
        foreach ($d in -1, 1, (-$w), $w) {
            $nb = $c + $d
            if ($nb -lt 0 -or $nb -ge $n -or $prev[$nb] -ge 0) { continue }
            $t = $tiles[$nb]
            if ($t -eq 0) { $ok = -not $block[$nb] -or $goals[$nb] }
            elseif ($t -ge 100 -and $t -lt 200) {
                $door = $script:Doors[$t - 100]
                $ok = $door.Lock -eq 0 -or $door.Lock -eq 3 -or $door.Unlocked -or ($door.Lock -eq 1 -and $script:P.KeyGold) -or ($door.Lock -eq 2 -and $script:P.KeySilver)
            }
            else { $ok = $false }
            if ($ok) { $prev[$nb] = $c; $queue.Enqueue($nb) }
        }
    }
    $null
}

# The point $Distance tiles along the bot's way (through the tile centres), or the end of the way.
function Get-BotPathPoint([double]$Distance) {
    $w = $script:MapW; $fx = $script:P.X; $fy = $script:P.Y
    foreach ($c in $script:BotPath) {
        $cx = $c % $w + 0.5; $cy = [Math]::Floor($c / $w) + 0.5
        $leg = [Math]::Sqrt(($cx - $fx) * ($cx - $fx) + ($cy - $fy) * ($cy - $fy))
        if ($leg -ge $Distance) { $k = $Distance / $leg; return @(($fx + ($cx - $fx) * $k), ($fy + ($cy - $fy) * $k)) }      # (the comma binds tighter than the arithmetic)
        $Distance -= $leg; $fx = $cx; $fy = $cy
    }
    @($fx, $fy)
}

function Get-BotInput([int]$Frame) {
    $p = $script:P; $w = $script:MapW
    $in = @{ Forward = 0; Strafe = 0; Turn = 0; MouseTurn = 0.0; Run = $false; Sneak = $false; Fire = $false; Use = $false; Weapon = -1 }
    $ptx = [int][Math]::Floor($p.X); $pty = [int][Math]::Floor($p.Y)

    # the enemy it is fighting: stay with him as long as he stands and can be seen - no darting between targets
    $foe = $script:BotFoe
    if ($foe -and -not ($foe.Shootable -and $foe.Visible -and (Test-LineToPlayer $foe.X $foe.Y))) {
        if (-not $foe.Shootable) { $script:BotHold = 14 }          # he is down: a breath before moving on
        $foe = $null
    }
    if (-not $foe -and $Frame % 4 -eq 0) {                        # a look around for the next one, a few times a second
        $foe = $script:Actors | Where-Object { $_.Shootable -and -not $_.Def.Inert -and $_.Visible -and (Test-LineToPlayer $_.X $_.Y) } | Sort-Object Depth | Select-Object -First 1
        if ($foe) { $script:BotReact = 6 }                        # a sixth of a second before the aim swings over
    }
    $script:BotFoe = $foe
    if ($script:BotHold -gt 0) { $script:BotHold--; $script:BotTurn *= 0.8; $in.MouseTurn = - $script:BotTurn; return $in }

    if ($foe) {
        # the aim is human: it drifts a little around the target, and a new target takes a moment to react to
        $tx = $foe.X; $ty = $foe.Y
        $wobble = 2.0 * [Math]::Sin($Frame * 0.23) + 1.2 * [Math]::Sin($Frame * 0.071)
    }
    else {
        $wobble = 0.3 * [Math]::Sin($Frame * 0.11)                 # a walking view is never quite still
        $here = $pty * $w + $ptx
        if ($Frame % 18 -eq 0 -or -not $script:BotPath) { $script:BotPath = @(Find-BotPath $ptx $pty) }      # re-plan twice a second
        while ($script:BotPath.Count -and $script:BotPath[0] -eq $here) { $script:BotPath = @($script:BotPath | Select-Object -Skip 1) }
        if (-not $script:BotPath.Count) { $script:BotTurn = [Math]::Min(1.5, $script:BotTurn + 0.1); $in.MouseTurn = - $script:BotTurn; return $in }      # nothing to go for: look around, slowly
        # the feet follow the way closely, the eyes look further along it: the view stays down the corridor while
        # the body rounds the corner, sidestepping if it has to - the way anybody walks through a building
        $near = Get-BotPathPoint 0.9; $far = Get-BotPathPoint 2.8
        $tx = $far[0]; $ty = $far[1]; $move = $near
    }

    # a rocket on its way? step aside (this way, then that way)
    foreach ($a in $script:Actors) { if ($a.Kind -eq 'rocket' -and $a.State -eq 'rocket.fly' -and $a.Visible) { $in.Strafe = if ([int]($Frame / 50) % 2) { 1 } else { -1 }; $in.Run = $true; break } }

    # turning with inertia: faster the further there is to go, easing in and out, and at rest once it is close
    $want = [Math]::Atan2(- ($ty - $p.Y), $tx - $p.X) * 180.0 / [Math]::PI + $wobble
    $diff = (($want - $p.Angle + 540.0) % 360.0) - 180.0
    $goal = if ([Math]::Abs($diff) -lt 0.8) { 0.0 } else { [Math]::Max(-4.5, [Math]::Min(4.5, $diff * 0.2)) }
    if ($script:BotReact -gt 0) { $script:BotReact--; $goal = $script:BotTurn * 0.8 }      # not seen him yet
    $script:BotTurn += [Math]::Max(-0.6, [Math]::Min(0.6, $goal - $script:BotTurn))
    $in.MouseTurn = - $script:BotTurn
    if ($foe) {
        $in.Fire = [Math]::Abs($diff) -lt 9 -and ($Frame % 20 -lt 9)      # bursts, with a pause between them
        if ($foe.Depth -gt 5 -and [Math]::Abs($diff) -lt 25) { $in.Forward = 1 }
    }
    else {
        # walk towards the near point whatever the view is doing: forward and sideways in the right mix
        $mx = $move[0] - $p.X; $my = $move[1] - $p.Y; $len = [Math]::Sqrt($mx * $mx + $my * $my)
        if ($len -gt 0.05) {
            $rad = $p.Angle * [Math]::PI / 180.0; $fx = [Math]::Cos($rad); $fy = - [Math]::Sin($rad)
            $forward = ($mx * $fx + $my * $fy) / $len; $strafe = ($mx * $fy * -1 + $my * $fx) / $len
            if ($forward -gt -0.3) { $in.Forward = [Math]::Round($forward, 2); $in.Strafe = [Math]::Round($strafe, 2) }      # the way is behind: turn first
        }
        $t = $script:Tiles[$script:BotPath[0]]
        if ($t -ge $script:TILE_DOOR_BASE -and $t -lt $script:TILE_PUSHWALL -and $script:Doors[$t - $script:TILE_DOOR_BASE].Action -eq 'closed') { $in.Use = $Frame % 10 -lt 2 }
    }
    $in
}

# Plays a floor with the bot, headless, at a fixed 35 frames per second, and saves the demo. The
# bot is no genius, so it gets several attempts (different seeds) and the best take is kept.
function Export-AttractDemo([string]$Path, [int]$Seconds = 40, [int]$Attempts = 5) {
    $script:KeyDown = [bool[]]::new(256); $script:KeyHit = [System.Collections.Generic.Queue[int]]::new(); $script:Mode = 'play'
    $best = -1; $take = "$Path.take"
    for ($try = 1; $try -le $Attempts; $try++) {
        $script:GodMode = $false; $script:LevelIndex = 0; $script:Difficulty = 1
        Start-DemoRecording
        Reset-Bot
        $frames = $Seconds * 35
        for ($f = 0; $f -lt $frames -and -not $script:PlayerDied -and -not $script:LevelDone; $f++) {
            Update-View                                            # the bot sees what the renderer marks visible
            $in = Get-BotInput $f
            Add-DemoFrame 2.0 $in
            Update-World 2.0 $in
        }
        $score = $script:Stats.Kills * 100 + $script:P.Health + $f / 10
        Stop-DemoRecording $take
        Write-Step ("attract demo, take {0}: {1} frames, {2} kills, {3} health" -f $try, $f, $script:Stats.Kills, $script:P.Health)
        if ($score -gt $best) { $best = $score; Move-Item -LiteralPath $take -Destination $Path -Force }
    }
    Remove-Item -LiteralPath $take -ErrorAction SilentlyContinue
    Write-Step "attract demo: best take saved to $Path"
}
