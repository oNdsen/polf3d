# POLF 3D - Copyright (c) 2026 oNdsen. Licensed under the MIT License, see LICENSE.

<#
.SYNOPSIS
    Authoring tool: generates the campaign maps (maps/level1.map ... level10.map) from room lists.
.DESCRIPTION
    Typing grids of two-character cells by hand is error prone, so every floor is described as
    rooms (rectangles carved out of solid rock), doors and things. Rooms that touch or overlap
    merge into one space - that is how corridors and caves are made. The result is a plain text
    map; the game only ever reads the .map files, so they may be edited by hand afterwards.
    Run tools/Test-Level.ps1 to validate the result.

    The floors get harder: more and tougher enemies, fewer gifts, bigger bosses.
#>
[CmdletBinding()]
param([string]$OutDir = (Join-Path $PSScriptRoot '../maps'))

$script:grid = $null; $script:W = 0; $script:H = 0

function New-Grid([int]$Width, [int]$Height) {
    $script:W = $Width; $script:H = $Height
    $script:grid = New-Object 'string[,]' $Width, $Height          # $null = untouched rock
    $script:spawns = [System.Collections.Generic.List[string]]::new()
    $script:darks = [System.Collections.Generic.List[string]]::new()
}

# The room around this tile has no light: flashlight and muzzle flashes only.
function Add-Dark([int]$X, [int]$Y) {
    if ($script:grid[$X, $Y] -ne '..') { throw "Dark room marker $X,$Y is not on a free floor tile" }
    $script:darks.Add("@dark $X $Y")
}

# Reinforcements that only appear from difficulty $MinDifficulty (3 = Senior Engineer, 4 = root).
# Flat list with ABSOLUTE coordinates: x, y, code, ...
function Add-Spawns([int]$MinDifficulty, [object[]]$List) {
    for ($i = 0; $i -lt $List.Count; $i += 3) {
        $x = $List[$i]; $y = $List[$i + 1]
        if ($script:grid[$x, $y] -ne '..') { throw "Spawn $x,$y ('$($List[$i + 2])') is not on a free floor tile ('$($script:grid[$x, $y])')" }
        $script:spawns.Add("@spawn $MinDifficulty $x $y $($List[$i + 2])")
    }
}

function Set-Cell([int]$X, [int]$Y, [string]$Code) {
    if ($X -lt 1 -or $Y -lt 1 -or $X -ge $script:W - 1 -or $Y -ge $script:H - 1) { throw "Cell $X,$Y ('$Code') is on or beyond the map border" }
    $isWallCode = $Code -cmatch '^([SBWRMGT][A-Za-z]|[?!=].|D[DGSL0-9]|X[0-9])$'
    if (-not $isWallCode -and $script:grid[$X, $Y] -ne '..') { throw "Cell $X,$Y is not free ('$($script:grid[$X, $Y])') for '$Code'" }
    $script:grid[$X, $Y] = $Code
}

# Carves the interior and gives untouched rock around it this room's wall texture (first room wins).
# $Things: flat list dx, dy, code, ... RELATIVE to the room's top left floor tile.
function Add-Room([int]$X, [int]$Y, [int]$Width, [int]$Height, [string]$Wall, [object[]]$Things = @()) {
    for ($yy = $Y - 1; $yy -le $Y + $Height; $yy++) {
        for ($xx = $X - 1; $xx -le $X + $Width; $xx++) {
            if ($xx -lt 0 -or $yy -lt 0 -or $xx -ge $script:W -or $yy -ge $script:H) { throw "Room at $X,$Y reaches beyond the map" }
            $inside = $xx -ge $X -and $xx -lt $X + $Width -and $yy -ge $Y -and $yy -lt $Y + $Height
            if ($inside) { if ($script:grid[$xx, $yy] -notmatch '^\S\S$' -or $script:grid[$xx, $yy] -cmatch '^[SBWRMGT]') { $script:grid[$xx, $yy] = '..' } }
            elseif ($null -eq $script:grid[$xx, $yy]) { $script:grid[$xx, $yy] = $Wall }
        }
    }
    for ($i = 0; $i -lt $Things.Count; $i += 3) { Set-Cell ($X + $Things[$i]) ($Y + $Things[$i + 1]) $Things[$i + 2] }
}

# Solid blocks inside a room (shelves, a lift shaft): call AFTER the room has been carved.
function Add-Wall([int]$X, [int]$Y, [int]$Width, [int]$Height, [string]$Code) {
    for ($yy = $Y; $yy -lt $Y + $Height; $yy++) { for ($xx = $X; $xx -lt $X + $Width; $xx++) { Set-Cell $xx $yy $Code } }
}
function Add-Floor([int]$X, [int]$Y, [int]$Width, [int]$Height) {
    for ($yy = $Y; $yy -lt $Y + $Height; $yy++) { for ($xx = $X; $xx -lt $X + $Width; $xx++) { $script:grid[$xx, $yy] = '..' } }
}

function Add-Things([object[]]$List) {           # flat list with ABSOLUTE coordinates: x, y, code, ...
    for ($i = 0; $i -lt $List.Count; $i += 3) { Set-Cell $List[$i] $List[$i + 1] $List[$i + 2] }
}

# PowerShell everywhere. Called by Save-Level: some of the plain walls facing a room get a console, a poster, an
# error screen, a neon prompt or a graffito, and open stretches of wall get a server rack or a desk with a terminal
# in front of them. Which ones is decided by their coordinates, so the maps come out the same every time.
$script:SceneryWalls = @{
    SS = 'St', 'St', 'Sh', 'Sg'; BB = 'Bt', 'Bt'; WW = 'Wt', 'Wh'; RR = 'Rt', 'Rh', 'Rg'
    MM = 'Mt', 'Me', 'Mn'; GG = 'Gt', 'Gt'; TT = 'Tt', 'Tt', 'Te', 'Tn'
}
function Add-Scenery([int]$Salt) {
    $g = $script:grid; $w = $script:W; $h = $script:H
    $isFloor = { param($c) $null -ne $c -and $c -cnotmatch '^([SBWRMGT][A-Za-z]|[?!=].|D[DGSL0-9]|X[0-9])$' }
    $taken = @{}
    foreach ($sp in $script:spawns) { $f = $sp.Split(' '); $taken["$($f[2]),$($f[3])"] = $true }
    $near = @(-1, 0), @(1, 0), @(0, -1), @(0, 1)
    $terminals = 0; $spares = [System.Collections.Generic.List[object]]::new()
    for ($y = 1; $y -lt $h - 1; $y++) {
        for ($x = 1; $x -lt $w - 1; $x++) {
            $c = $g[$x, $y]
            if ($script:SceneryWalls.ContainsKey([string]$c)) {
                # a plain wall: decorate it if it faces a room and is no door frame
                $faces = $false; $frame = $false
                foreach ($n in $near) { $o = $g[($x + $n[0]), ($y + $n[1])]; if (& $isFloor $o) { $faces = $true } elseif ($o -cmatch '^D') { $frame = $true } }
                if ($faces -and -not $frame -and (($x * 31 + $y * 17 + $Salt * 7) % 6) -eq 0) {
                    $set = $script:SceneryWalls[$c]
                    $g[$x, $y] = $set[($x * 13 + $y * 7 + $Salt) % $set.Count]
                }
            }
            elseif ($c -eq '..' -and -not $taken["$x,$y"]) {
                $chosen = (($x * 29 + $y * 41 + $Salt * 3) % 9) -eq 0
                # open floor with a plain stretch of wall on exactly one side and nothing else around it
                $walls = 0; $clear = $true; $base = ''
                for ($dy = -1; $dy -le 1; $dy++) {
                    for ($dx = -1; $dx -le 1; $dx++) {
                        if ($dx -eq 0 -and $dy -eq 0) { continue }
                        $o = $g[($x + $dx), ($y + $dy)]
                        if ($o -eq '..') { continue }
                        if ($o -cmatch '^[SBWRMGT][A-Za-z]$' -and ($dx -eq 0 -or $dy -eq 0)) { $walls++; $base = $o[0] } elseif ($o -cmatch '^[SBWRMGT][A-Za-z]$') { } else { $clear = $false }
                    }
                }
                # ... and in the second row out nothing that blocks, so that nothing gets walled in
                for ($dy = -2; $dy -le 2 -and $clear; $dy++) { for ($dx = -2; $dx -le 2; $dx++) { $xx = $x + $dx; $yy = $y + $dy; if ($xx -lt 0 -or $yy -lt 0 -or $xx -ge $w -or $yy -ge $h) { continue }; $o = $g[$xx, $yy]; if ($o -cmatch '^(D.|\?.|\*[^lhsuk]|P.)$') { $clear = $false } } }      # no door, secret wall, other furniture or the start close by
                if ($walls -eq 1 -and $clear) {
                    if ($chosen -and $terminals -lt 6) { $g[$x, $y] = if ($base -in 'M', 'T') { '*r' } else { '*T' }; $terminals++ } else { $spares.Add(@($x, $y, $base)) }
                }
            }
        }
    }
    # every floor needs terminals (there are files to read on them): top up from the spares, spread over the map
    for ($k = 0; $terminals -lt 3 -and $spares.Count; $k++) {
        $pick = $spares[[int](($spares.Count - 1) * (0.2, 0.8, 0.5)[$k % 3])]
        $null = $spares.Remove($pick)
        $free = $true
        for ($dy = -2; $dy -le 2; $dy++) { for ($dx = -2; $dx -le 2; $dx++) { if ($g[($pick[0] + $dx), ($pick[1] + $dy)] -cin '*r', '*T') { $free = $false } } }
        if ($free) { $g[$pick[0], $pick[1]] = if ($pick[2] -in 'M', 'T') { '*r' } else { '*T' }; $terminals++ }
    }
}

