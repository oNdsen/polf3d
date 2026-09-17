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
        Mid   = [System.Drawing.Font]::new('Consolas', [single](5.0 * $Scale), [System.Drawing.FontStyle]::Bold)
        Big   = [System.Drawing.Font]::new('Consolas', [single](8.5 * $Scale), [System.Drawing.FontStyle]::Bold)
        Huge  = [System.Drawing.Font]::new('Consolas', [single](22 * $Scale), [System.Drawing.FontStyle]::Bold)
    }
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

    [Array]::Copy($script:BG, $fb, $fb.Length)

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
        [PolfScaler]::Wall($fb, $W, $H, $col, $step, [int]($projH / $perp), $tex, $texX)
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

    if ($draw.Count) {
        $k = $keys.ToArray(); $items = $draw.ToArray()
        [Array]::Sort($k, $items)                               # far to near
        foreach ($it in $items) { [PolfScaler]::Sprite($fb, $W, $H, $zbuf, $it[0], $it[1], $it[2], $it[3]) }
    }

    # ---- the weapon in the player's hands ------------------------------------------------------
    if ($script:ShowWeapon) {
        $wtex = $script:Spr["weapon.$($script:Weapons[$p.Weapon].Key)"][$p.WeaponFrame]
        [PolfScaler]::Sprite($fb, $W, $H, $zbuf, $wtex, [int]$halfW, $H, 0.0)
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
        $shaken = [System.Drawing.Rectangle]::new($r.X - 8 + $script:Rng.Next(-$amp, $amp + 1), $r.Y - 8 + $script:Rng.Next(-$amp, $amp + 1), $r.Width + 16, $r.Height + 16)
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
    # progress on this floor, and the clock when speedrunning
    $st = $script:Stats
    Write-HudText ("KILLS {0}/{1}   SECRETS {2}/{3}   TREASURE {4}/{5}" -f $st.Kills, $st.KillTotal, $st.Secrets, $st.SecretTotal, $st.Treasures, $st.TreasureTotal) 'Small' 'A0B4D0' 2 ($viewH - 19) 150 8
    if ($script:Speedrun) {
        $now = $st.Tics / $script:TICRATE
        Write-HudText ("{0}   par {1}   run {2}" -f (Format-Time $now -Tenths), (Format-Time $script:ParSeconds), (Format-Time (($script:P.RunTics + $st.Tics) / $script:TICRATE))) 'Mid' $(if ($now -le $script:ParSeconds) { '40FF60' } else { 'FF8040' }) 60 14 200 10
    }
    if ($script:ShowFps) { Write-HudText ("{0:0} fps" -f $script:Fps) 'Small' '80FF80' 2 2 40 8 }
    if ($script:Message -and $script:Clock.Elapsed.TotalSeconds -lt $script:MessageUntil) {
        Write-HudText $script:Message 'Mid' '000000' 0.6 6.6 320 10
        Write-HudText $script:Message 'Mid' 'FFE860' 0 6 320 10
    }
}

function Show-Face([double]$X, [double]$Y) {
    $p = $script:P; $g = $script:BackG; $s = $script:Scale
    $hp = $p.Health
    Write-HudBar '10203C' $X $Y 28 34
    $g.FillEllipse((Get-Brush 'E0A878'), [single](($X + 4) * $s), [single](($Y + 4) * $s), [single](20 * $s), [single](27 * $s))
    Write-HudBar '6A4420' ($X + 5) ($Y + 3) 18 7
    $look = if ($hp -le 0) { 0 } else { $p.FaceLook * 1.5 }
    if ($hp -le 0) {
        Write-HudText 'x' 'Small' '101010' ($X + 5) ($Y + 11) 8 8; Write-HudText 'x' 'Small' '101010' ($X + 15) ($Y + 11) 8 8
    }
    else {
        Write-HudBar 'FFFFFF' ($X + 8) ($Y + 13) 5 4; Write-HudBar 'FFFFFF' ($X + 15) ($Y + 13) 5 4
        Write-HudBar '203060' ($X + 9.5 + $look) ($Y + 13.5) 2 3; Write-HudBar '203060' ($X + 16.5 + $look) ($Y + 13.5) 2 3
    }
    Write-HudBar 'C08860' ($X + 13) ($Y + 17) 2 5
    if ($p.GrinTics -gt 0) { Write-HudBar 'FFFFFF' ($X + 9) ($Y + 24) 10 3; Write-HudBar '7A3030' ($X + 9) ($Y + 23.4) 10 0.8 }
    elseif ($hp -gt 60) { Write-HudBar '7A3030' ($X + 10) ($Y + 25) 8 1.2 }
    elseif ($hp -gt 25) { Write-HudBar '7A3030' ($X + 10) ($Y + 25.5) 8 1.2; Write-HudBar '7A3030' ($X + 9) ($Y + 26.5) 2 1.2 }
    else { Write-HudBar '501010' ($X + 10) ($Y + 24) 8 4 }
    if ($hp -le 75) { Write-HudBar 'B01010' ($X + 19) ($Y + 9) 2 5 }
    if ($hp -le 50) { Write-HudBar 'B01010' ($X + 7) ($Y + 18) 3 2; Write-HudBar 'B01010' ($X + 12) ($Y + 22) 1.5 4 }
    if ($hp -le 25) { Write-HudBar 'B01010' ($X + 16) ($Y + 6) 2 8; Write-HudBar 'B01010' ($X + 20) ($Y + 20) 3 3; Write-HudBar '5A2A6A' ($X + 7) ($Y + 11) 6 2 }
}

