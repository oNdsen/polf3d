# POLF 3D - Copyright (c) 2026 oNdsen. Licensed under the MIT License, see LICENSE.

# Render.ps1 - the ray caster, sprite projection, status bar and frame presentation.
#
# One ray per screen column is walked through the tile grid (DDA). The distance used for the
# wall height is measured along the view direction, not along the ray - that is what keeps
# walls straight instead of fish-eyed. Per column the distance is also stored in a z-buffer
# so sprites can be clipped against walls. Only the final pixel loops live in C# (Scaler.cs).

function Initialize-Renderer([int]$Scale, [int]$ColumnStep) {
    $script:ViewW = 320; $script:ViewH = 200; $script:HudH = 40
    $script:Scale = $Scale
    $script:ColumnStep = $ColumnStep
    $script:PlaneLen = 0.66                                   # tan(fov/2): about 67 degrees
    $script:ProjH = ($script:ViewW / 2) / $script:PlaneLen    # wall height in pixels at distance 1
    $script:FB = [int[]]::new($script:ViewW * $script:ViewH)
    $script:BG = [int[]]::new($script:ViewW * $script:ViewH)
    $script:ZBuf = [double[]]::new($script:ViewW)
    $script:FrameNo = 0

    $script:WinW = $script:ViewW * $Scale
    $script:WinH = ($script:ViewH + $script:HudH) * $Scale
    $script:ViewBmp = [System.Drawing.Bitmap]::new($script:ViewW, $script:ViewH, [System.Drawing.Imaging.PixelFormat]::Format32bppRgb)
    $script:ViewRect = [System.Drawing.Rectangle]::new(0, 0, $script:ViewW, $script:ViewH)
    $script:ViewDest = [System.Drawing.Rectangle]::new(0, 0, $script:WinW, $script:ViewH * $Scale)
    $script:BackBmp = [System.Drawing.Bitmap]::new($script:WinW, $script:WinH, [System.Drawing.Imaging.PixelFormat]::Format32bppPArgb)
    $script:BackG = [System.Drawing.Graphics]::FromImage($script:BackBmp)      # headless default; the window swaps in its own buffer
    Set-BackGraphicsMode

    $script:Fonts = @{
        Small = [System.Drawing.Font]::new('Consolas', [single](3.2 * $Scale), [System.Drawing.FontStyle]::Bold)
        Term  = [System.Drawing.Font]::new('Consolas', [single](3.3 * $Scale), [System.Drawing.FontStyle]::Regular)
        Mid   = [System.Drawing.Font]::new('Consolas', [single](5.0 * $Scale), [System.Drawing.FontStyle]::Bold)
        Big   = [System.Drawing.Font]::new('Consolas', [single](8.5 * $Scale), [System.Drawing.FontStyle]::Bold)
        Huge  = [System.Drawing.Font]::new('Consolas', [single](22 * $Scale), [System.Drawing.FontStyle]::Bold)
    }
    $script:RadarPen = [System.Drawing.Pen]::new([System.Drawing.Color]::FromArgb(255, 255, 112, 96), [single][Math]::Max(1.5, $Scale * 0.6))
    $script:Centered = [System.Drawing.StringFormat]::new()
    $script:Centered.Alignment = [System.Drawing.StringAlignment]::Center
    $script:Centered.LineAlignment = [System.Drawing.StringAlignment]::Center
}

function Set-BackGraphicsMode {
    $script:BackG.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::NearestNeighbor
    $script:BackG.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::Half
    $script:BackG.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAlias
}

function Set-Background {
    $half = $script:ViewW * ($script:ViewH / 2)
    [Array]::Fill($script:BG, [int]$script:CeilingColor, 0, $half)
    [Array]::Fill($script:BG, [int]$script:FloorColor, $half, $half)
}