function Save-Level([int]$Number, [string]$Name, [int]$Par, [string]$Ceiling, [string]$Floor, [string]$Rock, [string]$FilePrefix = 'level', [string[]]$Look = @()) {
    Add-Scenery ($Number + $(if ($FilePrefix -eq 'bonus') { 40 } else { 0 }))
    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add("; POLF 3D - $(if ($FilePrefix -eq 'bonus') { "secret floor reached from floor $Number" } else { "floor $Number" }). Generated by tools/New-Levels.ps1, may be edited by hand.")
    $lines.Add('; Every cell is TWO characters wide. Legend: see the header of src/Map.ps1 or the README.')
    $lines.Add('; Copyright (c) 2026 oNdsen. Licensed under the MIT License, see LICENSE.')
    $lines.Add("@name $Name"); $lines.Add("@par $Par"); $lines.Add("@ceiling $Ceiling"); $lines.Add("@floor $Floor")
    foreach ($l in $Look) { $lines.Add($l) }                      # @floortex / @ceiltex / @fog
    foreach ($sp in $script:spawns) { $lines.Add($sp) }
    foreach ($dk in $script:darks) { $lines.Add($dk) }
    $lines.Add('@map')
    for ($y = 0; $y -lt $script:H; $y++) {
        $sb = [System.Text.StringBuilder]::new()
        for ($x = 0; $x -lt $script:W; $x++) { $null = $sb.Append($(if ($null -eq $script:grid[$x, $y]) { $Rock } else { $script:grid[$x, $y] })) }
        $lines.Add($sb.ToString())
    }
    $null = New-Item -ItemType Directory -Path $OutDir -Force
    $file = Join-Path $OutDir "$FilePrefix$Number.map"
    [System.IO.File]::WriteAllLines($file, $lines)
    Write-Host ("floor {0}: {1,-22} {2}x{3}  -> {4}" -f $Number, $Name, $script:W, $script:H, $file)
}

# =====================================================================================================
# FLOOR 1 - Shellstein Dungeon.  Gentle start: guards and dogs, the first elites and mutants, all four
# secrets are generous. Ends with the commander (gold key) and an elite squad in front of the lift.
# =====================================================================================================
New-Grid 58 37
Add-Room 19 13 12 13 'SS'      # hub hall
Add-Room  6 24  3 12 'BB'      # cell corridor
Add-Room  2 32  3  4 'BB'      # start cell
Add-Room  2 26  3  4 'BB'      # second cell
Add-Room  4 16  8  7 'SS'      # guard room
Add-Room 13 18  5  3 'SS'      # passage guard room -> hub
Add-Room 23 27  3  3 'RR'      # passage hub -> kennels
Add-Room 14 30 13  6 'RR'      # kennels
Add-Room 15  5 11  7 'WW'      # officers' wing
Add-Room 32 14 12 11 'RR'      # storage
Add-Room 33 26 11 10 'MM'      # laboratory
Add-Room 45 15  8  9 'SS'      # commander's hall
Add-Room 27  2 14 10 'SS'      # last stand before the lift
Add-Room 42  6  3  3 'MM'      # lift
Add-Room 10 31  3  5 'RR'      # secret: kennels
Add-Room 18  1  5  3 'WW'      # secret: officers' wing
Add-Room 29 29  3  3 'MM'      # secret: laboratory
Add-Room 54 18  3  3 'SS'      # secret: commander's hall
Add-Things @(
    5, 33, 'DD',   5, 28, 'DD',   7, 23, 'DD',   12, 19, 'DD',   18, 19, 'DD'
    24, 26, 'DD',  21, 12, 'DD',  31, 19, 'DS',  38, 25, 'DD',   44, 19, 'DD'
    28, 12, 'DG',  41, 7, 'DL',   45, 7, 'MX'
    13, 33, '?r',  20, 4, '?w',   32, 30, '?M',  53, 19, '?s'
    9, 26, 'Bc',   9, 30, 'Bc',   9, 34, 'Bc',   5, 25, 'Bc',    5, 30, 'Bc'
    6, 15, 'Sb',   9, 15, 'Sb',   23, 12, 'Sb',  26, 12, 'Sb',   21, 26, 'Sb',  27, 26, 'Sb'
    18, 16, 'Sp',  18, 22, 'Sp',  31, 1, 'Sb',   36, 1, 'Sb',    53, 16, 'Sb',  53, 22, 'Sb'
    14, 8, 'Wp',   26, 7, 'Ws',   17, 4, 'Ws',   23, 4, 'Wp'
    31, 16, 'Rb',  44, 16, 'Rb',  13, 31, 'Rb'
    # start cell, cells, corridor
    3, 35, 'P^',   3, 32, '*k',   2, 33, '*s',   4, 34, '*u'
    2, 26, '+a',   3, 27, '+f',   4, 29, '*s'
    7, 27, 'g^',   7, 25, '*l',   7, 31, '*l',   8, 35, '+d'
    # guard room + passage
    5, 18, 'g>',   7, 21, 'gE',   5, 21, ':>',   10, 21, ':<'
    8, 18, '*t',   9, 18, '+f',   4, 16, '+a',   7, 19, '*l',    11, 16, '*L'
    16, 19, 'g<',  14, 19, '*l'
    # hub
    22, 16, '*c',  27, 16, '*c',  22, 22, '*c',  27, 22, '*c',   24, 19, '*h'
    24, 14, 'gE',  20, 14, ':>',  29, 14, ':v',  29, 24, ':<',   20, 24, ':^'
    26, 24, 'dW',  25, 17, 'gv',  30, 19, 'e<'
    19, 13, '+1',  30, 25, '+a',  19, 25, '+h',  30, 13, '*f'
    # kennels + secret
    16, 31, 'dE',  22, 31, 'dW',  15, 31, ':>',  25, 31, ':<'
    18, 34, 'dE',  24, 34, 'dW',  15, 34, ':>',  25, 34, ':<'
    20, 33, 'g^',  18, 32, '*b',  19, 32, '*b',  24, 28, '*l'
    14, 30, '+d',  26, 35, '+d',  14, 35, '+d',  26, 30, '+a'
    10, 31, '+m',  10, 35, '+2',  12, 35, '+a',  12, 31, '+1'
    # officers' wing + secret
    20, 6, 'ov',   16, 9, 'o>',   24, 10, 'g<'
    18, 8, '*t',   22, 8, '*t',   15, 5, '*p',   25, 5, '*p',    15, 11, '*a',  25, 11, '*a',  20, 8, '*h'
    16, 6, '+s',   24, 6, '+1',   25, 8, '+2',   17, 5, '+3',    19, 8, '+f'
    18, 1, '+p',   22, 1, '+4',   18, 3, '+u',   22, 3, '+a'
    # storage
    34, 16, '*x',  35, 16, '*x',  34, 17, '*x',  38, 20, '*x',   39, 20, '*x',  38, 21, '*x',  41, 15, '*x',  36, 23, '*x'
    42, 23, '*b',  43, 23, '*b',  36, 17, '*e',  40, 21, '*e',  37, 23, '*e'
    40, 18, 'e<',  33, 16, 'eS',  33, 23, ':^',  33, 14, ':v',   42, 19, 'g<',  43, 14, 'gw'
    32, 24, '+a',  41, 24, '+a',  37, 14, '+h',  43, 16, '+f'
    # laboratory + secret
    35, 28, '*v',  35, 32, '*v',  41, 28, '*v',  41, 32, '*v',   38, 31, '*l'
    38, 30, 'm^',  43, 27, 'mw',  33, 34, 'me',  42, 34, 'm<'
    33, 26, '+h',  43, 35, '+a',  38, 35, '+3'
    29, 29, '+c',  31, 29, '+a',  29, 31, '+h',  31, 31, '+a'
    # commander's hall + secret
    50, 19, 'b<',  47, 17, '*c',  47, 21, '*c',  52, 15, '*f',   52, 23, '*f',  49, 19, '*h'
    45, 15, '+h',  45, 23, '+h',  46, 15, '+a',  46, 23, '+a',   46, 19, '+q'
    54, 18, '+r',  56, 18, '+z',  54, 20, '+z',  56, 20, '+z'
    # last stand + lift
    34, 4, 'ev',   29, 3, 'ev',   39, 3, 'ev',   32, 6, 'ov',    36, 6, 'ov'
    30, 5, '*c',   37, 5, '*c',   30, 9, '*c',   37, 9, '*c'
    27, 2, '+h',   40, 2, '+h',   27, 11, '+a',  40, 11, '+a',   34, 2, '+2',   33, 11, '+a',  35, 11, '+h'
    43, 7, '*l'
)
Add-Spawns 3 @(23, 20, 'g<',  26, 18, 'g<',  37, 18, 'e<')
Add-Spawns 4 @(25, 21, 'e^',  38, 28, 'mv',  20, 10, 'ov')
Save-Level 1 'Shellstein Dungeon' 330 '383838' '6E6E6E' 'SS' -Look '@floortex flat_stone', '@ceiltex ceil_plain', '@fog 101010 16'

