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
function Start-DemoRecording {
    # a demo always starts from a fresh floor with a known seed
    $script:NextSeed = [int]($script:Clock.ElapsedTicks % 1000000) + 1
    $script:BonusMap = $null
    Start-Level $false $false
    Update-View                                                   # prime what the enemies can see, exactly as playback does
    $script:Recording = @{ Seed = $script:LevelSeed; Frames = [System.Collections.Generic.List[object]]::new() }
    Show-Message 'RECORDING - F12 stops and saves'
}

function Add-DemoFrame([double]$Tics, [hashtable]$In) {
    $flags = [int][bool]$In.Run + 2 * [int][bool]$In.Sneak + 4 * [int][bool]$In.Fire + 8 * [int][bool]$In.Use
    $script:Recording.Frames.Add(@($Tics, [double]$In.Forward, [double]$In.Strafe, [double]$In.Turn, [double]$In.MouseTurn, $flags, [int]$In.Weapon))
}

function Stop-DemoRecording([string]$Path) {
    $rec = $script:Recording; $script:Recording = $null
    if (-not $rec -or $rec.Frames.Count -eq 0) { return }
    if (-not $Path) { $Path = Join-Path $script:SaveDir ("demo-{0:yyyyMMdd-HHmmss}.json" -f (Get-Date)) }
    $demo = [ordered]@{
        Version = 1; Map = Split-Path $script:MapFile -Leaf; Difficulty = $script:Difficulty; Seed = $rec.Seed
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
        $index = -1
        for ($i = 0; $i -lt $script:MapFiles.Count; $i++) { if ((Split-Path $script:MapFiles[$i] -Leaf) -eq $demo.Map) { $index = $i } }
        if ($index -lt 0) { throw "map '$($demo.Map)' not found" }
        $script:Difficulty = [int]$demo.Difficulty
        $script:LevelIndex = $index; $script:BonusMap = $null
        $script:NextSeed = [int]$demo.Seed
        Start-Level $false $false
        Update-View
        $script:Playback = @{ Frames = $demo.Frames; Index = 0; End = $demo.End }
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
        In = @{ Forward = [double]$f[1]; Strafe = [double]$f[2]; Turn = [double]$f[3]; MouseTurn = [double]$f[4]; Weapon = [int]$f[6]
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
# sees. Not a great player - but good enough for thirty seconds of attract mode.
# ---------------------------------------------------------------------------------------------
# One flood fill from the player finds the NEAREST REACHABLE enemy and returns the first tile of the
# way there (or $null if nobody can be reached, e.g. everyone left is behind a locked door).
function Find-BotStep([int]$FromX, [int]$FromY) {
    $w = $script:MapW; $n = $w * $script:MapH
    $goals = [bool[]]::new($n)
    foreach ($a in $script:Actors) { if ($a.Shootable -and -not $a.Def.Inert) { $goals[[int][Math]::Floor($a.Y) * $w + [int][Math]::Floor($a.X)] = $true } }
    $prev = [int[]]::new($n); [Array]::Fill($prev, -1)
    $start = $FromY * $w + $FromX
    $queue = [System.Collections.Generic.Queue[int]]::new(); $queue.Enqueue($start); $prev[$start] = $start
    $tiles = $script:Tiles; $block = $script:StaticBlock
    while ($queue.Count) {
        $c = $queue.Dequeue()
        if ($goals[$c] -and $c -ne $start) {
            while ($prev[$c] -ne $start) { $c = $prev[$c] }        # walk back to the step after the start
            return $c
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

function Get-BotInput([int]$Frame) {
    $p = $script:P
    $in = @{ Forward = 0; Strafe = 0; Turn = 0; MouseTurn = 0.0; Run = $false; Sneak = $false; Fire = $false; Use = $false; Weapon = -1 }
    $ptx = [int][Math]::Floor($p.X); $pty = [int][Math]::Floor($p.Y)

    # something to shoot at right now?
    $foe = $script:Actors | Where-Object { $_.Shootable -and -not $_.Def.Inert -and $_.Visible -and (Test-LineToPlayer $_.X $_.Y) } | Sort-Object Depth | Select-Object -First 1
    if ($foe) { $tx = $foe.X; $ty = $foe.Y }
    else {
        if ($Frame % 12 -eq 0) { $script:BotStep = Find-BotStep $ptx $pty }      # re-plan three times a second
        if ($null -eq $script:BotStep) { $in.Turn = 1; return $in }
        $tx = $script:BotStep % $script:MapW + 0.5; $ty = [Math]::Floor($script:BotStep / $script:MapW) + 0.5
    }

    $want = [Math]::Atan2(- ($ty - $p.Y), $tx - $p.X) * 180.0 / [Math]::PI
    $diff = (($want - $p.Angle + 540.0) % 360.0) - 180.0
    $in.MouseTurn = - [Math]::Max(-7.0, [Math]::Min(7.0, $diff))
    if ($foe) {
        $in.Fire = [Math]::Abs($diff) -lt 6 -and ($Frame % 14 -lt 7)
        if ($foe.Depth -gt 4 -and [Math]::Abs($diff) -lt 20) { $in.Forward = 1 }
    }
    elseif ([Math]::Abs($diff) -lt 30) {
        $in.Forward = 1
        $t = $script:Tiles[$script:BotStep]
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
        $script:BotStep = $null
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