# =============================================================================================
# 3D view
# =============================================================================================
function Update-View {
    $p = $script:P
    $W = [int]$script:ViewW; $H = [int]$script:ViewH
    $fb = $script:FB; $zbuf = $script:ZBuf; $tiles = $script:Tiles; $vis = $script:Vis
    $mw = [int]$script:MapW
    $light = $script:WallLight; $dark = $script:WallDark; $doors = $script:Doors
    $jamb = [int]$script:TEX_JAMB
    $step = [int]$script:ColumnStep
    $projH = [double]$script:ProjH; $pl = [double]$script:PlaneLen
    $frame = [int](++$script:FrameNo)
    $scaler = $script:Scaler                                   # the compiled pixel loops (see Initialize-Scaler)

    # distance haze: fog units (0..256) per tile, capped so far walls never vanish completely
    $fogK = [double]$script:FogPerTile; $maxFog = 205

    # windows: the ray goes on, the window strip is remembered and drawn over the scene later
    $isWin = $script:IsWindow
    if ($null -eq $script:WinD -or $script:WinD.Length -ne $W) { $script:WinD = [double[]]::new($W); $script:WinX = [int[]]::new($W); $script:WinT = [object[]]::new($W) }
    $winD = $script:WinD; $winX = $script:WinX; $winT = $script:WinT
    [Array]::Clear($winD, 0, $W)
    $minWin = 1e9

    $rad = $p.Angle * [Math]::PI / 180.0
    $dirX = [Math]::Cos($rad); $dirY = - [Math]::Sin($rad)
    $plX = - $dirY * $pl; $plY = $dirX * $pl                   # camera plane = view direction turned right
    $px = [double]$p.X; $py = [double]$p.Y
    $ptx = [int][Math]::Floor($px); $pty = [int][Math]::Floor($py)
    $vis[$pty * $mw + $ptx] = $frame

    # the push-wall (if one is moving) is an axis aligned box that has slid Pos tiles along DX/DY
    $pw = $script:PW
    $bx0 = $pw.X + $pw.DX * $pw.Pos; $by0 = $pw.Y + $pw.DY * $pw.Pos
    $bx1 = $bx0 + 1.0; $by1 = $by0 + 1.0
    $pwTex = [int]$pw.TexId

    # floor and ceiling: textured (one C# call) or, with -FlatFloors / maps without textures, two plain colours
    if ($script:FloorTex -and $script:CeilTex -and -not $script:FlatFloors) {
        $scaler::Floor($fb, $W, $H, $px, $py, $dirX, $dirY, $plX, $plY, $projH, $script:FloorTex, $script:CeilTex, $fogK, $maxFog)
    }
    else { [Array]::Copy($script:BG, $fb, $fb.Length) }

    $camStep = 2.0 / $W
    for ($col = 0; $col -lt $W; $col += $step) {
        $cam = ($col + 0.5 * $step) * $camStep - 1.0
        $rdx = $dirX + $plX * $cam; if ($rdx -eq 0) { $rdx = 1e-9 }
        $rdy = $dirY + $plY * $cam; if ($rdy -eq 0) { $rdy = 1e-9 }
        $ddx = [Math]::Abs(1.0 / $rdx); $ddy = [Math]::Abs(1.0 / $rdy)
        $mx = $ptx; $my = $pty
        if ($rdx -lt 0) { $sx = -1; $sdx = ($px - $mx) * $ddx } else { $sx = 1; $sdx = ($mx + 1.0 - $px) * $ddx }
        if ($rdy -lt 0) { $sy = -1; $sdy = ($py - $my) * $ddy } else { $sy = 1; $sdy = ($my + 1.0 - $py) * $ddy }

        while ($true) {
            if ($sdx -lt $sdy) { $sdx += $ddx; $mx += $sx; $side = 0 } else { $sdy += $ddy; $my += $sy; $side = 1 }
            $idx = $my * $mw + $mx
            $vis[$idx] = $frame
            $t = $tiles[$idx]
            if ($t -eq 0) { continue }

            if ($t -lt 100) {
                # ---- solid wall ----
                if ($side -eq 0) {
                    $perp = $sdx - $ddx; $hit = $py + $perp * $rdy; $before = $tiles[$idx - $sx]
                    $texX = [int][Math]::Floor(($hit - [Math]::Floor($hit)) * 64.0)
                    if ($rdx -lt 0) { $texX = 63 - $texX }               # keep textures readable, not mirrored
                    if ($before -ge 100 -and $before -lt 200) { $t = $jamb }      # seen from inside a doorway
                    $tex = $light[$t]
                }
                else {
                    $perp = $sdy - $ddy; $hit = $px + $perp * $rdx; $before = $tiles[$idx - $sy * $mw]
                    $texX = [int][Math]::Floor(($hit - [Math]::Floor($hit)) * 64.0)
                    if ($rdy -gt 0) { $texX = 63 - $texX }
                    if ($before -ge 100 -and $before -lt 200) { $t = $jamb }
                    $tex = $dark[$t]
                }
                if ($isWin[$idx]) {
                    if ($winD[$col] -eq 0) { $winD[$col] = $perp; $winX[$col] = $texX; $winT[$col] = $tex; if ($perp -lt $minWin) { $minWin = $perp } }
                    continue
                }
                break
            }

            if ($t -lt 200) {
                # ---- door: a thin leaf in the middle of its tile, sliding sideways by Open ----
                $d = $doors[$t - 100]
                if ($d.Vertical) {
                    if ($side -ne 0) { continue }
                    $perp = $sdx - 0.5 * $ddx
                    $hit = $py + $perp * $rdy - $my
                    if ($hit -lt 0 -or $hit -ge 1 -or $hit -lt $d.Open) { continue }
                    $tex = $light[$d.TexId]
                }
                else {
                    if ($side -ne 1) { continue }
                    $perp = $sdy - 0.5 * $ddy
                    $hit = $px + $perp * $rdx - $mx
                    if ($hit -lt 0 -or $hit -ge 1 -or $hit -lt $d.Open) { continue }
                    $tex = $dark[$d.TexId]
                }
                $texX = [int][Math]::Floor(($hit - $d.Open) * 64.0)
                break
            }

            # ---- moving push-wall: ray against box (slab test) ----
            $t1 = ($bx0 - $px) / $rdx; $t2 = ($bx1 - $px) / $rdx; if ($t1 -gt $t2) { $t1, $t2 = $t2, $t1 }
            $t3 = ($by0 - $py) / $rdy; $t4 = ($by1 - $py) / $rdy; if ($t3 -gt $t4) { $t3, $t4 = $t4, $t3 }
            $tIn = [Math]::Max($t1, $t3); $tOut = [Math]::Min($t2, $t4)
            if ($tIn -gt $tOut -or $tOut -le 0) { continue }
            $perp = $tIn
            if ($t1 -gt $t3) { $hit = $py + $perp * $rdy - $by0; $tex = $light[$pwTex] } else { $hit = $px + $perp * $rdx - $bx0; $tex = $dark[$pwTex] }
            $texX = [int][Math]::Floor(($hit - [Math]::Floor($hit)) * 64.0)
            break
        }

        if ($perp -lt 0.02) { $perp = 0.02 }
        $fog = [int]($perp * $fogK); if ($fog -gt $maxFog) { $fog = $maxFog }
        $scaler::Wall($fb, $W, $H, $col, $step, [int]($projH / $perp), $tex, $texX, $fog, $false)
        $zbuf[$col] = $perp
        if ($step -gt 1) { for ($k = 1; $k -lt $step -and ($col + $k) -lt $W; $k++) { $zbuf[$col + $k] = $perp } }
    }

    # ---- sprites: everything standing on a tile that a ray has crossed this frame ----------------
    $keys = [System.Collections.Generic.List[double]]::new()
    $draw = [System.Collections.Generic.List[object]]::new()
    $halfW = $W / 2.0

    foreach ($s in $script:Statics) {
        if ($s.Removed -or $vis[$s.Y * $mw + $s.X] -ne $frame) { continue }
        $rx = $s.X + 0.5 - $px; $ry = $s.Y + 0.5 - $py
        $depth = $rx * $dirX + $ry * $dirY
        if ($depth -lt 0.2) { continue }
        $lat = $ry * $dirX - $rx * $dirY
        $keys.Add(- $depth)
        $draw.Add(@($s.Sprite, [int]($halfW * (1.0 + $lat / ($depth * $pl))), [int]($projH / $depth), $depth))
    }

    foreach ($a in $script:Actors) {
        $ax = $a.X; $ay = $a.Y
        $ai = [int][Math]::Floor($ay) * $mw + [int][Math]::Floor($ax)
        $seen = ($vis[$ai] -eq $frame) -or ($vis[$a.TY * $mw + $a.TX] -eq $frame) -or
                ($vis[$ai - 1] -eq $frame -and $tiles[$ai - 1] -eq 0) -or ($vis[$ai + 1] -eq $frame -and $tiles[$ai + 1] -eq 0) -or
                ($vis[$ai - $mw] -eq $frame -and $tiles[$ai - $mw] -eq 0) -or ($vis[$ai + $mw] -eq $frame -and $tiles[$ai + $mw] -eq 0)
        if (-not $seen) { $a.Visible = $false; continue }
        $rx = $ax - $px; $ry = $ay - $py
        $depth = $rx * $dirX + $ry * $dirY
        if ($depth -lt 0.2) { $a.Visible = $false; continue }
        $a.Visible = $true; $a.Active = $true
        $lat = $ry * $dirX - $rx * $dirY
        $a.Depth = $depth
        $a.ScreenX = [int]($halfW * (1.0 + $lat / ($depth * $pl)))

        $st = $script:States[$a.State]
        $spr = $script:Spr[$st.Sprite]
        if ($st.Rot) {
            # pick one of four views from where the player stands relative to the enemy's heading
            $view = 0
            if ($a.Dir -ne 8) {
                $toPlayer = [Math]::Atan2($ry, - $rx) * 180.0 / [Math]::PI
                $rel = ($toPlayer - $a.Dir * 45.0 + 765.0) % 360.0
                $view = [int][Math]::Floor($rel / 90.0)
            }
            $spr = $spr[$view]
        }
        $keys.Add(- $depth)
        $draw.Add(@($spr, $a.ScreenX, [int]($projH / $depth), $depth))
    }

    # far sprites, then the window strips, then the sprites in front of the nearest window
    $windowsPending = $minWin -lt 1e9
    if ($draw.Count) {
        # far to near. Sorted through an index array: Array.Sort(keys, items) called from PowerShell sorts the keys
        # but leaves an object[] of items in its old order - which drew every enemy on top of every column.
        $k = $keys.ToArray(); $order = [int[]](0..($k.Length - 1))
        [Array]::Sort($k, $order)
        foreach ($o in $order) {
            $it = $draw[$o]
            if ($windowsPending -and $it[3] -lt $minWin) {
                for ($c = 0; $c -lt $W; $c += $step) { if ($winD[$c] -gt 0) { $scaler::Wall($fb, $W, $H, $c, $step, [int]($projH / [Math]::Max(0.02, $winD[$c])), $winT[$c], $winX[$c], [int][Math]::Min($maxFog, $winD[$c] * $fogK), $true) } }
                $windowsPending = $false
            }
            $fog = [int]($it[3] * $fogK); if ($fog -gt $maxFog) { $fog = $maxFog }
            $scaler::Sprite($fb, $W, $H, $zbuf, $it[0], $it[1], $it[2], $it[3], $fog)
        }
    }
    if ($windowsPending) {
        for ($c = 0; $c -lt $W; $c += $step) { if ($winD[$c] -gt 0) { $scaler::Wall($fb, $W, $H, $c, $step, [int]($projH / [Math]::Max(0.02, $winD[$c])), $winT[$c], $winX[$c], [int][Math]::Min($maxFog, $winD[$c] * $fogK), $true) } }
    }

    # ---- the weapon in the player's hands ------------------------------------------------------
    if ($script:ShowWeapon) {
        $wtex = $script:Spr["weapon.$($script:Weapons[$p.Weapon].Key)"][$p.WeaponFrame]
        $scaler::Sprite($fb, $W, $H, $zbuf, $wtex, [int]$halfW, $H, 0.0, 0)
    }
}

