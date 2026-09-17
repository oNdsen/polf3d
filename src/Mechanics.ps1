# POLF 3D - Copyright (c) 2026 oNdsen. Licensed under the MIT License, see LICENSE.

# Mechanics.ps1 - level machinery that runs on a timer or reacts to where the player stands.

# ---------------------------------------------------------------------------------------------
# Traps ("~s" spikes, "~c" crusher). Both cycle forever; neighbours are out of phase so that a
# row of them becomes a timing puzzle instead of a wall.
#   spikes : down 90 tics, up 60 - hurt the player when they shoot up and while he stands in them
#   crusher: raised 130 tics, coming down 30 (the warning), down 70 - blocks the tile and hurts
#            whoever is under it, enemies included
# ---------------------------------------------------------------------------------------------
$script:TrapCodes = @{ [char]'s' = 'spikes'; [char]'c' = 'crusher' }

function Add-Trap([string]$Kind, [int]$X, [int]$Y) {
    $s = [Static]::new()
    $s.X = $X; $s.Y = $Y; $s.Sprite = $script:Spr["$Kind.0"]
    $script:Statics.Add($s)
    $script:Traps.Add(@{ Kind = $Kind; X = $X; Y = $Y; Phase = (($X * 7 + $Y * 13) % 11) * 20.0; State = 0; Hurt = 0.0; Static = $s })
}

function Update-Traps([double]$Tics) {
    if ($script:Traps.Count -eq 0) { return }
    $p = $script:P; $w = $script:MapW
    $ptx = [int][Math]::Floor($p.X); $pty = [int][Math]::Floor($p.Y)
    foreach ($t in $script:Traps) {
        $t.Phase += $Tics
        if ($t.Kind -eq 'spikes') { $state = if (($t.Phase % 150) -ge 90) { 1 } else { 0 } }
        else { $m = $t.Phase % 230; $state = if ($m -lt 130) { 0 } elseif ($m -lt 160) { 1 } else { 2 } }
        $inside = $ptx -eq $t.X -and $pty -eq $t.Y
        $near = [Math]::Abs($p.X - $t.X) -lt 8 -and [Math]::Abs($p.Y - $t.Y) -lt 8

        if ($state -ne $t.State) {
            $t.State = $state
            $t.Static.Sprite = $script:Spr["$($t.Kind).$state"]
            if ($t.Kind -eq 'crusher') {
                $script:StaticBlock[$t.Y * $w + $t.X] = $state -eq 2
                if ($state -eq 2) {
                    if ($near) { Start-Sfx 'crusher' }
                    if ($inside) { Invoke-PlayerDamage (40 + ((Get-Rnd) -shr 4)) $null }
                    $victim = $script:ActorAt[$t.Y * $w + $t.X]
                    if ($victim -and $victim.Shootable) { Invoke-ActorDamage $victim 60 'explosion' }
                }
            }
            elseif ($state -eq 1) {
                if ($near) { Start-Sfx 'spikes' }
                if ($inside) { Invoke-PlayerDamage (10 + ((Get-Rnd) -shr 4)) $null; $t.Hurt = 0.0 }
            }
        }
        elseif ($t.Kind -eq 'spikes' -and $state -eq 1 -and $inside) {
            $t.Hurt += $Tics                                        # standing in raised spikes keeps hurting
            if ($t.Hurt -ge 30) { $t.Hurt = 0.0; Invoke-PlayerDamage (6 + ((Get-Rnd) -shr 5)) $null }
        }
    }
}
