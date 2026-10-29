# POLF 3D - Copyright (c) 2026 oNdsen. Licensed under the MIT License, see LICENSE.
#
# Ghost.ps1 - the ghost race. A dungeon run is recorded anyway (that is what makes its time checkable), and since 1.4.0
# the recording also keeps where the player was, ten times a second. Today's dungeon then has a second runner: your
# best run, as a see-through figure in gold. -Ghost <file> races somebody else's run instead - a friend sends the file
# of their run, and the game builds the same dungeon and lets them run along.
#
# The ghost is only drawn. It is not an actor, it touches nothing and nothing touches it, so a run with a ghost is
# exactly as checkable as one without.

$script:GhostRun = $null
$script:GHOST_STEP = 7.0                         # tics between two points of the path: a tenth of a second

# Called after every simulated frame of a recording: notes where the player is, on the clock of the floor.
function Add-GhostPoint {
    $rec = $script:Recording
    if (-not $rec -or $null -eq $rec.Path) { return }                  # (an empty list is false - $null is the test)
    while ($rec.PathNext -le $script:Stats.Tics) {
        $rec.Path.Add(@([Math]::Round($script:P.X, 2), [Math]::Round($script:P.Y, 2), [int][Math]::Round($script:P.Angle)))
        $rec.PathNext += $script:GHOST_STEP
    }
}

# The figure: the co-op player's, every other pixel left out and the rest in gold - the -WhatIf ghosts' cousin.
function Initialize-GhostSprite {
    if ($script:Spr['ghost.s']) { return }
    if (-not $script:Spr['peer0.s']) { Add-SoldierSprites 'peer0' }
    foreach ($pose in 's', 'w1', 'w2', 'w3', 'w4') {
        $script:Spr["ghost.$pose"] = @(foreach ($view in $script:Spr["peer0.$pose"]) {
                $px = [int[]]::new(4096)
                for ($i = 0; $i -lt 4096; $i++) {
                    $c = $view[$i]
                    if ($c -eq 0 -or ((($i % 64) + [int][Math]::Floor($i / 64)) % 2) -ne 0) { continue }
                    $light = 0.45 + ((($c -shr 16) -band 255) + (($c -shr 8) -band 255) + ($c -band 255)) / 1100.0
                    $px[$i] = (0xFF -shl 24) -bor ([int][Math]::Min(255, 255 * $light) -shl 16) -bor ([int][Math]::Min(255, 200 * $light) -shl 8) -bor [int][Math]::Min(255, 64 * $light)
                }
                , $px
            })
    }
}

# A run to race, from a demo file of a dungeon: $null when the file has no path (recorded before 1.4.0) or is no dungeon.
function Read-GhostRun([string]$Path, [string]$Label) {
    try { $demo = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -AsHashtable } catch { return $null }
    if ($demo -isnot [System.Collections.IDictionary] -or -not $demo.Dungeon -or -not $demo.Path) { return $null }
    $points = @(foreach ($p in $demo.Path) { $p = @($p); if ($p.Count -ge 3 -and $p[0] -is [ValueType] -and $p[1] -is [ValueType] -and $p[2] -is [ValueType]) { , @([double]$p[0], [double]$p[1], [double]$p[2]) } })
    if ($points.Count -lt 2) { return $null }
    $step = if ($demo.PathStep -is [ValueType] -and [double]$demo.PathStep -gt 0) { [double]$demo.PathStep } else { $script:GHOST_STEP }
    $seconds = if ($demo.Seconds -is [ValueType]) { [double]$demo.Seconds } else { ($points.Count - 1) * $step / $script:TICRATE }
    $who = if ($Label) { $Label } elseif ($demo.Player) { [string]$demo.Player } else { 'the ghost' }
    @{ Path = $points; Step = $step; Seconds = $seconds; Label = $who; Dungeon = [int]$demo.Dungeon; Difficulty = [int]$demo.Difficulty }
}

# Who runs along in this dungeon: the run from -Ghost if it is of this dungeon, otherwise your own best.
function Start-GhostRun([int]$Seed) {
    $script:GhostRun = $null
    $run = $null
    if ($script:GhostFile) {
        $run = Read-GhostRun $script:GhostFile ''
        if (-not $run -or $run.Dungeon -ne $Seed -or $run.Difficulty -ne $script:Difficulty) { $run = $null }
    }
    if (-not $run) {
        $best = Get-DungeonBest $Seed
        if ($best -and $best.Demo) {
            $run = Read-GhostRun (Join-Path $script:SaveDir ([System.IO.Path]::GetFileName([string]$best.Demo))) 'your best'
            if (-not $run) { $script:GhostNote = 'Your best run here has no ghost yet - it was recorded before ghosts. This run records one.' }
        }
    }
    if (-not $run) { return }
    Initialize-GhostSprite
    $run.Arrived = $false
    $script:GhostRun = $run
}