# =============================================================================================
# Presentation
# =============================================================================================
function Copy-ViewToBack {
    $bd = $script:ViewBmp.LockBits($script:ViewRect, [System.Drawing.Imaging.ImageLockMode]::WriteOnly, [System.Drawing.Imaging.PixelFormat]::Format32bppRgb)
    [System.Runtime.InteropServices.Marshal]::Copy($script:FB, 0, $bd.Scan0, $script:FB.Length)
    $script:ViewBmp.UnlockBits($bd)
    if ($script:Shake -gt 0) {
        # camera shake: draw the view slightly enlarged and offset, clipped to its own area
        $amp = [int](1 + $script:Shake / 2)
        $r = $script:ViewDest
        # cosmetic randomness has its own generator: the game's must stay in step with recorded demos
        $shaken = [System.Drawing.Rectangle]::new($r.X - 8 + $script:FxRng.Next(-$amp, $amp + 1), $r.Y - 8 + $script:FxRng.Next(-$amp, $amp + 1), $r.Width + 16, $r.Height + 16)
        $script:BackG.SetClip($r)
        $script:BackG.DrawImage($script:ViewBmp, $shaken)
        $script:BackG.ResetClip()
    }
    else { $script:BackG.DrawImage($script:ViewBmp, $script:ViewDest) }
}

