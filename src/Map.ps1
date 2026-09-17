# POLF 3D - Copyright (c) 2026 oNdsen. Licensed under the MIT License, see LICENSE.

# Map.ps1 - loads a level from its text file and builds the run-time tables.
#
# File format (see maps/level1.map): header lines "@key value", then "@map" followed by the
# grid. Every tile is TWO characters wide:
#
#   SS Sb Sp  BB Bc  WW Wp Ws  RR Rb  MM     solid walls: stone, blue stone, wood, brick, steel (+ decorated variants)
#   GG Gv  TT Tl                             mossy rock (+ vines), tech panels (+ console)
#   MX                                       lift switch (the exit)
#   ?S ?s ?B ?b ?W ?w ?R ?r ?M ?G ?g ?T ?t   secret push-wall (upper case plain, lower case decorated)
#   !S !B !W !R !M !G !T                     cracked wall: only an explosion brings it down (counts as a secret)
#   DD DG DS DL                              door: normal / gold lock / silver lock / lift door
#   D1..D9  X1..X9                           remote door and the wall lever (same number) that opens it for good
#   ..                                       floor
#   P^ P> Pv P<                              player start + view direction
#   g d e o m s h k b u  +  ^>v< | nesw | NESW   enemy: standing | standing & deaf (ambush) | patrolling
#                                            (guard dog elite officer mutant sniper shield-bearer kamikaze-bot boss super-boss)
#   :^ :> :v :<                              patrol turning point
#   @1..@9                                   teleporter pads: two pads with the same number are a pair
#   ~s ~c                                    traps: spikes, crusher (both cycle on a timer)
#   +x                                       item,       see $ItemCodes
#   *x                                       decoration, see $DecoCodes  (*e = explosive barrel)
#
# Unlike the 1992 format there are no hand-numbered "areas": rooms are found by flood fill.

function Get-DirFromChar([char]$c) {
    switch -CaseSensitive ([string]$c) {
        '>' { 0 } '^' { 2 } '<' { 4 } 'v' { 6 }
        'e' { 0 } 'n' { 2 } 'w' { 4 } 's' { 6 }
        'E' { 0 } 'N' { 2 } 'W' { 4 } 'S' { 6 }
        default { -1 }
    }
}

function Read-MapFile([string]$Path) {
    $meta = @{ name = 'Untitled'; par = '120'; ceiling = '383838'; floor = '707070' }
    $rows = [System.Collections.Generic.List[string]]::new()
    $inMap = $false
    foreach ($line in [System.IO.File]::ReadAllLines($Path)) {
        if ($line.StartsWith(';')) { continue }
        if ($inMap) { if ($line.Trim().Length -gt 0) { $rows.Add($line.TrimEnd()) }; continue }
        if ($line.StartsWith('@map')) { $inMap = $true; continue }
        if ($line.StartsWith('@')) {
            $parts = $line.Substring(1).Split(' ', 2)
            $meta[$parts[0].ToLower()] = $parts[1].Trim()
        }
    }
    if ($rows.Count -eq 0) { throw "Map '$Path' has no @map block." }
    $w = $rows[0].Length / 2
    foreach ($r in $rows) { if ($r.Length -ne $w * 2) { throw "Map '$Path': every row must be $($w * 2) characters long (found: $($r.Length))." } }
    @{ Meta = $meta; Rows = $rows; W = [int]$w; H = $rows.Count }
}