# =====================================================================================================
# FLOOR 2 - The Barracks.  One long corridor with patrols, dorms and a mess hall full of guards. The
# silver key lies in the office behind the mess hall; a commander holds the lift lobby.
# =====================================================================================================
New-Grid 50 36
Add-Room 3 18 40 4 'SS' @(                                   # main corridor
    5, 1, 'gE',   1, 1, ':>',   38, 1, ':<',   30, 2, 'gW',   1, 2, ':>',   38, 2, ':<'
    22, 0, 'o<',  12, 3, 'e>',  34, 0, 'h<',  6, 0, '*l',    16, 3, '*l',   26, 0, '*l',  36, 3, '*l',   0, 0, '*f',  0, 3, '*f')
Add-Room 3 23 5 5 'MM' @(2, 3, 'P^',  2, 1, '*l',  0, 0, '+a')                      # arrival
Add-Room 3 9 9 8 'WW' @(                                     # dorm A - some of them are asleep
    0, 0, '*B',  0, 2, '*B',  0, 4, '*B',  8, 0, '*B',  8, 2, '*B',  8, 4, '*B',  4, 3, '*t'
    2, 1, 'gn',  6, 3, 'gw',  3, 5, 'g>',  6, 6, 'gs',  4, 0, '+f',  8, 7, '+a',  0, 7, '+1',  8, 6, '+j')
Add-Room 13 9 9 8 'WW' @(                                    # dorm B
    0, 0, '*B',  0, 2, '*B',  0, 4, '*B',  8, 0, '*B',  8, 2, '*B',  8, 4, '*B'
    4, 2, 'ov',  6, 5, 'g<',  2, 6, 'gs',  8, 7, '+h',  0, 7, '+2')
Add-Room 23 6 12 11 'SS' @(                                  # mess hall
    2, 3, '*t',  6, 3, '*t',  2, 7, '*t',  6, 7, '*t',  4, 5, '*h',  9, 5, '*h'
    3, 2, 'gv',  7, 8, 'g^',  9, 4, 'g<',  1, 5, 'g>',  10, 1, 'e<',  10, 9, 'e<'
    3, 3, '+f',  7, 7, '+f',  0, 10, '+a')
Add-Room 25 2 8 3 'SS' @(1, 1, 'g>',  0, 0, '+f',  7, 0, '+f',  7, 2, '+d',  3, 0, '*b',  4, 0, '*b',  7, 1, '*e')       # kitchen
Add-Room 34 2 3 3 'SS' @(0, 0, '+3',  2, 0, '+a',  2, 2, '+h',  0, 2, '+2')                                          # cache behind the cracked kitchen wall
Add-Room 36 9 6 8 'WW' @(                                    # the office: silver key
    3, 3, 'o<',  4, 5, 'o<',  2, 1, 'e<',  4, 1, '*t',  5, 0, '+s',  5, 7, '+3',  0, 0, '*p',  0, 7, '*p',  5, 4, '*a')
Add-Room 10 23 8 7 'RR' @(                                   # armoury
    2, 3, 'e^',  6, 4, 'e^',  0, 0, '*x',  1, 0, '*x',  7, 0, '*x',  0, 6, '*x'
    2, 6, '+a',  6, 6, '+a',  7, 3, '+a',  3, 1, '+m',  0, 3, '+h',  5, 1, '*e',  6, 1, '*e')
Add-Room 20 23 9 8 'RR' @(                                   # kennels
    2, 2, 'dE',  1, 2, ':>',  7, 2, ':<',  6, 5, 'dW',  1, 5, ':>',  7, 5, ':<',  3, 5, 'dE',  4, 7, 'd^',  4, 3, 'g^'
    0, 0, '+d',  8, 0, '+d',  0, 7, '+d',  8, 7, '+d')
Add-Room 31 23 8 6 'BB' @(1, 1, '*u',  5, 3, '*u',  2, 4, '*u',  6, 1, 'g<',  1, 4, 'gn',  7, 5, '+h',  0, 0, '+a')   # wash room
Add-Room 44 15 5 8 'MM' @(3, 3, 'b<',  1, 1, 'e<',  3, 6, 'e<',  0, 7, '+a',  4, 7, '+h',  2, 4, '*l')             # lift lobby
Add-Room 45 11 3 3 'MM' @(1, 1, '*l')                                                                              # lift
Add-Room 15 5 5 3 'WW' @(0, 0, '+c',  4, 0, '+a',  0, 2, '+3',  4, 2, '+a')                                       # secret: dorm B
Add-Room 12 31 5 3 'RR' @(0, 0, '+u',  4, 0, '+4',  0, 2, '+a',  4, 2, '+q')                                       # secret: armoury
Add-Things @(
    5, 22, 'DD',   7, 17, 'DD',   17, 17, 'DD',  28, 17, 'DD',  29, 5, 'DD',   35, 12, 'DD'
    14, 22, 'D1',  42, 14, 'X1',  24, 22, 'DD',  35, 22, 'DD',  43, 19, 'DS',  46, 14, 'DL',  46, 10, 'MX'
    17, 4, 'MY',
    17, 8, '?w',   14, 30, '?r',  33, 3, '!S',   25, 17, '=S',  31, 17, '=S'
    12, 17, 'Sb',  22, 17, 'Sb',  32, 17, 'Sp',  38, 17, 'Sp',  9, 22, 'Sb',   19, 22, 'Sb',  30, 22, 'Sb',  40, 22, 'Sb'
    42, 12, 'Wp',  38, 8, 'Ws',   2, 12, 'Wp',   22, 12, 'Ws'
)
Add-Spawns 3 @(20, 21, 'g>',  31, 18, 'e<',  28, 11, 'ev')
Add-Spawns 4 @(48, 16, 'h<',  38, 21, 'o<',  15, 27, 'e^')
Save-Level 2 'The Barracks' 300 '403830' '6A6258' 'SS' -Look '@floortex flat_wood', '@ceiltex ceil_plain', '@fog 14100C 16'

# =====================================================================================================
# FLOOR 3 - The Catacombs.  Caves and crypts: dogs in the dark, mutants lying in ambush behind every
# pillar. Silver key in the officers' crypt, gold key in the vault, a commander guards the lift.
# =====================================================================================================
New-Grid 50 43
Add-Room 2 38 5 4 'GG' @(2, 2, 'P^',  0, 0, '*s',  4, 3, '+a',  4, 0, '+j')                       # arrival cave
Add-Room 4 30 2 8 'GG'
Add-Room 2 24 8 6 'GG' @(                                    # dog cave
    1, 1, 'dE',  0, 1, ':>',  7, 1, ':<',  6, 4, 'd<',  3, 4, 'd^',  4, 3, '*g',  7, 5, '*s',  0, 5, '+d',  7, 0, '+f')
Add-Room 10 26 8 2 'GG' @(6, 0, 'mW',  7, 0, ':<')
Add-Room 18 22 9 9 'GG' @(                                   # pillar crypt: ambush!
    2, 2, '*c',  6, 2, '*c',  2, 6, '*c',  6, 6, '*c',  0, 0, 'me',  8, 0, 'mw',  1, 8, 'me',  8, 8, 'mw',  4, 1, 'ms'
    4, 4, '+h',  1, 7, '*s',  7, 1, '*s')
Add-Room 21 14 2 8 'GG'
Add-Room 16 6 12 8 'SS' @(                                   # officers' crypt: silver key
    3, 2, 'ov',  8, 2, 'ov',  1, 5, 'g>',  10, 5, 'g<',  5, 3, '*t',  1, 0, '+s',  0, 0, '*a',  11, 0, '*a'
    10, 0, '+2', 6, 3, '+f',  4, 6, 'e^',  6, 5, 'hv')
Add-Room 27 25 8 2 'GG'
Add-Room 35 20 10 12 'GG' @(                                 # flooded hall
    2, 2, '*u',  6, 4, '*u',  3, 8, '*u',  7, 9, '*u',  5, 2, '*g',  2, 9, '*g',  8, 7, '*g'
    7, 5, 'e<',  8, 6, 'e<',  4, 1, 'ev',  5, 10, 'e^',  9, 2, 'g<',  9, 9, 'g<',  0, 0, '+a',  9, 11, '+h',  0, 11, '+a',  3, 4, 'mw',  3, 7, 'mw',  9, 5, 's<')
Add-Room 36 10 9 9 'BB' @(                                   # the vault: gold key
    4, 0, '+g',  2, 2, 'mv',  6, 2, 'mv',  4, 3, 'ov',  0, 0, '+3',  8, 0, '+3',  0, 8, '+2',  8, 8, '+4',  2, 5, '*c',  6, 5, '*c')
Add-Room 34 33 12 8 'SS' @(                                  # the commander's crypt
    6, 5, 'b^',  2, 4, 'm^',  10, 4, 'm^',  4, 6, 'e^',  8, 6, 'e^',  3, 2, '*c',  8, 2, '*c',  0, 7, '+h',  11, 7, '+h',  0, 0, '+a',  11, 0, '+a')