function Stop-GhostRun { $script:GhostRun = $null; $script:GhostNote = $null }

# Where the ghost is now: between two points of its path, by the clock of the floor.
function Get-GhostPose {
    $g = $script:GhostRun; $path = $g.Path; $n = $path.Count
    $t = [double]$script:Stats.Tics / $g.Step
    $i = [int][Math]::Floor($t)
    if ($i -ge $n - 1) { $p = $path[$n - 1]; return @{ X = $p[0]; Y = $p[1]; Angle = $p[2]; Moving = $false; Pose = 's'; Done = $true } }
    $a = $path[$i]; $b = $path[$i + 1]; $f = $t - $i
    $moved = [Math]::Abs($b[0] - $a[0]) + [Math]::Abs($b[1] - $a[1])
    if ($moved -gt 2.0) { $f = 0.0 }                                    # a teleporter: no flight across the map
    $turn = (($b[2] - $a[2] + 540.0) % 360.0) - 180.0
    $walking = $moved -gt 0.02
    @{
        X = $a[0] + ($b[0] - $a[0]) * $f; Y = $a[1] + ($b[1] - $a[1]) * $f; Angle = $a[2] + $turn * $f
        Moving = $walking; Pose = $(if ($walking) { "w$(([int][Math]::Floor($t * 0.7) % 4) + 1)" } else { 's' }); Done = $false
    }
}

# The sprite pass of the renderer asks for it: @(sprite, screen x, size, depth) or $null when it is not in sight.
function Get-GhostSprite([double]$PX, [double]$PY, [double]$DirX, [double]$DirY, [double]$Plane, [double]$HalfW, [double]$ProjH, [int]$Frame) {
    if (-not $script:GhostRun) { return $null }
    $pose = Get-GhostPose
    $mw = $script:MapW
    $tile = [int][Math]::Floor($pose.Y) * $mw + [int][Math]::Floor($pose.X)
    if ($tile -lt 0 -or $tile -ge $script:Vis.Length -or $script:Vis[$tile] -ne $Frame) { return $null }
    $rx = $pose.X - $PX; $ry = $pose.Y - $PY
    $depth = $rx * $DirX + $ry * $DirY
    if ($depth -lt 0.2) { return $null }
    $lat = $ry * $DirX - $rx * $DirY
    $toViewer = [Math]::Atan2($ry, - $rx) * 180.0 / [Math]::PI
    $view = [int][Math]::Floor((($toViewer - $pose.Angle + 765.0) % 360.0) / 90.0) % 4
    , @($script:Spr["ghost.$($pose.Pose)"][$view], [int]($HalfW * (1.0 + $lat / ($depth * $Plane))), [int]($ProjH / $depth), $depth)
}

# The line on the screen: who is racing, and whether they have reached the lift.
function Show-GhostLabel {
    $g = $script:GhostRun
    if (-not $g) { return }
    $done = [double]$script:Stats.Tics / $g.Step -ge $g.Path.Count - 1
    $text = if ($done) { "GHOST  $($g.Label) reached the lift at $(Format-Time $g.Seconds -Tenths)" } else { "GHOST  $($g.Label)  $(Format-Time $g.Seconds -Tenths)" }
    Write-HudBar '70101A2C' 2 ($script:ViewH - 37) ($text.Length * 2.5 + 5) 7      # bottom left, clear of the weapon
    Write-HudLine $text 'Small' 'FFC840' 4 ($script:ViewH - 36.6)
}

# On the floor-completed screen: how the race went.
function Get-GhostVerdict([double]$Seconds) {
    $g = $script:GhostRun
    if (-not $g) { return $null }
    $d = $Seconds - $g.Seconds
    if ([Math]::Abs($d) -lt 0.05) { return "a dead heat with $($g.Label)" }
    if ($d -lt 0) { "$('{0:0.0}' -f -$d) s ahead of $($g.Label)" } else { "$('{0:0.0}' -f $d) s behind $($g.Label)" }
}