function Initialize-Level([string]$Path) {
    $map = Read-MapFile $Path
    $w = $map.W; $h = $map.H; $n = $w * $h

    $script:MapW = $w; $script:MapH = $h
    $script:LevelName = $map.Meta.name
    $script:ParSeconds = [int]$map.Meta.par
    $script:CeilingColor = [Convert]::ToInt32('FF' + $map.Meta.ceiling, 16)
    $script:FloorColor = [Convert]::ToInt32('FF' + $map.Meta.floor, 16)

    $script:Tiles = [int[]]::new($n)              # 0 floor | 1..99 wall texture | 100+ door | 200 moving push-wall
    $script:PushTex = [int[]]::new($n)            # texture id where a secret wall waits to be pushed
    $script:StaticBlock = [bool[]]::new($n)       # blocking decoration
    $script:TurnAt = [int[]]::new($n)             # patrol turning points (-1 = none)
    $script:LeverAt = [int[]]::new($n)            # channel number of a wall lever (0 = none)
    $script:Breakable = [bool[]]::new($n)         # cracked walls that an explosion brings down
    $script:ActorAt = [object[]]::new($n)         # which enemy has reserved this tile
    $script:AreaOf = [int[]]::new($n)
    $script:Vis = [int[]]::new($n)                # frame number in which a ray last crossed the tile
    $script:Doors = [System.Collections.Generic.List[Door]]::new()
    $script:Statics = [System.Collections.Generic.List[Static]]::new()
    $script:Items = [System.Collections.Generic.List[Static]]::new()
    $script:Actors = [System.Collections.Generic.List[Actor]]::new()
    $script:NewActors = [System.Collections.Generic.List[Actor]]::new()
    $script:Traps = [System.Collections.Generic.List[hashtable]]::new()
    $script:Teleporters = [System.Collections.Generic.List[hashtable]]::new()
    $script:TeleLock = $false
    $script:Stats = @{ KillTotal = 0; Kills = 0; SecretTotal = 0; Secrets = 0; TreasureTotal = 0; Treasures = 0; Tics = 0.0 }
    $script:PW = @{ Active = $false; X = 0; Y = 0; DX = 0; DY = 0; Pos = 0.0; Moved = 0; TexId = 0 }
    for ($i = 0; $i -lt $n; $i++) { $script:TurnAt[$i] = -1; $script:AreaOf[$i] = -1 }

    # ---- pass 1: walls, push-walls, doors -----------------------------------------------------
    $doorCells = @()
    for ($y = 0; $y -lt $h; $y++) {
        $row = $map.Rows[$y]
        for ($x = 0; $x -lt $w; $x++) {
            $code = $row.Substring($x * 2, 2); $idx = $y * $w + $x
            if ($script:WallCodes.ContainsKey($code)) { $script:Tiles[$idx] = $script:WallCodes[$code] }
            elseif ($code[0] -ceq '?') {
                if (-not $script:PushCodes.ContainsKey($code[1])) { throw "Unknown push-wall '$code' at $x,$y" }
                $script:Tiles[$idx] = $script:PushCodes[$code[1]]
                $script:PushTex[$idx] = $script:PushCodes[$code[1]]
                $script:Stats.SecretTotal++
            }
            elseif ($code[0] -ceq '!') {
                if (-not $script:BreakCodes.ContainsKey($code[1])) { throw "Unknown breakable wall '$code' at $x,$y" }
                $script:Tiles[$idx] = $script:BreakCodes[$code[1]]; $script:Breakable[$idx] = $true
                $script:Stats.SecretTotal++
            }
            elseif ($code[0] -ceq 'D' -and $script:DoorCodes.ContainsKey($code[1])) { $doorCells += , @($x, $y, $script:DoorCodes[$code[1]], 0) }
            elseif ($code[0] -ceq 'D' -and [char]::IsDigit($code[1])) { $doorCells += , @($x, $y, 4, [int][string]$code[1]) }
            elseif ($code[0] -ceq 'X' -and [char]::IsDigit($code[1])) { $script:Tiles[$idx] = $script:TEX_LEVER_OFF; $script:LeverAt[$idx] = [int][string]$code[1] }
        }
    }
    foreach ($dc in $doorCells) {
        $x = $dc[0]; $y = $dc[1]; $idx = $y * $w + $x
        $solidWE = ($script:Tiles[$idx - 1] -gt 0) -and ($script:Tiles[$idx + 1] -gt 0)
        $solidNS = ($script:Tiles[$idx - $w] -gt 0) -and ($script:Tiles[$idx + $w] -gt 0)
        if (-not ($solidWE -xor $solidNS)) { throw "Door at $x,$y needs walls on exactly two opposite sides." }
        $d = [Door]::new()
        $d.X = $x; $d.Y = $y; $d.Vertical = $solidNS; $d.Lock = $dc[2]; $d.Channel = $dc[3]
        $d.TexId = if ($d.Lock -eq 4) { $script:TEX_DOOR_REMOTE } else { $script:TEX_DOOR + $d.Lock }
        $script:Tiles[$idx] = $script:TILE_DOOR_BASE + $script:Doors.Count
        $script:Doors.Add($d)
    }

    # ---- pass 2: areas = rooms separated by doors (secret walls count as floor) ---------------------
    $area = 0
    $stack = [System.Collections.Generic.Stack[int]]::new()
    for ($i = 0; $i -lt $n; $i++) {
        $open = ($script:Tiles[$i] -eq 0) -or ($script:PushTex[$i] -ne 0) -or $script:Breakable[$i]
        if (-not $open -or $script:AreaOf[$i] -ge 0) { continue }
        $stack.Push($i); $script:AreaOf[$i] = $area
        while ($stack.Count) {
            $c = $stack.Pop()
            foreach ($nb in ($c - 1), ($c + 1), ($c - $w), ($c + $w)) {
                if ($nb -lt 0 -or $nb -ge $n -or $script:AreaOf[$nb] -ge 0) { continue }
                if (($script:Tiles[$nb] -eq 0) -or ($script:PushTex[$nb] -ne 0) -or $script:Breakable[$nb]) { $script:AreaOf[$nb] = $area; $stack.Push($nb) }
            }
        }
        $area++
    }
    $script:AreaCount = $area
    $script:AreaConnect = New-Object 'int[,]' $area, $area
    $script:AreaByPlayer = [bool[]]::new($area)
    foreach ($d in $script:Doors) {
        $idx = $d.Y * $w + $d.X
        if ($d.Vertical) { $d.Area1 = $script:AreaOf[$idx - 1]; $d.Area2 = $script:AreaOf[$idx + 1] }
        else { $d.Area1 = $script:AreaOf[$idx - $w]; $d.Area2 = $script:AreaOf[$idx + $w] }
        if ($d.Area1 -lt 0 -or $d.Area2 -lt 0) { throw "Door at $($d.X),$($d.Y) leads nowhere." }
    }

    # ---- pass 3: things ---------------------------------------------------------------------------
    $playerSet = $false
    for ($y = 0; $y -lt $h; $y++) {
        $row = $map.Rows[$y]
        for ($x = 0; $x -lt $w; $x++) {
            $idx = $y * $w + $x
            if ($script:Tiles[$idx] -ne 0) { continue }
            $a = $row[$x * 2]; $b = $row[$x * 2 + 1]
            if ($a -ceq '.') { continue }
            if ($a -ceq 'P') {
                $script:StartX = $x + 0.5; $script:StartY = $y + 0.5; $script:StartAngle = (Get-DirFromChar $b) * 45.0
                $playerSet = $true
            }
            elseif ($a -ceq ':') { $script:TurnAt[$idx] = Get-DirFromChar $b }
            elseif ($a -ceq '@') {
                if (-not [char]::IsDigit($b)) { throw "Teleporter '@$b' at $x,$y needs a number" }
                Add-Teleporter ([int][string]$b) $x $y
            }
            elseif ($a -ceq '~') {
                if (-not $script:TrapCodes.ContainsKey($b)) { throw "Unknown trap '~$b' at $x,$y" }
                Add-Trap $script:TrapCodes[$b] $x $y
            }
            elseif ($a -ceq '+') {
                if (-not $script:ItemCodes.ContainsKey($b)) { throw "Unknown item '+$b' at $x,$y" }
                Add-Item $script:ItemCodes[$b] $x $y
                if ($script:ItemCodes[$b] -in $script:TreasureItems) { $script:Stats.TreasureTotal++ }
            }
            elseif ($a -ceq '*') {
                if (-not $script:DecoCodes.ContainsKey($b)) { throw "Unknown decoration '*$b' at $x,$y" }
                if ($b -ceq 'e') { Add-InertActor 'barrel' $x $y; continue }      # explosive barrels are shootable actors
                $deco = $script:DecoCodes[$b]
                $s = [Static]::new(); $s.X = $x; $s.Y = $y; $s.Sprite = $script:Spr[$deco[0]]; $s.Block = $deco[1]
                $script:Statics.Add($s)
                if ($s.Block) { $script:StaticBlock[$idx] = $true }
            }
            elseif ($script:EnemyCodes.ContainsKey($a)) {
                $dir = Get-DirFromChar $b
                if ($dir -lt 0) { throw "Enemy '$a$b' at $x,$y has no valid direction." }
                $mode = if ('NESW'.Contains([string]$b)) { 'patrol' } elseif ('nesw'.Contains([string]$b)) { 'ambush' } else { 'stand' }
                Add-Enemy $script:EnemyCodes[$a] $x $y $dir $mode
            }
            else { throw "Unknown map code '$a$b' at $x,$y" }
        }
    }
    if (-not $playerSet) { throw 'The map has no player start (P^ P> Pv P<).' }
}