Add-Room 30 36 3 3 'MM' @(1, 1, '*l')                                                                              # lift
Add-Room 7 39 12 2 'GG'
Add-Room 19 34 8 8 'GG' @(6, 1, 'k<',  2, 6, 'k<',  5, 2, 'd<',  6, 5, 'd<',  3, 3, 'g<',  7, 0, '+a',  7, 7, '+a',  0, 0, '+f',  4, 1, '*g',  0, 7, '+t',  7, 3, '@1')
Add-Room 40 2 4 4 'GG' @(1, 1, '@1',  3, 0, '+u',  0, 3, '+4',  3, 3, '+a')                                          # sealed cave: teleporter only
Add-Room 22 31 2 3 'GG'
Add-Room 20 2 5 3 'SS' @(0, 0, '+p',  4, 0, '+u',  0, 2, '+a',  4, 2, '+a')                                       # secret: crypt
Add-Room 12 29 5 3 'GG' @(0, 0, '+c',  4, 0, '+a',  0, 2, '+h',  4, 2, '+1')                                       # secret: tunnel
Add-Room 46 13 3 3 'BB' @(0, 0, '+r',  2, 0, '+z',  0, 2, '+z',  2, 2, '+q')                                       # secret: vault
Add-Things @(
    3, 26, ':>',   11, 26, '~s',  11, 27, '~s'
    40, 19, 'DS',  40, 32, 'DG',  33, 37, 'DL',  29, 37, 'MX'
    22, 5, '?s',   14, 28, '?g',  45, 14, '?B'
    15, 9, 'Sb',   28, 9, 'Sb',   10, 25, 'Gv',  1, 27, 'Gv',   17, 24, 'Gv',  27, 28, 'Gv',  34, 22, 'Gv',  45, 28, 'Gv'
    6, 37, 'Gv',   18, 38, 'Gv',  27, 36, 'Gv',  35, 14, 'Bc',  45, 11, 'Bc',  33, 35, 'Sb',  46, 36, 'Sb'
)
Add-Spawns 3 @(21, 26, 'm>',  37, 27, 'k<',  24, 12, 'ov')
Add-Spawns 4 @(40, 28, 'e<',  39, 35, 'h^',  5, 27, 'd>')
Save-Level 3 'The Catacombs' 420 '1E2A1C' '4A5240' 'GG' -Look '@floortex flat_moss', '@ceiltex ceil_rock', '@fog 060C06 9'

# =====================================================================================================
# FLOOR 4 - Lab Zero.  A ring corridor with elite patrols around the reactor hall. The silver key is
# in lab B, the commander sits on the gold key in the server room, and behind the gold door waits
# the first war machine.
# =====================================================================================================
New-Grid 52 45
Add-Room 8 6 36 3 'TT'; Add-Room 8 6 3 27 'TT'; Add-Room 41 6 3 27 'TT'; Add-Room 8 30 36 3 'TT'      # the ring
Add-Room 25 9 3 3 'TT'; Add-Room 25 26 3 4 'TT'; Add-Room 11 18 4 3 'TT'; Add-Room 37 18 4 3 'TT'    # spokes
Add-Room 16 13 20 12 'TT' @(                                 # reactor hall
    8, 4, '*v',  11, 4, '*v',  8, 7, '*v',  11, 7, '*v',  3, 2, '*m',  16, 2, '*m',  3, 9, '*m',  16, 9, '*m'
    6, 2, 'ev',  13, 2, 'ev',  6, 9, 'e^',  13, 9, 'e^',  0, 0, 'me',  19, 0, 'mw',  0, 11, 'me',  19, 11, 'mw',  15, 5, 'o<'
    9, 5, '+h',  10, 6, '+a',  9, 9, 'h^',  10, 2, 'hv')
Add-Room 2 28 5 5 'MM' @(2, 2, 'P>',  2, 1, '*l',  0, 0, '+a',  0, 4, '+h')                                          # arrival
Add-Room 12 1 10 4 'TT' @(1, 0, '*v',  8, 0, '*v',  4, 0, '*m',  3, 1, 'mv',  6, 1, 'mv',  9, 3, 'ms',  9, 0, '+h',  0, 3, '+a')     # lab A
Add-Room 30 1 12 4 'TT' @(0, 0, '*v',  3, 0, '*v',  8, 0, '*v',  11, 0, '*v',  11, 3, '+s',  5, 1, 'ov',  2, 2, 'mv',  9, 2, 'mv',  10, 1, 'e<',  0, 3, '+f',  11, 1, '*e')   # lab B
Add-Room 43 1 3 3 'TT' @(0, 0, '+o',  2, 0, '+o',  2, 2, '+h',  0, 2, '+z')                                          # cache behind the cracked lab wall
Add-Room 45 10 6 10 'RR' @(                                  # storage
    1, 0, '*x',  2, 0, '*x',  5, 3, '*x',  2, 5, '*x',  3, 5, '*x',  0, 8, '*x',  5, 9, '*x'
    3, 3, 'e<',  4, 7, 'g<',  5, 0, 'gw',  0, 0, '+a',  1, 9, '+a',  4, 9, '+a',  5, 5, '+m',  0, 5, '+h',  4, 4, '*e',  1, 6, '*e',  3, 9, '+l')
Add-Room 45 22 6 9 'TT' @(                                   # server room: commander + gold key
    1, 0, '*m',  3, 0, '*m',  5, 0, '*m',  1, 8, '*m',  3, 8, '*m',  3, 4, 'b<',  4, 2, 'e<',  4, 6, 'e<',  0, 8, '+h',  0, 0, '+a')
Add-Room 14 34 12 5 'BB' @(                                  # holding cells
    5, 2, 'k^',  7, 3, 'k^',  1, 1, '*s',  9, 3, '*s',  4, 2, '*u',  2, 3, 'm^',  8, 2, 'm^',  11, 4, 'mn',  11, 0, '+f',  6, 4, '+h',  3, 0, '+a')
Add-Room 28 34 13 9 'MM' @(                                  # hangar of the war machine
    6, 6, 'u^',  3, 3, '*c',  9, 3, '*c',  3, 6, '*c',  9, 6, '*c',  1, 7, 'e^',  11, 7, 'e^'
    0, 0, '+h',  12, 0, '+h',  0, 8, '+a',  12, 8, '+a',  6, 8, '+z',  6, 2, '*e',  1, 4, '*e',  11, 4, '*e',  5, 0, '+o',  7, 0, '+o')
Add-Room 42 35 3 3 'MM' @(1, 1, '*l')                                                                               # lift
Add-Room 8 1 3 3 'TT' @(0, 0, '+p',  2, 0, '+a',  0, 2, '+a',  2, 2, '+2')                                          # secret: lab A
Add-Room 46 6 5 3 'RR' @(0, 0, '+z',  4, 0, '+z',  0, 2, '+q',  4, 2, '+r')                                         # secret: storage
Add-Room 10 35 3 3 'BB' @(0, 0, '+c',  2, 0, '+a',  0, 2, '+a',  2, 2, '+3')                                        # secret: cells
Add-Things @(
    # three patrols walk the ring clockwise
    8, 6, 's>',    43, 32, 's<',  25, 27, '~s',  26, 27, '~s',  27, 27, '~s',  38, 18, '~c',  38, 19, '~c',  38, 20, '~c',
    12, 7, 'eE',   30, 31, 'eW',  42, 15, 'mS',  42, 7, ':v',  42, 31, ':<',  9, 31, ':^',  9, 7, ':>'
    7, 30, 'DD',   16, 5, 'DD',   35, 5, 'DD',   44, 14, 'DD',  44, 26, 'DS',  19, 33, 'DD',  34, 33, 'DG'
    26, 12, 'DD',  26, 25, 'DD',  15, 19, 'DD',  36, 19, 'DD',  41, 36, 'DL',  45, 36, 'MX'
    11, 2, '?T',   48, 9, '?R',   13, 36, '?B',  42, 2, '!T',   15, 18, '=T',  15, 20, '=T'
    20, 5, 'Tl',   28, 5, 'Tl',   40, 5, 'Tl',   7, 12, 'Tl',   7, 20, 'Tl',   12, 33, 'Tl',  28, 33, 'Tl',  40, 33, 'Tl'
    20, 12, 'Tl',  32, 12, 'Tl',  20, 25, 'Tl',  32, 25, 'Tl',  15, 15, 'Tl',  15, 23, 'Tl',  36, 15, 'Tl',  36, 23, 'Tl'
    16, 39, 'Bc',  22, 39, 'Bc',  44, 20, 'Tl',  44, 10, 'Tl'
)
Add-Spawns 3 @(20, 19, 'e>',  20, 30, 'm>',  33, 8, 'm<')
Add-Spawns 4 @(30, 36, 'h>',  38, 36, 'h<',  47, 24, 's<')
Save-Level 4 'Lab Zero' 480 '20262E' '4A525C' 'TT' -Look '@floortex flat_tech', '@ceiltex ceil_tech', '@fog 0A1018 14'

# =====================================================================================================
# FLOOR 5 - The Citadel.  The end of the first half: a gate hall, the great hall with three patrols, mutants in the
# west tower (silver key), TWO commanders in the east tower (gold key) and, in the throne hall, the
# war machine with its escort.
# =====================================================================================================
New-Grid 48 46
Add-Room 12 16 24 15 'SS' @(                                 # great hall
    4, 3, '*c',  9, 3, '*c',  14, 3, '*c',  19, 3, '*c',  4, 11, '*c',  9, 11, '*c',  14, 11, '*c',  19, 11, '*c'
    11, 7, '*h',  6, 7, '*h',  17, 7, '*h'
    3, 1, 'eE',  18, 13, 'eW',  22, 6, 'oS',  22, 1, ':v',  22, 13, ':<',  1, 13, ':^',  1, 1, ':>'
    2, 3, 's>',  21, 3, 's<',  8, 5, 'ov',  15, 5, 'ov',  6, 9, 'mv',  17, 9, 'mv',  3, 7, 'g>',  20, 7, 'g<',  11, 3, 'ev'
    0, 0, '+h',  23, 0, '+h',  0, 14, '+a',  23, 14, '+a',  11, 8, '+3')