function Show-Hud {
    $p = $script:P; $y = $script:ViewH
    Write-HudBar '0A1428' 0 $y 320 40
    Write-HudBar '2C4A86' 0 $y 320 1.5
    $cells = @(
        @(4, 40, 'FLOOR', "$($script:LevelIndex + 1)"), @(48, 68, 'SCORE', ('{0:000000}' -f $p.Score)), @(120, 30, 'LIVES', "$($p.Lives)"),
        @(188, 46, 'HEALTH', "$($p.Health)%"), @(238, 36, 'AMMO', "$($p.Ammo)")
    )
    foreach ($c in $cells) {
        Write-HudBar '1A2E5A' $c[0] ($y + 4) $c[1] 33
        Write-HudText $c[2] 'Small' '8FB0FF' $c[0] ($y + 5) $c[1] 8
        $col = if ($c[2] -eq 'HEALTH' -and $p.Health -le 25) { 'FF5040' } else { 'FFFFFF' }
        Write-HudText $c[3] 'Big' $col $c[0] ($y + 14) $c[1] 22
    }
    Show-Face 155 ($y + 3)
    # keys
    Write-HudBar '1A2E5A' 278 ($y + 4) 12 33
    Write-HudBar $(if ($p.KeyGold) { 'E8C020' } else { '101C38' }) 280 ($y + 8) 8 11
    Write-HudBar $(if ($p.KeySilver) { 'D0D8E0' } else { '101C38' }) 280 ($y + 23) 8 11
    # weapon
    Write-HudBar '1A2E5A' 294 ($y + 4) 23 33
    Write-HudText 'WEAPON' 'Small' '8FB0FF' 292 ($y + 5) 27 8
    $special = $p.Weapon -ge $script:WEAPON_PIPELINE
    Write-HudText $script:Weapons[$p.Weapon].Short 'Small' $(if ($special) { '40E0FF' } else { 'FFFFFF' }) 290 ($y + 15) 31 10
    if ($p.Owned[$script:WEAPON_FORCE]) { Write-HudText "F x$($p.Charges)" 'Small' '40FF60' 290 ($y + 26) 31 9 }
    $script:HudDirty = $false
}

# ---- automap and minimap ----------------------------------------------------------------------
# Both draw from one bitmap of everything seen so far (8 pixels per tile, padded so the minimap
# can crop around the player without leaving the image). It is updated incrementally twice a
# second: only tiles that are new or have changed are painted.
$script:MAP_CELL = 8
$script:MAP_PAD = 10
$script:MapColors = @{ 1 = '8A8A8A'; 2 = '8A8A8A'; 3 = '8A8A8A'; 4 = '3048B8'; 5 = '3048B8'; 6 = '8A5A28'; 7 = '8A5A28'; 8 = '8A5A28'; 9 = 'A43828'; 10 = 'A43828'; 11 = '7A8A9A'; 12 = 'D02020'; 13 = '20C040'; 19 = '5A7A4A'; 20 = '5A7A4A'; 21 = '4A6A80'; 22 = '4A6A80' }

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
        $g.FillEllipse((Get-Brush 'FF3030'), [single]($cx + $dx * $unit - $dot / 2), [single]($cy + $dy * $unit - $dot / 2), $dot, $dot)
    }
    $rad = $p.Angle * [Math]::PI / 180.0
    $g.FillEllipse((Get-Brush '40FF40'), [single]($cx - $dot / 2), [single]($cy - $dot / 2), $dot, $dot)
    $pen = [System.Drawing.Pen]::new([System.Drawing.Color]::FromArgb(255, 64, 255, 64), [single]2)
    $g.DrawLine($pen, [single]$cx, [single]$cy, [single]($cx + [Math]::Cos($rad) * $unit * 2), [single]($cy - [Math]::Sin($rad) * $unit * 2))
    $pen.Dispose()
}