function Show-Back {
    if ($script:Buffered -and -not $script:Form.IsDisposed) { $script:Buffered.Render($script:FormG) }
}

function Write-HudText([string]$Text, [string]$Font, [string]$Color, [double]$X, [double]$Y, [double]$W, [double]$H) {
    # coordinates in 320x240 units
    $s = $script:Scale
    $rect = [System.Drawing.RectangleF]::new([single]($X * $s), [single]($Y * $s), [single]($W * $s), [single]($H * $s))
    $script:BackG.DrawString($Text, $script:Fonts[$Font], (Get-Brush $Color), $rect, $script:Centered)
}

function Write-HudBar([string]$Color, [double]$X, [double]$Y, [double]$W, [double]$H) {
    $s = $script:Scale
    $script:BackG.FillRectangle((Get-Brush $Color), [single]($X * $s), [single]($Y * $s), [single]($W * $s), [single]($H * $s))
}

function Show-Overlays {
    $viewH = $script:ViewH
    $g = $script:BackG; $sc = $script:Scale
    if ($script:BeamFlash -gt 0) {
        # the pipeline beam: converges from the muzzle to the vanishing point
        $cx = 160 * $sc; $cy = ($viewH / 2) * $sc; $by = ($viewH - 44) * $sc
        $a = [int][Math]::Min(230, $script:BeamFlash * 26)
        foreach ($beam in @(11, '40E0FF'), @(4, 'FFFFFF')) {
            $pts = [System.Drawing.PointF[]]@(
                [System.Drawing.PointF]::new($cx - $beam[0] * $sc, $by), [System.Drawing.PointF]::new($cx + $beam[0] * $sc, $by),
                [System.Drawing.PointF]::new($cx + 1, $cy), [System.Drawing.PointF]::new($cx - 1, $cy))
            $g.FillPolygon((Get-Brush ('{0:X2}{1}' -f $a, $beam[1])), $pts)
        }
    }
    if ($script:MuzzleFlash -gt 0) { Write-HudBar ('{0:X2}FFE8A0' -f [int]($script:MuzzleFlash * 9)) 0 0 320 $viewH }
    if ($script:ForceFlash -gt 0) {
        $a = [int][Math]::Min(235, $script:ForceFlash * 12)
        Write-HudBar ('{0:X2}B0FFC0' -f $a) 0 0 320 $viewH
    }
    if ($script:P.SudoTics -gt 0) {
        $blink = ($script:P.SudoTics -gt 210) -or ([int]($script:P.SudoTics / 12) % 2 -eq 0)     # flickers when running out
        if ($blink) {
            foreach ($b in @(0, 0, 320, 2), @(0, ($viewH - 2), 320, 2), @(0, 0, 2, $viewH), @(318, 0, 2, $viewH)) { Write-HudBar 'C0F0D040' $b[0] $b[1] $b[2] $b[3] }
            Write-HudText ("SUDO {0}s" -f [Math]::Ceiling($script:P.SudoTics / 70)) 'Mid' 'F0D040' 190 4 66 10
        }
    }
    if ($script:DamageFlash -gt 0) {
        $alpha = [int][Math]::Min(150, 30 + $script:DamageFlash * 5)
        Write-HudBar ('{0:X2}D00000' -f $alpha) 0 0 320 $viewH
    }
    elseif ($script:BonusFlash -gt 0) {
        $alpha = [int][Math]::Min(70, $script:BonusFlash * 4)
        Write-HudBar ('{0:X2}FFF8C0' -f $alpha) 0 0 320 $viewH
    }
    $cheats = @(if ($script:GodMode) { 'GOD' }; if ($script:InfiniteAmmo) { 'AMMO' }; if ($script:OneHitKill) { '1-HIT' })
    if ($cheats) { Write-HudText ("CHEAT: " + ($cheats -join ' + ')) 'Small' 'FF60FF' 2 ($viewH - 10) 120 8 }
    # what the enemies make of you: "?" = has noticed something and is reacting, "!" = is coming for you
    $zbuf = $script:ZBuf
    foreach ($a in $script:Actors) {
        if (-not $a.Visible -or -not $a.Shootable -or ($a.React -le 0 -and $a.AlertTics -le 0 -and $a.Stun -le 0)) { continue }
        $sx = $a.ScreenX
        if ($sx -lt 0 -or $sx -ge $script:ViewW -or $zbuf[$sx] -lt $a.Depth) { continue }
        $top = 100 - ($script:ProjH / $a.Depth) / 2 - 11
        if ($top -lt 1) { $top = 1 }
        $mark = if ($a.Stun -gt 0) { 'II' } elseif ($a.AlertTics -gt 0) { '!' } else { '?' }
        Write-HudText $mark 'Mid' '000000' ($sx - 9.5) ($top + 0.5) 20 10
        Write-HudText $mark 'Mid' $(if ($mark -eq '!') { 'FF4030' } elseif ($mark -eq 'II') { '40E0FF' } else { 'FFE040' }) ($sx - 10) $top 20 10
    }
    # the noise you are making right now: none / footsteps / running or doors / gunfire
    $level = if ($script:MadeNoise) { 3 } elseif ($script:StepNoise -ge $script:NOISE_DOOR) { 2 } elseif ($script:StepNoise -gt 0) { 1 } else { 0 }
    if ($level -gt $script:NoiseShown) { $script:NoiseShown = $level; $script:NoiseShownUntil = $script:Clock.Elapsed.TotalSeconds + 0.35 }
    elseif ($script:Clock.Elapsed.TotalSeconds -gt $script:NoiseShownUntil) { $script:NoiseShown = $level }
    for ($i = 1; $i -le 3; $i++) {
        $lit = $i -le $script:NoiseShown
        Write-HudBar $(if (-not $lit) { '60101A2C' } elseif ($i -eq 3) { 'FF4030' } elseif ($i -eq 2) { 'FFC040' } else { '60FF80' }) (152 + $i * 4) ($viewH - 8 - $i * 2) 3 (2 + $i * 2)
    }
    if ($script:P.Sneaking) { Write-HudText 'SNEAKING' 'Small' '60FF80' 172 ($viewH - 19) 40 8 }
    # a boss on your heels: his name and what is left of him
    $boss = $null
    foreach ($a in $script:Actors) { if ($a.Shootable -and $a.AttackMode -and $script:BossNames.ContainsKey($a.Kind) -and (-not $boss -or $a.Depth -lt $boss.Depth)) { $boss = $a } }
    if ($boss) {
        $full = [double]$boss.Def.HP[$script:Difficulty]
        Write-HudBar 'C0101A2C' 70 37 180 17
        Write-HudText $script:BossNames[$boss.Kind] 'Small' 'FFB0A0' 0 38 320 8
        Write-HudBar 'A0101A2C' 79 47 162 5
        Write-HudBar $(if ($boss.HP / $full -le 0.3) { 'FF4030' } else { 'D03838' }) 80 48 (160 * [Math]::Max(0.0, [Math]::Min(1.0, $boss.HP / $full))) 3
    }
    Show-AbilityOverlays

    # progress on this floor, and the clock when speedrunning
    $st = $script:Stats
    Write-HudText ("KILLS {0}/{1}   SECRETS {2}/{3}   TREASURE {4}/{5}" -f $st.Kills, $st.KillTotal, $st.Secrets, $st.SecretTotal, $st.Treasures, $st.TreasureTotal) 'Small' 'A0B4D0' 2 ($viewH - 19) 150 8
    if ($script:Speedrun) {
        $now = $st.Tics / $script:TICRATE
        Write-HudText ("{0}   par {1}   run {2}" -f (Format-Time $now -Tenths), (Format-Time $script:ParSeconds), (Format-Time (($script:P.RunTics + $st.Tics) / $script:TICRATE))) 'Mid' $(if ($now -le $script:ParSeconds) { '40FF60' } else { 'FF8040' }) 60 14 200 10
    }
    if ($script:NetLive) {
        $net = $script:Net
        Write-HudText (Get-NetHudText) 'Small' '60C0FF' 2 12 150 8
    }
    if ($script:ShowFps) { Write-HudText ("{0:0} fps" -f $script:Fps) 'Small' '80FF80' 2 2 40 8 }
    if ($script:Message -and $script:Clock.Elapsed.TotalSeconds -lt $script:MessageUntil) {
        Write-HudText $script:Message 'Mid' '000000' 0.6 6.6 320 10
        Write-HudText $script:Message 'Mid' 'FFE860' 0 6 320 10
    }
}