Add-Room 21 40 6 4 'MM' @(2, 2, 'P^',  0, 0, '+h',  5, 0, '+a')                                                     # arrival
Add-Room 17 32 14 7 'SS' @(                                  # gate hall
    5, 2, 'hv',  8, 2, 'hv',  3, 1, 'gv',  10, 1, 'gv',  7, 1, 'ev',  2, 5, 'dE',  0, 5, ':>',  13, 5, ':<',  11, 3, 'dW',  0, 3, ':>',  13, 3, ':<'
    0, 0, '*f',  13, 0, '*f',  0, 6, '+a',  13, 6, '+a')
Add-Room 3 18 8 10 'BB' @(                                   # west tower: silver key
    0, 0, '+s',  1, 2, 'm>',  1, 7, 'm>',  4, 4, 'me',  3, 9, 'm>',  5, 1, 'm>',  6, 1, '*s',  2, 5, '*s',  5, 8, '*u'
    0, 9, '+h',  7, 0, '+c',  7, 9, '+t',  6, 9, '@1')
Add-Room 41 32 3 3 'SS' @(1, 1, '@1',  0, 0, '+o',  2, 0, '+h',  2, 2, '+a')                                         # sealed closet: teleporter only
Add-Room 37 18 8 10 'RR' @(                                  # east tower: two commanders, one gold key each
    5, 2, 'b<',  5, 7, 'b<',  2, 4, 'e<',  7, 0, '*x',  7, 9, '*x',  0, 0, '*x',  0, 9, '+a',  7, 5, '+h',  7, 4, '+z',  3, 1, '*e',  3, 8, '*e')
Add-Room 14 3 20 12 'MM' @(                                  # throne hall
    7, 4, 'kv',  12, 4, 'kv',  10, 1, 'uv',  3, 3, 'ev',  16, 3, 'ev',  0, 0, 'ms',  19, 0, 'ms',  6, 2, 'ov',  13, 2, 'ov'
    4, 5, '*c',  15, 5, '*c',  4, 9, '*c',  15, 9, '*c',  9, 7, '*c',  10, 7, '*c'
    0, 11, '+h',  19, 11, '+h',  1, 11, '+a',  18, 11, '+a',  8, 11, '+z',  10, 11, '+q',  2, 11, '+o',  17, 11, '+o',  8, 9, '~s',  9, 9, '~s',  10, 9, '~s',  11, 9, '~s')
Add-Room 35 7 3 3 'MM' @(1, 1, '*l')                                                                                # lift
Add-Room 35 3 3 2 'MM' @(0, 0, '+z',  2, 0, '+o',  1, 1, '+h')                                                       # cache behind a cracked wall
Add-Room 8 29 3 3 'SS' @(0, 0, '+z',  2, 0, '+z',  0, 2, '+u',  2, 2, '+a')                                         # secret: west
Add-Room 37 29 3 3 'SS' @(0, 0, '+q',  2, 0, '+4',  0, 2, '+a',  2, 2, '+h')                                        # secret: east
Add-Room 10 7 3 3 'MM' @(0, 0, '+r',  2, 0, '+z',  0, 2, '+z',  2, 2, '+p')                                         # secret: throne hall
Add-Things @(
    23, 39, 'DD',  23, 31, 'DD',  11, 23, 'D2',  31, 34, 'X2',  36, 23, 'DS',  23, 15, 'DG',  34, 8, 'DL',  38, 8, 'MX'
    11, 30, '?s',  36, 30, '?s',  13, 8, '?M',   34, 4, '!M',   11, 21, '=S',  11, 25, '=S'
    14, 15, 'Sb',  18, 15, 'Sb',  28, 15, 'Sb',  32, 15, 'Sb',  14, 31, 'Sb',  32, 31, 'Sb',  11, 19, 'Sp',  36, 19, 'Sp'
    2, 20, 'Bc',   2, 25, 'Bc',   45, 22, 'Rb',  16, 39, 'Sb',  31, 35, 'Sb'
)
Add-Spawns 3 @(24, 20, 'ev',  22, 26, 'mv',  39, 20, 'e<')
Add-Spawns 4 @(20, 8, 'hv',  27, 8, 'hv',  6, 23, 'k>')
Save-Level 5 'The Citadel' 540 '30203A' '5A5060' 'SS' -Look '@floortex flat_carpet', '@ceiltex ceil_plain', '@fog 140A1C 15'

# =====================================================================================================
# FLOOR 6 - The Data Centre.  Six cold aisles between two cross corridors: snipers at the far ends,
# windows in the rack rows. Silver key in the NOC, the commander sits in the silver cage on the gold
# key, the lift lobby is behind the gold door.
# =====================================================================================================
New-Grid 56 42
Add-Room 12 30 25 3 'TT' @(                                  # south cross corridor, one patrol
    2, 1, 'eE',   0, 1, ':>',   23, 1, ':<',  4, 0, '*l',   12, 0, '*l',  20, 0, '*l',  8, 2, 'o^',  18, 2, 'h<')
Add-Room 12 9 36 3 'TT' @(                                   # north cross corridor
    30, 1, 'oW',  0, 1, ':>',   35, 1, ':<',  6, 0, '*l',   16, 0, '*l',  26, 0, '*l',  10, 0, 'ev',  20, 2, 'h<',  35, 0, '+a',  0, 2, '+f')
foreach ($ax in 12, 16, 20, 24, 28, 32) { Add-Room $ax 12 3 18 'TT' }                                               # the aisles
Add-Room 2 36 5 4 'MM' @(2, 2, 'P^',  2, 1, '*l',  0, 0, '+a',  4, 0, '+h')                                         # arrival
Add-Room 2 24 9 11 'RR' @(                                   # loading dock
    0, 0, '*x',  1, 0, '*x',  8, 0, '*x',  0, 5, '*x',  7, 6, '*x',  8, 6, '*x',  8, 10, '*x',  3, 3, '*e',  6, 8, '*e'
    4, 2, 'gv',  6, 5, 'e<',  2, 8, 'g>',  7, 3, 'd<',  0, 10, '+a',  8, 1, '+a',  0, 1, '+f',  4, 5, '+m')
Add-Room 2 9 9 14 'MM' @(                                    # cooling plant
    1, 1, '*v',  1, 4, '*v',  1, 7, '*v',  1, 10, '*v',  6, 2, '*v',  6, 6, '*v',  6, 10, '*v'
    3, 3, 'me',  7, 8, 'mw',  4, 0, 'ms',  3, 12, 'mn',  8, 12, 'm>',  4, 6, 'o>'
    0, 13, '+h',  8, 0, '+a',  0, 0, '+2',  8, 13, '+z')
Add-Room 38 13 10 8 'TT' @(                                  # network operations centre: silver key
    1, 0, '*m',  3, 0, '*m',  5, 0, '*m',  7, 0, '*m',  4, 4, '*t',  5, 4, '*t'
    2, 3, 'o^',  7, 3, 'o^',  4, 6, 'e^',  8, 6, 'e<',  9, 7, 's<',  9, 0, '+s',  0, 7, '+a',  0, 0, '+3')
Add-Room 38 22 11 11 'MM' @(                                 # the silver cage: the commander
    6, 5, 'b<',  3, 2, 'e<',  3, 8, 'e<',  1, 5, 'h<',  4, 3, '*c',  4, 7, '*c',  8, 3, '*c',  8, 7, '*c'
    10, 0, '+h',  10, 10, '+h',  0, 0, '+a',  9, 5, '+o')
Add-Room 40 3 9 5 'MM' @(2, 1, 'hv',  6, 1, 'hv',  4, 0, 'sv',  7, 2, 'k<',  0, 2, 'k>',  0, 0, '+h',  8, 4, '+a')      # lift lobby
Add-Room 50 4 3 3 'MM' @(1, 1, '*l')                                                                                # lift
Add-Room 2 5 4 3 'MM' @(0, 0, '+u',  3, 0, '+4',  0, 2, '+a',  3, 2, '+q')                                          # secret: plant
Add-Room 20 34 5 3 'TT' @(0, 0, '+c',  4, 0, '+a',  0, 2, '+3',  4, 2, '+a')                                        # secret: south corridor
Add-Room 50 25 3 3 'MM' @(0, 0, '+z',  2, 0, '+4',  0, 2, '+o',  2, 2, '+h')                                        # secret: cage
Add-Room 20 5 4 3 'TT' @(0, 0, '+o',  3, 0, '+o',  0, 2, '+h',  3, 2, '+z')                                         # cache behind a cracked wall
Add-Things @(
    4, 35, 'DD',   5, 23, 'DD',   11, 31, 'DD',  11, 10, 'DD',  42, 12, 'DD',  37, 31, 'DS',  44, 8, 'DG',  49, 5, 'DL',  53, 5, 'MX'
    19, 20, 'DD',  27, 20, 'DD',  15, 16, '=T',  15, 24, '=T',  23, 16, '=T',  23, 24, '=T',  31, 16, '=T',  31, 24, '=T'
    3, 8, '?M',    22, 33, '?T',  49, 26, '?M',  21, 8, '!T'
    13, 13, 'sv',  21, 13, 'sv',  29, 13, 'sv',  17, 20, 'ev',  25, 18, 'e^',  33, 22, 'ev',  13, 22, 'hv',  29, 24, 'hv',  21, 25, 'kv',  33, 14, 'kv'
    17, 14, '+a',  25, 27, '+a',  33, 28, '+h',  13, 28, '+o'
    # security: cameras at the east ends of both corridors, sentry guns in the lift lobby and in the cage
    47, 11, 'cw',  36, 30, 'cw',  44, 5, 'ts',   47, 31, 'tw'
)
Add-Spawns 3 @(14, 20, 'ev',  25, 30, 'h<',  43, 18, 'e^')
Add-Spawns 4 @(45, 29, 'h<',  5, 15, 'm>',  30, 9, 's<')
Add-Dark 5 15                                                 # the cooling plant
Save-Level 6 'The Data Centre' 600 '1C2430' '46505C' 'TT' -Look '@floortex flat_tech', '@ceiltex ceil_tech', '@fog 081420 13'