function Add-Item([string]$Name, [int]$X, [int]$Y) {
    $s = [Static]::new()
    $s.X = $X; $s.Y = $Y; $s.Item = $Name
    $s.Sprite = $script:Spr[$(if ($Name -eq 'clip_small') { 'clip' } else { $Name })]
    $script:Statics.Add($s); $script:Items.Add($s)
}

function New-Enemy([string]$Kind, [int]$X, [int]$Y, [int]$Dir, [string]$Mode) {
    $def = $script:EnemyDefs[$Kind]
    $a = [Actor]::new()
    $a.Kind = $Kind; $a.Def = $def
    $a.X = $X + 0.5; $a.Y = $Y + 0.5; $a.TX = $X; $a.TY = $Y
    $a.Dir = $Dir; $a.PathDir = $Dir; $a.Speed = $def.Patrol
    $a.HP = $def.HP[$script:Difficulty]
    $a.Shootable = $true
    $a.Area = $script:AreaOf[$Y * $script:MapW + $X]
    $a.Ambush = ($Mode -eq 'ambush') -or ($Kind -in 'boss', 'uber')
    if ($Mode -eq 'patrol') {
        $a.State = "$Kind.path1"; $a.Active = $true
        $a.TX += $script:DirDX[$Dir]; $a.TY += $script:DirDY[$Dir]; $a.Dist = 1.0
    }
    else { $a.State = "$Kind.stand" }
    $t = $script:States[$a.State].Tics
    $a.Tics = if ($t -gt 0) { $script:Rng.NextDouble() * $t } else { 0 }
    $a
}

# Shootable scenery without a mind of its own (explosive barrels).
function Add-InertActor([string]$Kind, [int]$X, [int]$Y) {
    $a = [Actor]::new()
    $a.Kind = $Kind; $a.Def = $script:MiscDefs[$Kind]
    $a.X = $X + 0.5; $a.Y = $Y + 0.5; $a.TX = $X; $a.TY = $Y
    $a.HP = $a.Def.HP; $a.Shootable = $true
    $a.Area = $script:AreaOf[$Y * $script:MapW + $X]
    $a.State = "$Kind.idle"
    $script:ActorAt[$Y * $script:MapW + $X] = $a
    $script:Actors.Add($a)
}

function Add-Enemy([string]$Kind, [int]$X, [int]$Y, [int]$Dir, [string]$Mode) {
    $a = New-Enemy $Kind $X $Y $Dir $Mode
    $script:ActorAt[$a.TY * $script:MapW + $a.TX] = $a
    $script:Actors.Add($a)
    $script:Stats.KillTotal++
    if ($Kind -eq 'uber') { $script:Stats.KillTotal++ }          # its pilot counts as well
}