# Which face fits the moment: "tier|expression|look" (see New-FaceBitmap).
function Get-FaceKey {
    $p = $script:P
    if ($p.Health -le 0) { return '5|idle|0' }
    $tier = [Math]::Min(4, [int][Math]::Floor((100 - $p.Health) / 20))
    $expr = if ($p.PainTics -gt 0) { 'pain' } elseif ($p.SudoTics -gt 0) { 'sudo' } elseif ($script:GodMode) { 'god' } elseif ($p.GrinTics -gt 0) { 'grin' }
            elseif ($p.RageTics -gt 60) { 'rage' } elseif ($p.Sneaking) { 'sneak' } else { 'idle' }
    "$tier|$expr|$(if ($expr -in 'idle', 'rage', 'sneak', 'god') { [int]$p.FaceLook } else { 0 })"
}

function Show-Face([double]$X, [double]$Y) {
    $s = $script:Scale
    $key = Get-FaceKey
    $script:P.FaceKey = $key
    $f = $key.Split('|')
    Write-HudPanel $(if ($f[1] -eq 'sudo') { 'F0D040' } else { '80101A2C' }) ($X - 1) ($Y - 0.5) 32 35
    Write-HudBar 'FF101A2C' $X $Y 30 34
    $script:BackG.DrawImage((Get-FaceBitmap ([int]$f[0]) $f[1] ([int]$f[2])), [System.Drawing.RectangleF]::new([single]($X * $s), [single]($Y * $s), [single](30 * $s), [single](34 * $s)))
}