# =====================================================================================================
# FLOOR 7 - The Archive.  Two halls of shelves to get lost in, with things waiting between them. The
# silver key is in the catalogue room, the commander in the tape vault has the gold key, and the
# reading room behind the gold door leads to the lift. Four secrets - the microfiche knows them all.
# =====================================================================================================
New-Grid 54 44
Add-Room 19 29 15 8 'WW' @(                                  # foyer
    3, 2, '*c',  11, 2, '*c',  3, 5, '*c',  11, 5, '*c',  7, 3, '*h',  0, 0, '*p',  14, 0, '*p'
    7, 1, 'ov',  5, 4, 'g>',  9, 4, 'g<',  0, 7, '+a',  14, 7, '+h')
Add-Room 24 38 5 4 'MM' @(2, 2, 'P^',  2, 1, '*l',  0, 0, '+a',  4, 0, '+f')                                        # arrival
Add-Room 3 21 15 18 'WW' @(                                  # west stacks
    2, 3, 'ge',  12, 4, 'g<',  7, 6, 'ov',  3, 10, 'e>',  11, 10, 'h<',  6, 13, 'gn',  13, 16, 'k<',  2, 16, 'd>'
    0, 0, '+a',  14, 0, '+3',  0, 17, '+h',  14, 17, '+a',  7, 3, '+f',  5, 9, '+2')
Add-Room 35 21 15 18 'WW' @(                                 # east stacks
    12, 3, 'mw',  2, 4, 'g>',  7, 7, 's<',  10, 10, 'e<',  3, 13, 'hn',  13, 14, 'k<',  1, 16, 'o>',  4, 0, 'sv'
    0, 0, '+2',  14, 0, '+a',  0, 17, '+a',  14, 17, '+h',  7, 4, '+o',  9, 13, '+z')
foreach ($ox in 3, 35) {                                     # the shelves, the same in both halls
    Add-Wall ($ox + 1) 23 5 1 'Ws';  Add-Wall ($ox + 8) 23 6 1 'Ws'
    Add-Wall $ox 26 4 1 'Ws';        Add-Wall ($ox + 6) 26 4 1 'Ws';   Add-Wall ($ox + 12) 26 3 1 'Ws'
    Add-Wall ($ox + 1) 29 6 1 'Ws';  Add-Wall ($ox + 9) 29 5 1 'Ws'
    Add-Wall $ox 33 5 1 'Ws';        Add-Wall ($ox + 7) 33 4 1 'Ws';   Add-Wall ($ox + 13) 33 2 1 'Ws'
    Add-Wall ($ox + 1) 36 5 1 'Ws';  Add-Wall ($ox + 8) 36 6 1 'Ws'
}
Add-Room 24 21 5 7 'WW' @(1, 1, 'sv',  3, 1, 'ev',  0, 0, '*a',  4, 0, '*a')                                         # passage to the reading room
Add-Room 3 8 12 12 'WW' @(                                   # catalogue room: silver key
    3, 3, '*t',  8, 3, '*t',  3, 8, '*t',  8, 8, '*t',  11, 0, '+s'
    5, 5, 'ov',  2, 2, 'o>',  9, 9, 'o<',  6, 1, 'ev',  10, 6, 'e<',  5, 10, 'hv',  0, 0, '+1',  0, 11, '+a',  11, 11, '+f')
Add-Room 38 8 12 12 'BB' @(                                  # tape vault: the commander
    6, 4, 'bv',  10, 1, 'mw',  1, 10, 'me',  4, 7, 'ev',  8, 7, 'ev'
    3, 3, '*c',  8, 3, '*c',  3, 8, '*c',  8, 8, '*c',  0, 0, '+h',  11, 0, '+h',  0, 11, '+a',  11, 11, '+a',  6, 0, '+3')
Add-Room 19 8 15 12 'WW' @(                                  # reading room
    3, 3, '*t',  7, 3, '*t',  11, 3, '*t',  3, 8, '*t',  7, 8, '*t',  11, 8, '*t',  5, 5, '*h',  9, 5, '*h'
    4, 1, 'ev',  10, 1, 'ev',  7, 2, 'ov',  2, 6, 'h>',  12, 6, 'h<',  1, 10, 'k^',  13, 10, 'k^',  7, 6, 'sv'
    0, 0, '+h',  14, 0, '+a',  0, 11, '+a',  14, 11, '+3')
Add-Room 25 4 3 3 'MM' @(1, 1, '*l')                                                                                # lift
Add-Room 35 12 2 3 'WW' @(0, 0, '+o',  1, 0, '+o',  0, 2, '+h',  1, 2, '+u')                                        # cache behind a cracked wall
Add-Room 5 4 4 3 'WW' @(0, 0, '+4',  3, 0, '+a',  0, 2, '+h',  3, 2, '+z')                                          # secret: catalogue room
Add-Room 44 4 4 3 'BB' @(0, 0, '+c',  3, 0, '+a',  0, 2, '+4',  3, 2, '+q')                                         # secret: tape vault
Add-Room 19 38 3 3 'WW' @(0, 0, '+a',  2, 0, '+2',  0, 2, '+f',  2, 2, '+t')                                        # secret: foyer
Add-Room 51 30 2 3 'WW' @(0, 0, '+3',  1, 0, '+3',  0, 2, '+a',  1, 2, '+h')                                        # secret: east stacks
Add-Things @(
    26, 37, 'DD',  18, 32, 'DD',  34, 32, 'DD',  26, 28, 'DD',  26, 20, 'DG',  8, 20, 'DD',  43, 20, 'DS',  26, 7, 'DL',  26, 3, 'MX'
    6, 7, '?w',    45, 7, '?B',   20, 37, '?w',  50, 31, '?W',  34, 13, '!W'
    18, 25, 'Wp',  34, 25, 'Wp',  2, 14, 'Wp',   15, 14, 'Wp',  23, 24, 'Wp',  29, 24, 'Wp'
    24, 27, 'cn',  3, 13, 'ce',   26, 17, 'ts'           # a camera in the passage and in the catalogue room, a sentry gun behind the gold door
)
Add-Spawns 3 @(26, 33, 'ov',  9, 14, 'o>',  43, 15, 'ev')
Add-Spawns 4 @(24, 15, 'h^',  10, 30, 'k>',  42, 30, 's<')
Add-Dark 43 14                                                # the tape vault
Save-Level 7 'The Archive' 660 '3A2C1C' '6A5A40' 'WW' -Look '@floortex flat_wood', '@ceiltex ceil_plain', '@fog 120C06 12'

# =====================================================================================================
# FLOOR 8 - The Foundry.  A production line: the smelter, then the conveyor with three crushers and a
# gate in the middle. Three levers (control room, machine shop, storage) open the way, the armoury
# included. Silver key in the machine shop, the foreman behind the silver door has the gold key - and
# in the assembly hall behind the gold door stands THE PRINTER.
# =====================================================================================================
New-Grid 60 40
Add-Room 8 24 14 13 'RR' @(                                  # smelter
    3, 2, '*v',  7, 2, '*v',  11, 2, '*v',  3, 6, '*v',  11, 6, '*v',  7, 6, '*e',  5, 10, '*e',  9, 10, '*e'
    5, 4, 'e>',  9, 4, 'ev',  12, 9, 'h<',  6, 8, 'mv',  10, 8, 'm<',  1, 5, 'me',  12, 1, 'sw',  12, 11, 'k<'
    0, 0, '+a',  13, 0, '+f',  0, 12, '+h',  13, 12, '+a',  6, 12, '+o')
Add-Room 2 33 5 4 'MM' @(1, 2, 'P>',  2, 1, '*l',  0, 0, '+a',  4, 0, '+h')                                         # arrival
Add-Room 8 18 8 5 'MM' @(1, 0, '*m',  3, 0, '*m',  6, 0, '*m',  2, 2, 'ov',  5, 2, 'ov',  7, 4, 'e<',  0, 4, '+a',  7, 0, '+2')       # control room: lever 1
Add-Room 23 28 26 3 'MM'                                     # the conveyor
Add-Room 26 17 14 10 'RR' @(                                 # machine shop: silver key, lever 2
    2, 2, '*t',  6, 2, '*t',  10, 2, '*t',  2, 6, '*t',  6, 6, '*t',  10, 6, '*t',  13, 0, '*x',  13, 9, '*x',  0, 9, '*x'
    4, 4, 'ev',  8, 4, 'ev',  12, 4, 'o<',  1, 7, 'm>',  11, 8, 'h<',  7, 8, 'k^',  0, 0, '+s',  12, 0, '+a',  5, 9, '+h')