# Helpers for the status bar: rounded panels and gradient-filled gauges.
function Get-RoundedPath([double]$X, [double]$Y, [double]$W, [double]$H, [double]$R) {
    $s = $script:Scale; $d = [single](2 * $R * $s)
    $x0 = [single]($X * $s); $y0 = [single]($Y * $s); $x1 = [single](($X + $W) * $s - $d); $y1 = [single](($Y + $H) * $s - $d)
    $path = [System.Drawing.Drawing2D.GraphicsPath]::new()
    $path.AddArc($x0, $y0, $d, $d, 180, 90); $path.AddArc($x1, $y0, $d, $d, 270, 90)
    $path.AddArc($x1, $y1, $d, $d, 0, 90);   $path.AddArc($x0, $y1, $d, $d, 90, 90)
    $path.CloseFigure()
    $path
}

function Write-HudPanel([string]$Color, [double]$X, [double]$Y, [double]$W, [double]$H, [double]$R = 2.5) {
    $path = Get-RoundedPath $X $Y $W $H $R
    $script:BackG.FillPath((Get-Brush $Color), $path)
    $path.Dispose()
}

# A gauge: dark track, a fill whose colour follows the value (red - amber - green), tick marks.
function Write-HudGauge([double]$X, [double]$Y, [double]$W, [double]$H, [double]$Fraction, [string]$Low, [string]$High) {
    $Fraction = [Math]::Max(0.0, [Math]::Min(1.0, $Fraction))
    Write-HudPanel '0A1220' $X $Y $W $H 1.5
    if ($Fraction -gt 0.01) {
        $s = $script:Scale
        $rect = [System.Drawing.RectangleF]::new([single]($X * $s), [single]($Y * $s), [single]($W * $s), [single]($H * $s))
        $c1 = [System.Drawing.Color]::FromArgb([Convert]::ToInt32('FF' + $Low, 16)); $c2 = [System.Drawing.Color]::FromArgb([Convert]::ToInt32('FF' + $High, 16))
        $brush = [System.Drawing.Drawing2D.LinearGradientBrush]::new($rect, $c1, $c2, [single]0)
        $path = Get-RoundedPath ($X + 0.6) ($Y + 0.6) (($W - 1.2) * $Fraction) ($H - 1.2) 1.0
        $script:BackG.FillPath($brush, $path)
        $path.Dispose(); $brush.Dispose()
    }
    for ($t = 1; $t -lt 10; $t++) { Write-HudBar '700A1220' ($X + $W * $t / 10) $Y 0.5 $H }
}

function Show-Hud {
    $p = $script:P; $y = $script:ViewH; $g = $script:BackG; $s = $script:Scale
    $old = $g.SmoothingMode; $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias

    # backdrop: a dark gradient with a thin accent line towards the view
    $rect = [System.Drawing.RectangleF]::new(0, [single]($y * $s), [single](320 * $s), [single](40 * $s))
    $bg = [System.Drawing.Drawing2D.LinearGradientBrush]::new($rect, [System.Drawing.Color]::FromArgb(255, 22, 30, 46), [System.Drawing.Color]::FromArgb(255, 6, 9, 16), [single]90)
    $g.FillRectangle($bg, $rect); $bg.Dispose()
    Write-HudBar '40E0FF' 0 $y 320 0.7
    Write-HudBar '3040E0FF' 0 ($y + 0.7) 320 1.2

    # floor, score, lives
    Write-HudPanel '80101A2C' 4 ($y + 4) 70 33
    Write-HudText $(if ($script:DungeonSeed) { 'DUNGEON' } elseif ($script:BonusMap) { 'BONUS' } else { "FLOOR $($script:LevelIndex + 1)" }) 'Small' $(if ($script:BonusMap -or $script:DungeonSeed) { 'F0D040' } else { '40E0FF' }) 6 ($y + 5) 30 8
    Write-HudText ('{0:000000}' -f $p.Score) 'Mid' 'FFFFFF' 4 ($y + 13) 70 12
    Write-HudText ([string]::new([char]0x2665, [Math]::Min(9, [Math]::Max(0, $p.Lives)))) 'Small' 'FF4060' 4 ($y + 26) 70 9

    # health
    $hp = $p.Health
    $hpColor = if ($hp -le 25) { 'FF5040' } elseif ($hp -le 50) { 'FFC040' } else { 'FFFFFF' }
    Write-HudPanel '80101A2C' 78 ($y + 4) 72 33
    Write-HudText 'HEALTH' 'Small' '8FB0FF' 80 ($y + 5) 30 8
    Write-HudText "$hp" 'Big' $hpColor 78 ($y + 10) 72 18
    $low, $high = if ($hp -le 25) { 'C02020', 'FF5040' } elseif ($hp -le 50) { 'C07010', 'FFC040' } else { '20A040', '60FF80' }
    Write-HudGauge 82 ($y + 29) 64 5 ($hp / 100.0) $low $high

    Show-Face 153 ($y + 3)

    # ammunition - or whatever the weapon in hand consumes
    $res = Get-WeaponResource
    Write-HudPanel '80101A2C' 186 ($y + 4) 60 33
    Write-HudText $res.Label 'Small' '8FB0FF' 188 ($y + 5) 34 8
    Write-HudText $res.Text 'Big' $(if ($res.Fraction -le 0.05 -and $res.Text -ne '-') { 'FF5040' } else { 'FFFFFF' }) 186 ($y + 10) 60 18
    Write-HudGauge 190 ($y + 29) 52 5 $res.Fraction 'B07010' 'FFD860'

    # weapon slots, weapon name, keys
    Write-HudPanel '80101A2C' 250 ($y + 4) 66 33
    $n = $script:Weapons.Count; $bw = 62.0 / $n
    for ($i = 0; $i -lt $n; $i++) {
        $x = 252 + $i * $bw
        $current = $i -eq $p.Weapon
        $color = if ($current) { '40E0FF' } elseif ($p.Owned[$i]) { '2C4A86' } else { '141E30' }
        Write-HudPanel $color $x ($y + 6) ($bw - 1) 9 1.2
        Write-HudText "$($i + 1)" 'Small' $(if ($current) { '000000' } elseif ($p.Owned[$i]) { 'C0D0F0' } else { '3A4660' }) $x ($y + 6.5) ($bw - 1) 8
    }
    Write-HudText $script:Weapons[$p.Weapon].Name.ToUpper() 'Small' $(if ($p.Weapon -ge $script:WEAPON_PIPELINE) { '40E0FF' } else { 'FFFFFF' }) 250 ($y + 17) 66 9
    foreach ($k in @($p.KeyGold, 'E8C020', 266), @($p.KeySilver, 'D0D8E0', 286)) {
        $c = if ($k[0]) { $k[1] } else { '18243A' }
        $g.FillEllipse((Get-Brush $c), [single]($k[2] * $s), [single](($y + 28) * $s), [single](6 * $s), [single](6 * $s))
        $g.FillEllipse((Get-Brush '101A2C'), [single](($k[2] + 1.8) * $s), [single](($y + 29.8) * $s), [single](2.4 * $s), [single](2.4 * $s))
        Write-HudBar $c ($k[2] + 5.5) ($y + 30) 8 2; Write-HudBar $c ($k[2] + 10) ($y + 32) 1.5 2.5; Write-HudBar $c ($k[2] + 12.5) ($y + 32) 1.5 2
    }

    $g.SmoothingMode = $old
    $script:HudDirty = $false
}