Add-Room 26 32 14 6 'RR' @(                                  # storage: the foreman, lever 3
    0, 0, '*x',  1, 0, '*x',  0, 1, '*x',  12, 0, '*x',  13, 0, '*x',  6, 3, '*x',  7, 3, '*x'
    10, 3, 'b<',  4, 2, 'e^',  4, 4, 'e^',  13, 5, '+h',  0, 5, '+a',  12, 5, '+o',  8, 5, '+z')
Add-Room 43 32 5 4 'MM' @(0, 0, '+l',  4, 0, '+o',  0, 3, '+o',  4, 3, '+h',  2, 2, '+c',  2, 3, '+u')                 # armoury behind lever door 3
Add-Room 50 18 8 18 'MM' @(                                  # assembly hall: THE PRINTER
    2, 3, '*c',  5, 3, '*c',  2, 8, '*c',  5, 8, '*c',  2, 13, '*c',  5, 13, '*c'
    3, 6, 'uv',  1, 1, 'kv',  6, 1, 'kv',  1, 15, 'e^',  6, 15, 'e^'
    0, 0, '+h',  7, 0, '+h',  0, 17, '+a',  7, 17, '+a',  0, 9, '+o',  7, 9, '+o')
Add-Room 53 14 3 3 'MM' @(1, 1, '*l')                                                                               # lift
Add-Room 3 26 4 3 'RR' @(0, 0, '+a',  0, 2, '+3',  1, 0, '+t')                                                      # secret: smelter
Add-Room 41 18 3 3 'RR' @(0, 0, '+4',  2, 0, '+a',  0, 2, '+a',  2, 2, '+q')                                        # secret: machine shop
Add-Room 52 37 3 2 'MM' @(0, 0, '+4',  2, 0, '+4',  0, 1, '+r',  2, 1, '+a')                                        # secret: assembly hall
Add-Room 17 18 3 3 'MM' @(0, 0, '+o',  2, 0, '+o',  0, 2, '+z',  2, 2, '+h')                                        # cache behind a cracked wall
Add-Things @(
    7, 35, 'DD',   11, 23, 'DD',  22, 29, 'D1',  12, 17, 'X1',  32, 27, 'DD',  30, 16, 'X2',  32, 31, 'DS',  40, 35, 'X3',  45, 31, 'D3'
    41, 28, 'MM',  41, 30, 'MM',  41, 29, 'D2',  49, 29, 'DG',  54, 17, 'DL',  54, 13, 'MX'
    7, 27, '?r',   40, 19, '?R',  53, 36, '?M',  16, 19, '!M'
    26, 28, '~c',  26, 29, '~c',  26, 30, '~c',  36, 28, '~c',  36, 29, '~c',  36, 30, '~c',  44, 28, '~c',  44, 29, '~c',  44, 30, '~c'
    30, 29, 'e<',  33, 28, 'h<',  38, 30, 'e<',  39, 28, 's<',  47, 29, 'h<',  46, 28, 'k<',  46, 30, 'k<',  24, 28, '+a',  48, 30, '+a'
    7, 30, 'Rb',   22, 26, 'Rb',  22, 33, 'Rb',  25, 21, 'Rb',  25, 35, 'Rb'
    21, 30, 'cw',  48, 28, 'tw'                          # a camera over the smelter, a sentry gun at the end of the conveyor
)
Add-Spawns 3 @(16, 31, 'e<',  34, 22, 'ev',  52, 30, 'h^')
Add-Spawns 4 @(55, 22, 'hv',  24, 29, 's>',  35, 34, 'e^')
Add-Dark 31 35                                                # the storage
Save-Level 8 'The Foundry' 660 '2E1C14' '5A463A' 'RR' -Look '@floortex flat_stone', '@ceiltex ceil_rock', '@fog 1C0C04 12'

# =====================================================================================================
# FLOOR 9 - The Executive Floor.  Carpet, plants and a long gallery with offices on both sides. The
# silver key is in the CFO's office, the board - two commanders - meets behind the silver door, and
# the CEO's office behind the gold door has a lift of its own. And a printer.
# =====================================================================================================
New-Grid 56 42
Add-Room 4 22 47 3 'WW' @(                                   # the gallery, one patrol
    2, 1, 'oE',  0, 1, ':>',  46, 1, ':<',  7, 0, '*a',  17, 0, '*a',  29, 0, '*a',  39, 0, '*a',  7, 2, '*a',  17, 2, '*a',  29, 2, '*a',  39, 2, '*a'
    0, 2, 'o>',  46, 2, 's<',  12, 0, 'ev',  34, 0, 'hv')
Add-Room 25 36 5 4 'MM' @(2, 2, 'P^',  2, 1, '*l',  0, 0, '+a',  4, 0, '+h')                                        # arrival
Add-Room 20 26 15 9 'WW' @(                                  # reception
    0, 0, '*p',  14, 0, '*p',  0, 8, '*p',  14, 8, '*p',  5, 3, '*t',  6, 3, '*t',  8, 3, '*t',  9, 3, '*t',  7, 5, '*h'
    7, 2, 'ov',  4, 2, 'gv',  10, 2, 'gv',  12, 6, 'h<',  1, 8, '+a',  13, 8, '+f')
Add-Room 4 26 6 7 'WW' @(2, 3, '*t',  0, 6, '*p',  3, 2, 'ov',  4, 5, 'e^',  5, 6, '+a',  0, 0, '+1')                  # offices
Add-Room 11 26 7 7 'WW' @(3, 3, '*t',  6, 6, '*p',  2, 5, 'h^',  5, 2, 'ov',  0, 6, '+f',  6, 0, '+2')
Add-Room 37 26 7 7 'WW' @(3, 3, '*t',  0, 6, '*p',  1, 2, 'ov',  5, 5, 'e^',  3, 5, 'k^',  6, 6, '+a',  0, 0, '+3')
Add-Room 45 26 6 7 'WW' @(2, 3, '*t',  5, 6, '*p',  3, 4, 's^',  1, 5, 'h^',  0, 6, '+h',  5, 0, '+1')
Add-Room 4 12 12 9 'WW' @(                                   # the CFO's office: silver key
    4, 3, '*t',  5, 3, '*t',  6, 3, '*t',  0, 0, '*p',  11, 0, '*p',  5, 2, '+s'
    3, 5, 'ov',  8, 5, 'ov',  1, 7, 'e>',  10, 7, 'e<',  6, 6, 'hv',  11, 8, '+a',  0, 8, '+2',  10, 0, '+3')
Add-Room 39 12 12 9 'TT' @(                                  # security
    1, 0, '*m',  3, 0, '*m',  8, 0, '*m',  10, 0, '*m',  2, 3, 'kv',  9, 3, 'kv',  5, 4, 'sv',  2, 7, 'e>',  9, 7, 'e<',  6, 2, 'ov'
    0, 8, '+a',  11, 8, '+h',  5, 0, '+o',  6, 0, '+o')
Add-Room 18 9 19 12 'WW' @(                                  # the boardroom: two commanders
    5, 5, '*t',  6, 5, '*t',  7, 5, '*t',  8, 5, '*t',  9, 5, '*t',  10, 5, '*t',  11, 5, '*t',  12, 5, '*t',  13, 5, '*t',  6, 3, '*h',  12, 3, '*h'
    5, 2, 'bv',  13, 2, 'bv',  9, 2, 'ov',  2, 8, 'ev',  16, 8, 'ev',  9, 8, 'hv',  7, 9, 'hv',  11, 9, 'hv'
    0, 0, '+h',  18, 0, '+h',  0, 11, '+a',  18, 11, '+a',  8, 0, '+z',  10, 0, '+o')
Add-Room 20 3 16 5 'WW' @(                                   # the CEO's office
    7, 1, '*t',  8, 1, '*t',  0, 0, '*p',  15, 0, '*p',  0, 4, '*f',  15, 4, '*f'
    8, 2, 'uv',  3, 2, 'ev',  12, 2, 'ev',  1, 0, '+h',  14, 0, '+h',  1, 4, '+a',  14, 4, '+o')
Add-Room 37 4 3 3 'MM' @(1, 1, '*l')                                                                                # the private lift
Add-Room 16 4 3 3 'WW' @(0, 0, '+4',  0, 2, '+4',  0, 1, '+q')                                                      # cache behind a cracked wall
Add-Room 6 8 4 3 'WW' @(0, 0, '+4',  3, 0, '+4',  0, 2, '+a',  3, 2, '+q')                                          # secret: CFO
Add-Room 31 36 3 3 'WW' @(0, 0, '+a',  2, 0, '+a',  0, 2, '+c',  2, 2, '+h')                                        # secret: reception
Add-Room 52 15 2 3 'TT' @(0, 0, '+z',  1, 0, '+z',  0, 2, '+u',  1, 2, '+h')                                        # secret: security
Add-Things @(
    27, 35, 'DD',  27, 25, 'DD',  6, 25, 'DD',   14, 25, 'DD',  40, 25, 'DD',  47, 25, 'DD',  9, 21, 'DD',  45, 21, 'DD'
    27, 21, 'DS',  27, 8, 'DG',   36, 5, 'DL',   40, 5, 'MX'
    7, 11, '?w',   32, 35, '?w',  51, 16, '?T',  19, 5, '!W'
    12, 21, 'Wp',  20, 21, 'Ws',  34, 21, 'Ws',  42, 21, 'Wp',  10, 25, 'Wp',  23, 25, 'Ws',  31, 25, 'Ws',  44, 25, 'Wp'
    48, 22, 'cw',  27, 6, 'ts',   45, 18, 'ts'           # a camera in the gallery, sentry guns behind the CEO's and security's doors
)
Add-Spawns 3 @(27, 30, 'ov',  30, 24, 'e<',  27, 15, 'hv')
Add-Spawns 4 @(24, 5, 'hv',  8, 28, 's>',  45, 16, 'kv')
Add-Dark 45 17                                                # security likes it dim
Save-Level 9 'The Executive Floor' 720 '2A2030' '584A5C' 'WW' -Look '@floortex flat_carpet', '@ceiltex ceil_plain', '@fog 100810 15'