# What the ammo panel shows depends on the weapon in hand.
function Get-WeaponResource {
    $p = $script:P
    $res = $script:Weapons[$p.Weapon].Res
    if ($res -eq 'none') { return @{ Label = 'AMMO'; Text = '-'; Fraction = 0.0 } }
    $count = Get-ResourceCount $res
    @{ Label = $res.ToUpper(); Text = "$count"; Fraction = $count / [double]$script:ResourceMax[$res] }
}

# ---- automap and minimap ----------------------------------------------------------------------
# Both draw from one bitmap of everything seen so far (8 pixels per tile, padded so the minimap
# can crop around the player without leaving the image). It is updated incrementally twice a
# second: only tiles that are new or have changed are painted.
$script:MAP_CELL = 8
$script:MAP_PAD = 10
$script:MapColors = @{ 1 = '8A8A8A'; 2 = '8A8A8A'; 3 = '8A8A8A'; 4 = '3048B8'; 5 = '3048B8'; 6 = '8A5A28'; 7 = '8A5A28'; 8 = '8A5A28'; 9 = 'A43828'; 10 = 'A43828'; 11 = '7A8A9A'; 12 = 'D02020'; 13 = '20C040'; 19 = '5A7A4A'; 20 = '5A7A4A'; 21 = '4A6A80'; 22 = '4A6A80'; 23 = 'E040E0'; 24 = '20C040'; 40 = '4060F0'; 41 = 'F0D040'; 33 = 'A0D0FF'; 34 = 'A0D0FF'; 35 = 'A0D0FF'; 36 = 'A0D0FF'; 37 = 'A0D0FF'; 38 = 'A0D0FF'; 39 = 'A0D0FF' }

function Update-MapBitmap {
    $now = $script:Clock.Elapsed.TotalSeconds
    if ($script:MapBmp -and $now -lt $script:MapBmpTime + 0.5) { return }
    $script:MapBmpTime = $now
    $mw = $script:MapW; $mh = $script:MapH; $cell = $script:MAP_CELL; $pad = $script:MAP_PAD
    if ($null -eq $script:MapBmp) {
        $script:MapBmp = [System.Drawing.Bitmap]::new(($mw + 2 * $pad) * $cell, ($mh + 2 * $pad) * $cell, [System.Drawing.Imaging.PixelFormat]::Format32bppPArgb)
        $script:MapDrawn = [int[]]::new($mw * $mh)
    }
    $mg = $null
    $vis = $script:Vis; $tiles = $script:Tiles; $drawn = $script:MapDrawn
    for ($i = 0; $i -lt $drawn.Length; $i++) {
        if ($vis[$i] -eq 0) { continue }                                     # never seen
        $t = $tiles[$i]
        if ($drawn[$i] -eq $t + 1) { continue }                              # already painted like this
        if ($null -eq $mg) { $mg = [System.Drawing.Graphics]::FromImage($script:MapBmp) }
        $c = if ($t -eq 0) { '5A5A5A' } elseif ($t -ge 200) { '8A8A8A' } elseif ($t -ge 100) { ('40E0E0', 'E8C020', 'D0D8E0', 'FFFFFF', 'E040E0')[[Math]::Min(4, $script:Doors[$t - 100].Lock)] } else { $script:MapColors[$t] }
        if (-not $c) { $c = '8A8A8A' }
        $x = $i % $mw; $y = [int][Math]::Floor($i / $mw)
        $mg.FillRectangle((Get-Brush $c), ($x + $pad) * $cell, ($y + $pad) * $cell, $cell - 1, $cell - 1)
        $drawn[$i] = $t + 1
    }
    if ($mg) { $mg.Dispose() }
}