# =====================================================================================================
# FLOOR 10 - Ring 0.  Two rings around the core. Patrols walk the outer ring; the gates to the inner
# ring hang on two levers (north-east room, the silver arsenal in the south-east). A commander in the
# inner ring has the gold key to the core - and in the dark of the core wait two printers, BLUE SCREEN and,
# in the middle of it all, the lift.
# =====================================================================================================
New-Grid 51 51
Add-Room 4 4 43 3 'TT'; Add-Room 4 4 3 43 'TT'; Add-Room 44 4 3 43 'TT'; Add-Room 4 44 43 3 'TT'            # the outer ring
Add-Room 12 12 27 3 'MM'; Add-Room 12 12 3 27 'MM'; Add-Room 36 12 3 27 'MM'; Add-Room 12 36 27 3 'MM'      # the inner ring
Add-Room 16 16 19 19 'TT'                                                                                       # the core
Add-Wall 23 22 5 6 'MM'; Add-Floor 24 24 3 3                                                                    # the lift shaft in the middle of it
Add-Room 23 48 5 2 'MM' @(2, 1, 'P^',  0, 0, '+a',  4, 0, '+h')                                                 # arrival
Add-Room 24 40 3 3 'MM' @(0, 0, '+a',  2, 0, '+h',  0, 2, '+a')                                                 # gates: south, north, west, east
Add-Room 24 8 3 3 'MM' @(0, 1, 'h>')
Add-Room 8 24 3 3 'MM' @(1, 0, 'ev')
Add-Room 40 24 3 3 'MM' @(1, 2, 'e^')
Add-Room 8 8 3 3 'MM' @(0, 0, '+s',  2, 0, '+a',  1, 2, 'o^')                                                   # north-west: silver key
Add-Room 40 8 3 3 'MM' @(0, 0, '+a',  2, 0, '+h',  0, 2, 'k^',  2, 2, 'k^')                                     # north-east: lever 1
Add-Room 8 40 3 3 'MM' @(0, 0, '+h',  2, 0, '+h',  1, 0, '+o',  0, 2, '+a',  2, 2, '+a')                        # south-west: supplies
Add-Room 40 40 3 3 'MM' @(0, 0, '+z',  2, 0, '+z',  0, 1, '+o',  2, 1, '+o',  0, 2, '+q',  2, 2, '+u')          # south-east: the arsenal, lever 2
Add-Room 8 14 3 5 'TT' @(0, 0, '+4',  2, 0, '+4',  0, 4, '+a',  2, 4, '+h')                                     # secret: west
Add-Room 40 30 3 5 'TT' @(2, 0, '+c',  2, 4, '+a',  0, 0, '+u',  0, 4, '+h')                                    # secret: east
Add-Room 14 8 5 3 'TT' @(0, 0, '+4',  4, 0, '+4',  0, 2, '+z',  4, 2, '+z')                                     # secret: north
Add-Room 32 40 5 3 'TT' @(0, 0, '+o',  4, 0, '+o',  2, 0, '+h')                                                 # cache behind a cracked wall
Add-Things @(
    25, 47, 'DD',  25, 43, 'DD',  25, 39, 'D1',  25, 7, 'DD',   25, 11, 'D1',  7, 25, 'DD',   11, 25, 'D2',  43, 25, 'DD',  39, 25, 'D2'
    9, 7, 'DD',    41, 7, 'DD',   41, 11, 'X1',  9, 43, 'DD',   41, 43, 'DS',  41, 39, 'X2',  25, 15, 'DG',  25, 27, 'DL',  25, 23, 'MX',  25, 25, '*l'
    7, 16, '?T',   39, 32, '?M',  16, 7, '?T',   34, 43, '!T'
    # the outer ring: four patrols walk it clockwise, snipers in the corners, mutants in the niches
    5, 5, ':>',    45, 5, ':v',   45, 45, ':<',  5, 45, ':^',   10, 5, 'eE',   45, 20, 'eS',  40, 45, 'eW',  5, 30, 'eN'
    4, 4, 's>',    46, 4, 'sv',   46, 46, 's<',  4, 46, 's^',   15, 6, 'mn',   35, 4, 'ms',   44, 15, 'me',  46, 35, 'mw',  15, 44, 'mn',  35, 46, 'mn',  4, 15, 'me',  6, 35, 'mw'
    20, 6, '+a',   30, 6, '+a',   6, 22, '+a',   44, 28, '+a',  20, 44, '+a',  31, 46, '+a'
    12, 4, '+a',   38, 6, '+a',   46, 12, '+f',  44, 38, '+a',  12, 46, '+h',  38, 44, '+a',  4, 38, '+a',   6, 12, '+f'
    # the inner ring: shield-bearers on patrol, kamikaze robots, the commander with the gold key
    13, 13, ':>',  37, 13, ':v',  37, 37, ':<',  13, 37, ':^',  18, 13, 'hE',  32, 37, 'hW'
    30, 12, 'b<',  14, 20, 'kv',  36, 30, 'k^',  20, 38, 'k>',  30, 36, 'k<',  38, 12, 'e<',  12, 38, 'e>',  38, 38, 'e^'
    12, 12, '+h',  36, 36, '+a',  14, 36, '+a',  14, 14, '+o',  36, 14, '+o'
    # the core
    19, 19, '*c',  31, 19, '*c',  19, 31, '*c',  31, 31, '*c',  19, 25, '*c',  31, 25, '*c'
    25, 19, 'x^',  19, 28, 'u^',  31, 28, 'u^',  17, 17, 'e>',  33, 17, 'e<',  17, 33, 'k^',  33, 33, 'k^',  22, 30, 'h^',  28, 30, 'h^'
    23, 17, 'tn',  27, 17, 'tn',  20, 4, 'ce',   30, 46, 'cw'          # two sentry guns cover the door of the core, cameras watch the outer ring
    16, 16, '+h',  34, 16, '+h',  16, 34, '+h',  34, 34, '+h',  17, 16, '+a',  33, 16, '+a',  17, 34, '+o',  33, 34, '+o',  16, 25, '+z',  34, 25, '+z',  25, 33, '+q'
)
Add-Spawns 3 @(30, 44, 'e<',  14, 25, 'h<',  24, 31, 'e^')
Add-Spawns 4 @(20, 20, 'h^',  30, 20, 'h^',  4, 20, 'sv')
Add-Dark 20 21                                                # the core
Save-Level 10 'Ring 0' 900 '101018' '30303C' 'TT' -Look '@floortex flat_tech', '@ceiltex ceil_tech', '@fog 04040C 11'

# =====================================================================================================
# SECRET FLOOR (from floor 2) - The Treasury.  Behind the push-wall in dorm B of the barracks hides a
# second lift switch. It leads here: a vault full of crowns and chests, both side vaults stocked with
# every weapon - and a guard detail that does not expect visitors.
# =====================================================================================================
New-Grid 32 25
Add-Room 10 8 13 11 'WW' @(                                  # the great vault
    1, 1, '+4',  11, 1, '+4',  1, 9, '+4',  11, 9, '+4',  3, 3, '+3',  9, 3, '+3',  3, 7, '+3',  9, 7, '+3',  6, 2, '+2',  6, 8, '+2'
    4, 5, '*c',  8, 5, '*c',  6, 5, '+u',  6, 4, '*h'
    3, 1, 'dv',  9, 1, 'dv',  5, 1, 'ev',  7, 1, 'ev',  0, 5, 'k>',  12, 5, 'k<')
Add-Room 15 20 3 3 'MM' @(1, 1, 'P^')                                                                               # arrival
Add-Room 3 10 6 7 'BB' @(0, 0, '+l',  5, 0, '+t',  0, 6, '+o',  5, 6, '+o',  2, 3, '+c',  3, 3, '+j',  1, 3, 'h>')   # west vault: conventional arms
Add-Room 24 10 6 7 'RR' @(0, 0, '+p',  5, 0, '+r',  0, 6, '+z',  5, 6, '+z',  3, 3, '+q',  2, 3, '+h',  4, 3, 's<')  # east vault: the exotic stuff
Add-Room 15 4 3 3 'MM' @(1, 1, '*l')                                                                                 # lift
Add-Things @(
    16, 19, 'DD',  9, 13, 'DD',  23, 13, 'DD',  16, 7, 'DL',  16, 3, 'MX'
    12, 7, 'Wp',   20, 7, 'Ws',  12, 19, 'Ws',  20, 19, 'Wp'
)
Add-Spawns 3 @(14, 14, 'ov',  18, 14, 'ov')
Add-Spawns 4 @(12, 16, 'k^',  20, 16, 'k^')
Save-Level 2 'The Treasury' 120 '3A2A10' '6A5A30' 'WW' 'bonus' -Look '@floortex flat_carpet', '@ceiltex ceil_plain', '@fog 1A1206 14'