function Show-AutoMap {
    Update-MapBitmap
    $g = $script:BackG; $s = $script:Scale; $cell = $script:MAP_CELL; $pad = $script:MAP_PAD
    $mw = $script:MapW; $mh = $script:MapH
    $zoom = [Math]::Min(320.0 * $s / ($mw * $cell), 200.0 * $s / ($mh * $cell))
    $w = $mw * $cell * $zoom; $h = $mh * $cell * $zoom
    $ox = (320 * $s - $w) / 2; $oy = (200 * $s - $h) / 2
    Write-HudBar 'C8000000' 0 0 320 200
    $src = [System.Drawing.RectangleF]::new($pad * $cell, $pad * $cell, $mw * $cell, $mh * $cell)
    $g.DrawImage($script:MapBmp, [System.Drawing.RectangleF]::new($ox, $oy, $w, $h), $src, [System.Drawing.GraphicsUnit]::Pixel)
    # the player: a dot with a nose
    $p = $script:P; $rad = $p.Angle * [Math]::PI / 180.0; $tile = $cell * $zoom
    $cx = $ox + $p.X * $tile; $cy = $oy + $p.Y * $tile
    $g.FillEllipse((Get-Brush '40FF40'), [single]($cx - $tile / 3), [single]($cy - $tile / 3), [single]($tile / 1.5), [single]($tile / 1.5))
    $pen = [System.Drawing.Pen]::new([System.Drawing.Color]::FromArgb(255, 64, 255, 64), [single]2)
    $g.DrawLine($pen, [single]$cx, [single]$cy, [single]($cx + [Math]::Cos($rad) * $tile), [single]($cy - [Math]::Sin($rad) * $tile))
    $pen.Dispose()
}

# The minimap in the corner of the view: the surroundings within 9 tiles, north up, plus a
# radar - every enemy that is hunting you shows up as a red dot, seen or not.
function Show-MiniMap {
    Update-MapBitmap
    $g = $script:BackG; $s = $script:Scale; $cell = $script:MAP_CELL; $pad = $script:MAP_PAD
    $p = $script:P; $radius = 9
    $size = 50 * $s; $x0 = (320 - 53) * $s; $y0 = 3 * $s
    Write-HudBar '90000000' (320 - 54) 2 52 52
    $src = [System.Drawing.RectangleF]::new(($p.X + $pad - $radius) * $cell, ($p.Y + $pad - $radius) * $cell, 2 * $radius * $cell, 2 * $radius * $cell)
    $g.DrawImage($script:MapBmp, [System.Drawing.RectangleF]::new($x0, $y0, $size, $size), $src, [System.Drawing.GraphicsUnit]::Pixel)
    $unit = $size / (2.0 * $radius); $cx = $x0 + $size / 2; $cy = $y0 + $size / 2
    $dot = [single][Math]::Max(3, $unit * 0.9)
    foreach ($a in $script:Actors) {
        if (-not $a.AttackMode -or -not $a.Shootable) { continue }
        $dx = $a.X - $p.X; $dy = $a.Y - $p.Y
        if ([Math]::Abs($dx) -ge $radius -or [Math]::Abs($dy) -ge $radius) { continue }
        $ex = $cx + $dx * $unit; $ey = $cy + $dy * $unit
        if ($a.Dir -ge 0 -and $a.Dir -lt 8) {                        # a nose: where he is facing, which is where he is going
            $nose = $a.Dir * [Math]::PI / 4
            $g.DrawLine($script:RadarPen, [single]$ex, [single]$ey, [single]($ex + [Math]::Cos($nose) * $unit * 1.8), [single]($ey - [Math]::Sin($nose) * $unit * 1.8))
        }
        $g.FillEllipse((Get-Brush 'FF3030'), [single]($ex - $dot / 2), [single]($ey - $dot / 2), $dot, $dot)
    }
    if ($script:NetLive -and $script:Net.Mode -eq 'coop') {          # the partners: blue dots
        foreach ($pl in $script:Net.Players.Values) {
            $dx = $pl.Ghost.X - $p.X; $dy = $pl.Ghost.Y - $p.Y
            if ([Math]::Abs($dx) -lt $radius -and [Math]::Abs($dy) -lt $radius) { $g.FillEllipse((Get-Brush '40A0FF'), [single]($cx + $dx * $unit - $dot / 2), [single]($cy + $dy * $unit - $dot / 2), $dot, $dot) }
        }
    }
    $rad = $p.Angle * [Math]::PI / 180.0
    $g.FillEllipse((Get-Brush '40FF40'), [single]($cx - $dot / 2), [single]($cy - $dot / 2), $dot, $dot)
    $pen = [System.Drawing.Pen]::new([System.Drawing.Color]::FromArgb(255, 64, 255, 64), [single]2)
    $g.DrawLine($pen, [single]$cx, [single]$cy, [single]($cx + [Math]::Cos($rad) * $unit * 2), [single]($cy - [Math]::Sin($rad) * $unit * 2))
    $pen.Dispose()
}
