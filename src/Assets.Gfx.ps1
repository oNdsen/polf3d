# POLF 3D - Copyright (c) 2026 oNdsen. Licensed under the MIT License, see LICENSE.

# Assets.Gfx.ps1 - every texture and sprite is drawn procedurally at start-up with GDI+
# (no image files, nothing taken from the original game). All art is 64x64, returned as
# int[4096] ARGB; 0 = transparent.

$script:Brushes = @{}
$script:GFX = $null          # graphics of the canvas currently being painted

function Get-Brush([string]$Hex) {
    $b = $script:Brushes[$Hex]
    if ($null -eq $b) {
        $h = if ($Hex.Length -eq 6) { 'FF' + $Hex } else { $Hex }
        $b = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb([Convert]::ToInt32($h, 16)))
        $script:Brushes[$Hex] = $b
    }
    $b
}

function New-Canvas {
    $bmp = [System.Drawing.Bitmap]::new(64, 64, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $script:GFX = [System.Drawing.Graphics]::FromImage($bmp)
    $script:GFX.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::None
    $bmp
}

function Get-Pixels([System.Drawing.Bitmap]$Bmp, [switch]$FlipX) {
    if ($FlipX) { $Bmp.RotateFlip([System.Drawing.RotateFlipType]::RotateNoneFlipX) }
    $rect = [System.Drawing.Rectangle]::new(0, 0, 64, 64)
    $bd = $Bmp.LockBits($rect, [System.Drawing.Imaging.ImageLockMode]::ReadOnly, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $px = [int[]]::new(4096)
    [System.Runtime.InteropServices.Marshal]::Copy($bd.Scan0, $px, 0, 4096)
    $Bmp.UnlockBits($bd)
    if ($FlipX) { $Bmp.RotateFlip([System.Drawing.RotateFlipType]::RotateNoneFlipX) }
    , $px
}

# --- tiny drawing vocabulary -----------------------------------------------------------------
function Add-Box([string]$C, [int]$X, [int]$Y, [int]$W, [int]$H) { $script:GFX.FillRectangle((Get-Brush $C), $X, $Y, $W, $H) }
function Add-Oval([string]$C, [int]$X, [int]$Y, [int]$W, [int]$H) { $script:GFX.FillEllipse((Get-Brush $C), $X, $Y, $W, $H) }
function Add-Poly([string]$C, [int[]]$Pts) {
    $p = [System.Drawing.Point[]]::new($Pts.Count / 2)
    for ($i = 0; $i -lt $p.Count; $i++) { $p[$i] = [System.Drawing.Point]::new($Pts[2 * $i], $Pts[2 * $i + 1]) }
    $script:GFX.FillPolygon((Get-Brush $C), $p)
}
function Add-Speckle([string[]]$Colors, [int]$Count) {
    for ($i = 0; $i -lt $Count; $i++) {
        Add-Box $Colors[$script:Rng.Next($Colors.Count)] $script:Rng.Next(64) $script:Rng.Next(64) 1 1
    }
}
function Set-Pivot([double]$Px, [double]$Py, [double]$Angle, [double]$Sx = 1, [double]$Sy = 1) {
    $script:GFX.TranslateTransform($Px, $Py)
    $script:GFX.RotateTransform($Angle)
    $script:GFX.ScaleTransform($Sx, $Sy)
    $script:GFX.TranslateTransform(-$Px, -$Py)
}
function Reset-Pivot { $script:GFX.ResetTransform() }

# =============================================================================================
# WALLS
# =============================================================================================
function Add-BlockPattern([string]$Mortar, [string[]]$Colors, [string]$Hi, [int]$Bw, [int]$Bh) {
    Add-Box $Mortar 0 0 64 64
    $row = 0
    for ($y = 0; $y -lt 64; $y += $Bh) {
        $off = if ($row % 2) { [int]($Bw / 2) } else { 0 }
        for ($x = - $off; $x -lt 64; $x += $Bw) {
            Add-Box $Colors[$script:Rng.Next($Colors.Count)] ($x + 1) ($y + 1) ($Bw - 1) ($Bh - 1)
            Add-Box $Hi ($x + 1) ($y + 1) ($Bw - 1) 1
        }
        $row++
    }
}

function Add-WallBase([string]$Kind) {
    switch ($Kind) {
        'stone' { Add-BlockPattern '4A4A4A' @('808080', '787878', '888888', '707070') '9A9A9A' 32 16; Add-Speckle @('6A6A6A', '909090') 160 }
        'blue'  { Add-BlockPattern '101838' @('2838A0', '2C40B0', '243090', '3048B8') '4860D0' 16 16; Add-Speckle @('1C2878', '4058C8') 140 }
        'brick' { Add-BlockPattern 'B0A088' @('9A3020', '8A2818', 'A43828', '902C1C') 'B84838' 16 8; Add-Speckle @('7A2010', 'B04030') 120 }
        'wood'  {
            Add-Box '7A4A20' 0 0 64 64
            for ($x = 0; $x -lt 64; $x += 16) { Add-Box '5A3414' $x 0 1 64; Add-Box '8C5828' ($x + 1) 0 1 64 }
            for ($i = 0; $i -lt 40; $i++) { Add-Box '6A3E1A' $script:Rng.Next(64) $script:Rng.Next(64) 1 (4 + $script:Rng.Next(14)) }
            Add-Box '4A2A10' 0 0 64 3; Add-Box '4A2A10' 0 61 64 3; Add-Box '9A6430' 0 3 64 1
        }
        'moss' {
            Add-BlockPattern '1E261C' @('5A6A52', '4E5E4A', '66745A', '56624E') '7A8A6A' 32 16
            Add-Speckle @('3A5A30', '4A7A3A', '2E4A28') 420
            for ($i = 0; $i -lt 14; $i++) { Add-Oval '3E6A32' $script:Rng.Next(60) $script:Rng.Next(60) (3 + $script:Rng.Next(6)) (2 + $script:Rng.Next(4)) }
        }
        'tech' {
            Add-Box '3A4450' 0 0 64 64
            foreach ($py in 0, 32) {
                Add-Box '56626F' 0 $py 64 1; Add-Box '242B33' 0 ($py + 31) 64 1
                Add-Box '4A5561' 2 ($py + 3) 60 26; Add-Box '5C6875' 2 ($py + 3) 60 1
                for ($x = 6; $x -lt 60; $x += 9) { Add-Box '2E363F' $x ($py + 8) 5 16 }
            }
            Add-Box '20C0E0' 0 30 64 1; Add-Box '107088' 0 31 64 1
        }
        'steel' {
            Add-Box '6A7A8A' 0 0 64 64
            foreach ($py in 0, 32) { foreach ($px in 0, 32) {
                Add-Box '8A9AAA' $px $py 32 1; Add-Box '8A9AAA' $px $py 1 32
                Add-Box '4A5A6A' $px ($py + 31) 32 1; Add-Box '4A5A6A' ($px + 31) $py 1 32
                foreach ($r in @(3, 3), @(27, 3), @(3, 27), @(27, 27)) { Add-Box '3A4652' ($px + $r[0]) ($py + $r[1]) 2 2; Add-Box 'A8B8C8' ($px + $r[0]) ($py + $r[1]) 1 1 }
            } }
            Add-Speckle @('62727F', '748494') 100
        }
    }
}

function Add-Emblem([int]$X, [int]$Y) {       # the ">_" prompt - POLF's coat of arms
    Add-Poly 'FFFFFF' @($X, $Y, ($X + 3), $Y, ($X + 9), ($Y + 6), ($X + 3), ($Y + 12), $X, ($Y + 12), ($X + 6), ($Y + 6))
    Add-Box 'FFFFFF' ($X + 10) ($Y + 10) 8 3
}

function Add-WallArt([string]$Name) {
    switch ($Name) {
        'stone'  { Add-WallBase stone }
        'blue'   { Add-WallBase blue }
        'wood'   { Add-WallBase wood }
        'brick'  { Add-WallBase brick }
        'steel'  { Add-WallBase steel }
        'moss'   { Add-WallBase moss }
        'tech'   { Add-WallBase tech }
        'moss_vines' {
            Add-WallBase moss
            foreach ($vx in 8, 21, 37, 52) {
                $x = $vx
                for ($y = 0; $y -lt (34 + $script:Rng.Next(28)); $y += 3) { $x += $script:Rng.Next(3) - 1; Add-Box '2E6A28' $x $y 2 3; if ($y % 9 -eq 0) { Add-Oval '4A9A3A' ($x - 3) $y 5 3 } }
            }
        }
        'tech_lights' {
            Add-WallBase tech
            Add-Box '101418' 12 8 40 18; Add-Box '0A2A1A' 14 10 36 14
            foreach ($ly in 12, 16, 20) { Add-Box '30E070' 16 $ly (8 + $script:Rng.Next(22)) 1 }
            foreach ($l in @(14, 40, 'E03030'), @(22, 40, '30E070'), @(30, 40, 'E0C020'), @(38, 40, '30E070'), @(46, 40, '20C0E0')) { Add-Box '101418' ($l[0] - 1) ($l[1] - 1) 6 6; Add-Box $l[2] $l[0] $l[1] 4 4 }
        }
        { $_ -in 'stone_banner', 'brick_banner' } {
            Add-WallBase ($Name -replace '_banner')
            Add-Box 'C8A030' 16 4 32 3
            Add-Poly '1C3C9C' @(19, 7, 45, 7, 45, 50, 32, 58, 19, 50)
            Add-Poly '2C54C4' @(21, 7, 43, 7, 43, 48, 32, 55, 21, 48)
            Add-Emblem 23 20
        }
        'stone_pic' {
            Add-WallBase stone
            Add-Box 'C8A030' 12 14 40 32; Add-Box '8A6A18' 14 16 36 28
            Add-Box '78B8E8' 15 17 34 14; Add-Box '4A9A3A' 15 31 34 12
            Add-Oval 'F8E060' 38 19 8 8; Add-Poly '3A7A2A' @(15, 36, 28, 24, 40, 36); Add-Poly '6A6A72' @(30, 36, 40, 27, 49, 36)
        }
        'blue_cell' {
            Add-WallBase blue
            Add-Box '5A5A5A' 14 10 36 48; Add-Box '080808' 16 12 32 46
            Add-Oval 'D8D8C0' 27 30 9 9; Add-Box '080808' 29 33 2 2; Add-Box '080808' 33 33 2 2; Add-Box 'D8D8C0' 29 39 6 12
            for ($x = 18; $x -lt 48; $x += 6) { Add-Box '8A8A8A' $x 12 2 46; Add-Box 'B0B0B0' $x 12 1 46 }
            Add-Box '8A8A8A' 16 32 32 2
        }
        'wood_pic' {
            Add-WallBase wood
            Add-Box 'C8A030' 14 12 36 40; Add-Box '2A1A10' 16 14 32 36
            Add-Oval 'E0A878' 25 19 14 16; Add-Box '303030' 24 17 16 5; Add-Box '5A2A2A' 22 35 20 15
            Add-Box '101010' 28 25 2 2; Add-Box '101010' 34 25 2 2
        }
        'wood_shield' {
            Add-WallBase wood
            Add-Poly 'C8A030' @(18, 12, 46, 12, 46, 36, 32, 54, 18, 36)
            Add-Poly 'B02020' @(20, 14, 32, 14, 32, 50, 20, 35); Add-Poly 'E8E8E8' @(32, 14, 44, 14, 44, 35, 32, 50)
            Add-Box 'C8A030' 20 30 24 2
        }
        { $_ -in 'switch_off', 'switch_on' } {
            Add-WallBase steel
            Add-Box '2A323A' 20 14 24 36; Add-Box '101418' 22 16 20 32
            Add-Box '3A424A' 30 20 4 24
            if ($Name -eq 'switch_off') { Add-Box 'D02020' 27 18 10 8; Add-Box 'FF6060' 28 19 3 2; Add-Box '303030' 24 42 16 3 }
            else { Add-Box '20C040' 27 38 10 8; Add-Box '80FF90' 28 39 3 2; Add-Box '303030' 24 17 16 3 }
        }
        'jamb' {
            Add-Box '50585F' 0 0 64 64
            for ($x = 4; $x -lt 64; $x += 12) { Add-Box '3A4248' $x 0 2 64; Add-Box '6A747C' ($x + 2) 0 1 64 }
            Add-Box '1A1E22' 28 0 8 64; Add-Box '0A0C0E' 30 0 4 64
        }
        { $_ -like 'door*' } {
            if ($Name -eq 'door_lift') {
                Add-Box '7A8088' 0 0 64 64; Add-Box '9AA0A8' 0 0 64 1
                for ($x = -8; $x -lt 64; $x += 16) { Add-Poly 'E0C020' @($x, 10, ($x + 8), 10, ($x + 16), 2, ($x + 8), 2) }
                Add-Box '202020' 0 1 64 1; Add-Box '202020' 0 10 64 1
                Add-Box '3A4048' 31 11 2 53; Add-Box 'A8B0B8' 29 11 1 53; Add-Box 'A8B0B8' 34 11 1 53
                Add-Box '50585F' 8 20 18 36; Add-Box '50585F' 38 20 18 36
            }
            else {
                Add-Box '2A6A74' 0 0 64 64; Add-Box '3A8A96' 0 0 64 2; Add-Box '1A4A52' 0 62 64 2
                foreach ($p in @(6, 6), @(34, 6), @(6, 34), @(34, 34)) {
                    Add-Box '1F5A63' $p[0] $p[1] 24 24; Add-Box '347E89' ($p[0] + 2) ($p[1] + 2) 20 20; Add-Box '4A9AA6' ($p[0] + 2) ($p[1] + 2) 20 1
                }
                Add-Box '101010' 54 28 5 10; Add-Box 'C0C0C0' 55 29 3 8
                if ($Name -eq 'door_gold')   { Add-Box 'E8C020' 24 24 16 16; Add-Box '6A5408' 30 28 4 5; Add-Box '6A5408' 31 32 2 5 }
                if ($Name -eq 'door_silver') { Add-Box 'C8D0D8' 24 24 16 16; Add-Box '50585F' 30 28 4 5; Add-Box '50585F' 31 32 2 5 }
            }
        }
    }
}

function Initialize-WallTextures {
    $n = $script:WallNames.Count
    $script:WallLight = [object[]]::new($n)
    $script:WallDark = [object[]]::new($n)
    for ($i = 1; $i -lt $n; $i++) {
        $bmp = New-Canvas
        Add-WallArt $script:WallNames[$i]
        $script:WallLight[$i] = Get-Pixels $bmp
        Add-Box '60000000' 0 0 64 64            # east/west faces use a darker copy: cheap lighting
        $script:WallDark[$i] = Get-Pixels $bmp
        $script:GFX.Dispose(); $bmp.Dispose()
    }
}

# =============================================================================================
# SPRITES
# =============================================================================================
$script:Spr = @{}

function New-Sprite([scriptblock]$Paint, [switch]$FlipX) {
    $bmp = New-Canvas
    & $Paint
    $px = Get-Pixels $bmp -FlipX:$FlipX
    $script:GFX.Dispose(); $bmp.Dispose()
    , $px
}

$script:Palettes = @{
    guard   = @{ Skin = 'E0A878'; Hair = '5A3A1A'; Uniform = '8B6B3A'; UniformDark = '6B4F28'; Pants = '7A5C30'; PantsDark = '5C4420'; Boots = '201810'; Belt = '302010'; Hat = '707478'; HatDark = '505458'; HatStyle = 'helmet'; Gun = 'pistol' }
    officer = @{ Skin = 'E0A878'; Hair = '3A2A1A'; Uniform = 'D8D8C8'; UniformDark = 'B0B0A0'; Pants = 'C8C8B8'; PantsDark = 'A0A090'; Boots = '181818'; Belt = '604020'; Hat = 'D8D8C8'; HatDark = '303030'; HatStyle = 'cap'; Gun = 'pistol' }
    elite   = @{ Skin = 'E0A878'; Hair = 'C0A050'; Uniform = '3A5A9A'; UniformDark = '2A4478'; Pants = '34508A'; PantsDark = '243C6C'; Boots = '101018'; Belt = '101010'; Hat = '2A3A5A'; HatDark = '1A2A44'; HatStyle = 'helmet'; Gun = 'mg' }
    mutant  = @{ Skin = '7AA070'; Hair = '5A7A50'; Uniform = 'B0A880'; UniformDark = '8A8460'; Pants = '9A9470'; PantsDark = '7A7458'; Boots = '282820'; Belt = '403828'; Hat = '000000'; HatDark = '000000'; HatStyle = 'none'; Gun = 'chest' }
    pilot   = @{ Skin = 'E0A878'; Hair = '1A1A1A'; Uniform = '8A1C1C'; UniformDark = '641212'; Pants = '2A2A2A'; PantsDark = '181818'; Boots = '101010'; Belt = 'C0A030'; Hat = '2A2A2A'; HatDark = '101010'; HatStyle = 'cap'; Gun = 'mg' }
    boss    = @{ Skin = 'E0A878'; Hair = '3A2A1A'; Uniform = '5A7AA0'; UniformDark = '3E5A7C'; Pants = '4A6688'; PantsDark = '364E6A'; Boots = '202830'; Belt = 'C0A030'; Hat = '3A4A6A'; HatDark = '2A3650'; HatStyle = 'helmet'; Gun = 'twin' }
}

function Add-HatArt($p, [string]$View, [int]$bob) {
    switch ($p.HatStyle) {
        'helmet' {
            if ($View -eq 's') { Add-Oval $p.Hat 26 (5 + $bob) 14 10; Add-Box $p.Hat 26 (10 + $bob) 15 2 }
            else { Add-Oval $p.Hat 25 (5 + $bob) 14 10; Add-Box $p.Hat 25 (10 + $bob) 14 2; Add-Box $p.HatDark 25 (11 + $bob) 14 1 }
        }
        'cap' {
            if ($View -eq 's') { Add-Box $p.Hat 28 (6 + $bob) 10 5; Add-Box $p.HatDark 33 (10 + $bob) 8 2 }
            else {
                Add-Box $p.Hat 26 (5 + $bob) 12 5
                if ($View -eq 'f') { Add-Box $p.HatDark 26 (10 + $bob) 12 2; Add-Box 'E0C040' 31 (6 + $bob) 2 3 } else { Add-Box $p.HatDark 26 (9 + $bob) 12 1 }
            }
        }
    }
}

function Add-SoldierArt([hashtable]$p, [string]$View, [string]$Pose) {
    $lOff = 0; $rOff = 0; $bob = 0
    switch ($Pose) { 'w1' { $lOff = -3 } 'w2' { $bob = -1 } 'w3' { $rOff = -3 } 'w4' { $bob = -1 } }

    # ---- collapsing / dead: single view -------------------------------------------------------
    if ($Pose -eq 'die1') {
        Add-Box $p.Boots 22 59 8 4; Add-Box $p.Boots 34 59 8 4
        Add-Box $p.Pants 24 50 7 10; Add-Box $p.Pants 33 50 7 10
        Add-Box $p.Uniform 23 29 18 22; Add-Box $p.Belt 23 46 18 3
        Add-Box $p.Uniform 13 30 10 4; Add-Box $p.Uniform 41 30 10 4; Add-Box $p.Skin 11 30 3 4; Add-Box $p.Skin 50 30 3 4
        Add-Box $p.Skin 30 26 4 4; Add-Oval $p.Skin 27 15 10 12; Add-Box $p.Hair 27 15 10 3
        Add-Box '101010' 29 20 2 1; Add-Box '101010' 33 20 2 1; Add-Box '501010' 30 23 4 3
        Add-Box 'B00000' 29 33 5 7; Add-Box 'D01010' 30 34 2 3
        return
    }
    if ($Pose -eq 'die2') {
        Add-Oval '8B0000' 14 56 36 7
        Add-Box $p.Boots 8 52 5 8; Add-Box $p.Pants 12 54 14 6
        Add-Box $p.Uniform 24 43 18 15; Add-Box $p.Belt 24 43 3 15
        Add-Box $p.Uniform 42 47 10 4; Add-Box $p.Skin 52 47 3 4
        Add-Oval $p.Skin 37 34 10 11; Add-Box $p.Hair 37 34 10 3; Add-Box '501010' 41 41 3 2
        Add-Box 'B00000' 30 46 6 6
        return
    }
    if ($Pose -eq 'die3') {
        Add-Oval '8B0000' 8 57 48 6
        Add-Box $p.Boots 4 55 5 6; Add-Box $p.Pants 8 56 14 5
        Add-Box $p.Uniform 20 52 24 8; Add-Box $p.Belt 20 52 3 8
        Add-Oval $p.Skin 43 49 9 9; Add-Box $p.Hair 49 50 3 6
        Add-Box 'B00000' 28 53 8 4
        return
    }
    if ($Pose -eq 'dead') {
        Add-Oval '8B0000' 4 57 56 6; Add-Oval '6A0000' 14 58 30 4
        Add-Box $p.Boots 5 56 5 5; Add-Box $p.Pants 9 57 14 4
        Add-Box $p.Uniform 22 55 24 6; Add-Box $p.Belt 22 55 2 6; Add-Box 'B00000' 30 55 7 3
        Add-Oval $p.Skin 45 54 8 7; Add-Box $p.Hair 50 55 3 5
        return
    }

    # ---- side view (faces right; the left-facing version is mirrored) ---------------------------
    if ($View -eq 's') {
        $back = 29; $front = 29
        switch ($Pose) { 'w1' { $back = 22; $front = 36 } 'w3' { $back = 36; $front = 22 } }
        Add-Poly $p.PantsDark @(29, (40 + $bob), 35, (40 + $bob), ($back + 6), 59, $back, 59)
        Add-Box $p.Boots $back 59 9 4
        Add-Poly $p.Pants @(29, (40 + $bob), 35, (40 + $bob), ($front + 6), 59, $front, 59)
        Add-Box $p.Boots $front 59 9 4
        Add-Box $p.Uniform 27 (21 + $bob) 10 20; Add-Box $p.UniformDark 27 (21 + $bob) 2 20; Add-Box $p.Belt 27 (37 + $bob) 10 3
        Add-Box $p.Skin 30 (18 + $bob) 4 4
        Add-Oval $p.Skin 28 (8 + $bob) 10 12; Add-Box '101010' 35 (13 + $bob) 2 2; Add-Box $p.Skin 38 (14 + $bob) 1 2
        if ($p.HatStyle -eq 'none') { Add-Box $p.Hair 28 (9 + $bob) 5 3 } else { Add-HatArt $p 's' $bob }
        Add-Box $p.UniformDark 30 (23 + $bob) 4 12; Add-Box $p.Skin 31 (35 + $bob) 4 3
        switch ($p.Gun) {
            'pistol' { Add-Box '181818' 34 (34 + $bob) 7 3; Add-Box '181818' 34 (36 + $bob) 2 3 }
            'mg'     { Add-Box '181818' 31 (33 + $bob) 17 3; Add-Box '181818' 36 (36 + $bob) 2 4; Add-Box '4A3018' 28 (33 + $bob) 4 4 }
            'chest'  { Add-Box '202020' 36 (27 + $bob) 5 5 }
        }
        return
    }

    # ---- front / back -----------------------------------------------------------------------------
    $tx = if ($Pose -eq 'pain') { 2 } else { 0 }
    Add-Box $p.Boots 24 (59 + $lOff) 7 4; Add-Box $p.Boots 33 (59 + $rOff) 7 4
    Add-Box $p.Pants 25 (40 + $bob) 6 (19 + $lOff - $bob); Add-Box $p.Pants 33 (40 + $bob) 6 (19 + $rOff - $bob)
    Add-Box $p.PantsDark 30 (42 + $bob) 1 (15 + $lOff - $bob); Add-Box $p.PantsDark 33 (42 + $bob) 1 (15 + $rOff - $bob)
    Add-Box $p.Uniform (23 + $tx) (21 + $bob) 18 20
    Add-Box $p.UniformDark (23 + $tx) (21 + $bob) 2 20; Add-Box $p.UniformDark (39 + $tx) (21 + $bob) 2 20
    Add-Box $p.Belt (23 + $tx) (37 + $bob) 18 3
    if ($View -eq 'f') {
        Add-Box 'D0B040' (31 + $tx) (37 + $bob) 2 3
        foreach ($by in 24, 28, 32) { Add-Box $p.UniformDark (32 + $tx) ($by + $bob) 1 2 }
    }

    # head
    Add-Box $p.Skin (30 + $tx) (18 + $bob) 4 4
    Add-Oval $p.Skin (27 + $tx) (8 + $bob) 10 12
    if ($View -eq 'f') {
        Add-Box '101010' (29 + $tx) (13 + $bob) 2 2; Add-Box '101010' (33 + $tx) (13 + $bob) 2 2
        if ($Pose -eq 'pain') { Add-Box '501010' (30 + $tx) (16 + $bob) 4 3 } else { Add-Box '7A3030' (30 + $tx) (17 + $bob) 4 1 }
        if ($p.HatStyle -eq 'none') { Add-Box 'A01010' 28 10 3 2; Add-Box $p.Hair 29 8 6 2 }
    }
    else { Add-Box $p.Hair (27 + $tx) (12 + $bob) 10 6 }
    if ($Pose -ne 'pain') { Add-HatArt $p $View $bob } elseif ($p.HatStyle -ne 'none') { Add-Box $p.Hair (27 + $tx) (8 + $bob) 10 3 }

    # arms and gun
    if ($Pose -in 'aim', 'fire' -and $View -eq 'f' -and $p.Gun -ne 'chest') {
        Add-Box $p.Uniform 19 22 5 9; Add-Box $p.Uniform 40 22 5 9
        Add-Box $p.Uniform 21 29 9 4; Add-Box $p.Uniform 34 29 9 4
        Add-Box $p.Skin 28 28 8 6
        if ($p.Gun -eq 'mg') { Add-Box '101010' 29 25 6 9; Add-Box '404040' 31 27 2 2 } else { Add-Box '101010' 30 26 4 7; Add-Box '404040' 31 27 2 2 }
        if ($Pose -eq 'fire') { Add-Oval 'FF9020' 24 19 16 16; Add-Oval 'FFD040' 26 21 12 12; Add-Oval 'FFFFD0' 29 24 6 6 }
    }
    elseif ($Pose -eq 'pain') {
        Add-Box $p.Uniform 15 19 9 4; Add-Box $p.Skin 13 19 3 4
        Add-Box $p.Uniform 42 19 9 4; Add-Box $p.Skin 50 19 3 4
        Add-Box 'B00000' 31 27 4 5
    }
    else {
        Add-Box $p.Uniform 19 (22 + $bob) 4 14; Add-Box $p.Skin 19 (36 + $bob) 4 3
        Add-Box $p.Uniform 41 (22 + $bob) 4 14; Add-Box $p.Skin 41 (36 + $bob) 4 3
        if ($View -eq 'f') {
            switch ($p.Gun) {
                'pistol' { Add-Box '181818' 42 (38 + $bob) 3 6 }
                'mg'     { Add-Box '181818' 27 (32 + $bob) 19 3; Add-Box '4A3018' 24 (31 + $bob) 4 5; Add-Box '181818' 38 (35 + $bob) 2 4 }
            }
        }
    }
    if ($p.Gun -eq 'chest' -and $View -eq 'f') {
        Add-Box '202020' 29 (26 + $bob) 6 6; Add-Box '606060' 31 (28 + $bob) 2 2
        if ($Pose -eq 'fire') { Add-Oval 'FF9020' 24 21 16 16; Add-Oval 'FFFFD0' 28 25 8 8 }
    }
}

function Add-SoldierSprites([string]$Kind) {
    $p = $script:Palettes[$Kind]
    foreach ($pose in 's', 'w1', 'w2', 'w3', 'w4') {
        $ps = if ($pose -eq 's') { 'stand' } else { $pose }
        $f = New-Sprite { Add-SoldierArt $p 'f' $ps }
        $b = New-Sprite { Add-SoldierArt $p 'b' $ps }
        $r = New-Sprite { Add-SoldierArt $p 's' $ps }
        $l = New-Sprite { Add-SoldierArt $p 's' $ps } -FlipX
        $script:Spr["$Kind.$pose"] = @($f, $l, $b, $r)       # index = view: front, facing left, back, facing right
    }
    foreach ($pose in 'aim', 'fire', 'pain', 'die1', 'die2', 'die3', 'dead') {
        $script:Spr["$Kind.$pose"] = New-Sprite { Add-SoldierArt $p 'f' $pose }
    }
}

function Add-BossSprites {
    $p = $script:Palettes.boss
    $bossPaint = {
        param($pose)
        $flat = $pose -in 'die2', 'die3', 'dead'
        if (-not $flat) { Set-Pivot 32 63 0 1.35 1.1 }
        Add-SoldierArt $p 'f' $pose
        Reset-Pivot
        if (-not $flat -and $pose -ne 'die1') {
            foreach ($gx in 5, 49) {
                Add-Box '282828' $gx 30 10 20; Add-Box '484848' ($gx + 1) 30 2 20
                foreach ($bx in 1, 4, 7) { Add-Oval '101010' ($gx + $bx) 46 3 3 }
                if ($pose -eq 'fire') { Add-Oval 'FF9020' ($gx - 3) 40 16 16; Add-Oval 'FFFFD0' ($gx + 1) 44 8 8 }
            }
            Add-Box 'C03030' 28 28 8 3
        }
    }
    foreach ($pose in 's', 'w1', 'w2', 'w3', 'w4') {
        $ps = if ($pose -eq 's') { 'stand' } else { $pose }
        $script:Spr["boss.$pose"] = New-Sprite { & $bossPaint $ps }
    }
    foreach ($pose in 'aim', 'fire', 'die1', 'die2', 'die3', 'dead') {
        $ps = if ($pose -eq 'aim') { 'stand' } else { $pose }
        $script:Spr["boss.$pose"] = New-Sprite { & $bossPaint $ps }
    }
}

# ---- dog ------------------------------------------------------------------------------------
function Add-DogArt([string]$View, [string]$Pose) {
    $fur = '8A5A2B'; $dark = '5A3A1B'; $snout = '3A2A1A'
    if ($Pose -in 'die3', 'dead') {
        if ($Pose -eq 'dead') { Add-Oval '8B0000' 4 56 56 7 }
        Add-Oval $fur 10 49 40 11; Add-Oval $fur 44 47 13 12; Add-Box $snout 55 52 6 4
        Add-Box $dark 14 58 12 3; Add-Box $dark 34 58 12 3; Add-Poly $dark @(12, 52, 4, 48, 6, 47, 15, 50)
        Add-Box '101010' 50 51 2 1
        if ($Pose -eq 'dead') { Add-Box 'B00000' 26 50 8 3 }
        return
    }
    if ($View -eq 's') {
        $legs = switch ($Pose) { 'w1' { 12, 24, 38, 50 } 'w2' { 17, 21, 42, 46 } 'w3' { 16, 26, 36, 48 } 'w4' { 18, 22, 41, 45 } default { 15, 21, 40, 46 } }
        $bob = if ($Pose -in 'w2', 'w4') { -1 } else { 0 }
        $hip = 17, 21, 41, 45
        for ($i = 0; $i -lt 4; $i++) {
            $c = if ($i % 2) { $fur } else { $dark }
            Add-Poly $c @($hip[$i], 44, ($hip[$i] + 5), 44, ($legs[$i] + 4), 61, $legs[$i], 61)
        }
        Add-Oval $fur 12 (33 + $bob) 40 16
        Add-Poly $dark @(14, (38 + $bob), 5, (29 + $bob), 8, (28 + $bob), 18, (36 + $bob))
        Add-Oval $fur 43 (23 + $bob) 15 15; Add-Box $snout 55 (30 + $bob) 7 5; Add-Box '101010' 61 (30 + $bob) 2 2
        Add-Poly $dark @(45, (25 + $bob), 49, (17 + $bob), 53, (26 + $bob)); Add-Box '101010' 53 (28 + $bob) 2 2
        return
    }
    $l = 0; $r = 0
    switch ($Pose) { 'w1' { $l = -3 } 'w3' { $r = -3 } }
    Add-Oval $fur 21 32 22 22
    Add-Box $fur 23 48 6 (13 + $l); Add-Box $fur 35 48 6 (13 + $r); Add-Box $dark 23 (59 + $l) 6 2; Add-Box $dark 35 (59 + $r) 6 2
    if ($View -eq 'b') {
        Add-Poly $dark @(30, 36, 28, 20, 32, 18, 35, 36)
        Add-Poly $dark @(23, 30, 22, 22, 28, 28); Add-Poly $dark @(41, 30, 42, 22, 36, 28)
        return
    }
    Add-Oval $fur 21 20 22 20
    Add-Poly $dark @(22, 27, 21, 13, 29, 22); Add-Poly $dark @(42, 27, 43, 13, 35, 22)
    Add-Box '101010' 26 27 3 3; Add-Box '101010' 35 27 3 3
    Add-Oval $snout 27 31 10 8; Add-Box '101010' 30 31 4 2
    if ($Pose -like 'jump*') { Add-Oval 'A01010' 27 35 10 8; Add-Box 'FFFFFF' 28 35 2 3; Add-Box 'FFFFFF' 34 35 2 3; Add-Box 'FFFFFF' 29 41 2 2; Add-Box 'FFFFFF' 33 41 2 2 }
}

function Add-DogSprites {
    foreach ($pose in 's', 'w1', 'w2', 'w3', 'w4') {
        $f = New-Sprite { Add-DogArt 'f' $pose }
        $b = New-Sprite { Add-DogArt 'b' $pose }
        $r = New-Sprite { Add-DogArt 's' $pose }
        $l = New-Sprite { Add-DogArt 's' $pose } -FlipX
        $script:Spr["dog.$pose"] = @($f, $l, $b, $r)
    }
    $script:Spr['dog.jump1'] = New-Sprite { Set-Pivot 32 63 0 1.0 1.0;  Add-DogArt 'f' 'jump1'; Reset-Pivot }
    $script:Spr['dog.jump2'] = New-Sprite { Set-Pivot 32 70 0 1.3 1.3;  Add-DogArt 'f' 'jump2'; Reset-Pivot }
    $script:Spr['dog.jump3'] = New-Sprite { Set-Pivot 32 74 0 1.55 1.55; Add-DogArt 'f' 'jump3'; Reset-Pivot }
    $script:Spr['dog.die1'] = New-Sprite { Set-Pivot 32 50 -25; Add-DogArt 's' 's'; Reset-Pivot }
    $script:Spr['dog.die2'] = New-Sprite { Set-Pivot 32 54 -60 1 0.9; Add-DogArt 's' 's'; Reset-Pivot }
    $script:Spr['dog.die3'] = New-Sprite { Add-DogArt 's' 'die3' }
    $script:Spr['dog.dead'] = New-Sprite { Add-DogArt 's' 'dead' }
}

# ---- items and decoration ---------------------------------------------------------------------
function Add-ThingSprites {
    $S = $script:Spr
    $S['dogfood'] = New-Sprite { Add-Oval '8A8A92' 22 52 20 9; Add-Oval '5A5A62' 24 53 16 5; Add-Oval '7A4A2A' 25 51 14 6 }
    $S['food'] = New-Sprite { Add-Oval 'E8E8E8' 18 53 28 8; Add-Oval 'C0C0C0' 21 54 22 5; Add-Oval 'B06A2A' 24 47 14 10; Add-Box 'F0E8D0' 36 49 8 3; Add-Oval '3A8A2A' 20 52 7 5 }
    $S['medkit'] = New-Sprite { Add-Box 'E8E8E8' 20 46 24 16; Add-Box 'B8B8B8' 20 60 24 2; Add-Box '909090' 28 43 8 3; Add-Box 'D01818' 30 48 4 12; Add-Box 'D01818' 26 52 12 4 }
    $S['clip'] = New-Sprite { Add-Box '2A3A4A' 25 50 14 11; Add-Box '4A5A6A' 25 50 14 2; foreach ($x in 27, 30, 33, 36) { Add-Box 'E0B030' $x 46 2 5 } }
    $S['mgun'] = New-Sprite { Add-Box '202020' 12 52 40 5; Add-Box '383838' 12 52 40 1; Add-Box '202020' 48 50 10 3; Add-Box '4A3018' 8 52 8 8; Add-Box '202020' 28 57 4 6; Add-Box '202020' 36 57 3 4 }
    $S['chaingun'] = New-Sprite { Add-Box '282828' 14 48 26 12; Add-Box '484848' 14 48 26 2; foreach ($y in 49, 53, 57) { Add-Box '181818' 40 $y 18 2; Add-Box '606060' 40 $y 18 1 }; Add-Box '4A3018' 8 50 7 9; Add-Box 'E0B030' 18 56 8 5 }
    foreach ($k in @('key_gold', 'E8C020', '9A7A08'), @('key_silver', 'D0D8E0', '707880')) {
        $S[$k[0]] = New-Sprite { Add-Oval $k[1] 20 48 12 12; Add-Box $k[2] 24 52 4 4; Add-Box $k[1] 30 52 18 4; Add-Box $k[1] 40 56 3 5; Add-Box $k[1] 45 56 3 4 }
    }
    $S['coins'] = New-Sprite { foreach ($c in @(22, 56), @(32, 57), @(27, 52), @(36, 53), @(30, 48)) { Add-Oval 'C09010' $c[0] $c[1] 10 5; Add-Oval 'F0D040' $c[0] ($c[1] - 1) 10 4 } }
    $S['goblet'] = New-Sprite { Add-Oval 'C09010' 24 58 16 5; Add-Box 'E0B828' 30 48 4 11; Add-Poly 'F0D040' @(22, 34, 42, 34, 38, 48, 26, 48); Add-Oval 'FFF0A0' 22 32 20 5; Add-Box 'D02040' 30 39 4 4 }
    $S['chest'] = New-Sprite { Add-Box '6A3A14' 16 44 32 18; Add-Box '8A5220' 16 44 32 7; Add-Box 'E0B828' 16 50 32 2; Add-Box 'E0B828' 20 44 2 18; Add-Box 'E0B828' 42 44 2 18; Add-Box 'F0D040' 30 49 4 6; Add-Oval 'F0D040' 22 40 6 5; Add-Oval 'F0D040' 30 39 6 5; Add-Oval '40C0F0' 37 40 5 5 }
    $S['crown'] = New-Sprite { Add-Poly 'F0D040' @(18, 60, 18, 42, 25, 52, 32, 40, 39, 52, 46, 42, 46, 60); Add-Box 'C09010' 18 56 28 5; Add-Oval 'D02040' 30 56 4 4; Add-Oval '40C0F0' 21 57 3 3; Add-Oval '40C0F0' 40 57 3 3; Add-Oval 'D02040' 30 37 4 4 }
    $S['oneup'] = New-Sprite { Add-Oval '2060E0' 18 34 28 28; Add-Oval '50A0FF' 22 37 12 10; Add-Oval 'FFFFFF' 25 39 5 4; Add-Emblem 24 44 }

    $S['pipeline'] = New-Sprite { Add-Box '4A3018' 6 52 8 8; Add-Box '203040' 12 52 44 5; Add-Box '40E0FF' 14 53 40 1; foreach ($x in 22, 32, 42) { Add-Box '80F0FF' $x 50 2 9 } }
    $S['forcegun'] = New-Sprite { Add-Box '2A2A30' 10 47 34 13; Add-Box '44444C' 10 47 34 2; Add-Oval '101418' 36 44 18 18; Add-Oval '40FF60' 40 48 10 10; Add-Oval 'C0FFC8' 43 51 4 4; Add-Box '30C050' 14 52 18 2 }
    $S['charge'] = New-Sprite { Add-Box '808890' 28 45 8 3; Add-Box '2A2A30' 25 48 14 14; Add-Box '40FF60' 27 50 10 10; Add-Box 'C0FFC8' 29 52 2 6 }
    $S['sudo'] = New-Sprite { Add-Oval 'C09010' 18 28 28 28; Add-Oval 'F0D040' 20 30 24 24; Add-Oval '8A6A08' 23 33 18 18; Add-Box 'FFFFFF' 28 36 2 12; Add-Box 'FFFFFF' 34 36 2 12; Add-Box 'FFFFFF' 25 39 14 2; Add-Box 'FFFFFF' 25 44 14 2 }
    $S['rocket'] = New-Sprite { Add-Oval 'C03008' 22 22 20 20; Add-Oval 'FF7010' 24 24 16 16; Add-Oval 'FFD040' 27 27 10 10; Add-Oval 'FFFFFF' 30 30 4 4 }
    $S['rocket.boom1'] = New-Sprite { Add-Oval 'FF7010' 18 18 28 28; Add-Oval 'FFD040' 23 23 18 18; Add-Oval 'FFFFFF' 28 28 8 8 }
    $S['rocket.boom2'] = New-Sprite { Add-Oval 'C03008' 8 8 48 48; Add-Oval 'FF7010' 14 14 36 36; Add-Oval 'FFD040' 22 22 20 20; foreach ($d in @(6, 10), @(52, 14), @(10, 50), @(50, 48)) { Add-Box '402010' $d[0] $d[1] 3 3 } }
    $S['rocket.boom3'] = New-Sprite { Add-Oval '5A5A5A' 6 6 52 52; Add-Oval '7A7A7A' 14 12 30 30; Add-Oval 'C03008' 24 26 16 16; foreach ($d in @(2, 6), @(58, 10), @(4, 56), @(56, 54), @(30, 0)) { Add-Box '402010' $d[0] $d[1] 3 3 } }

    $S['bed'] = New-Sprite { Add-Box '5A3414' 8 44 4 18; Add-Box '5A3414' 52 50 4 12; Add-Box '7A4A20' 8 50 48 6; Add-Box '9AA6B8' 12 46 40 6; Add-Box 'E8E8E0' 12 43 12 5; Add-Box '6A7A9A' 26 46 26 5 }
    $S['console'] = New-Sprite { Add-Box '3A4450' 14 30 36 32; Add-Box '56626F' 14 30 36 2; Add-Poly '4A5561' @(14, 30, 50, 30, 46, 20, 18, 20); Add-Box '0A2A1A' 20 22 24 7; Add-Box '30E070' 22 24 14 1; Add-Box '30E070' 22 26 9 1; foreach ($l in @(18, 36, 'E03030'), @(24, 36, '30E070'), @(30, 36, 'E0C020'), @(36, 36, '20C0E0'), @(42, 36, '30E070')) { Add-Box $l[2] $l[0] $l[1] 3 3 }; Add-Box '242B33' 18 44 28 14 }
    $S['stalagmite'] = New-Sprite { Add-Poly '5A6A52' @(18, 63, 46, 63, 36, 30, 32, 8, 27, 32); Add-Poly '7A8A6A' @(27, 60, 32, 12, 33, 60); Add-Poly '4E5E4A' @(8, 63, 24, 63, 17, 40); Add-Poly '4E5E4A' @(40, 63, 56, 63, 49, 44); Add-Oval '3E6A32' 22 54 8 4; Add-Oval '3E6A32' 38 57 9 4 }

    $S['lamp_ceiling'] = New-Sprite { Add-Box '303030' 31 0 2 8; Add-Poly '2A8A3A' @(24, 14, 40, 14, 36, 8, 28, 8); Add-Oval 'FFFFC0' 27 13 10 5 }
    $S['chandelier'] = New-Sprite { Add-Box 'C09010' 31 0 2 10; Add-Box 'E0B828' 18 10 28 3; foreach ($x in 18, 25, 37, 44) { Add-Box 'F0F0E0' $x 5 2 5; Add-Oval 'FFE060' ($x - 1) 1 4 5 }; Add-Poly 'C09010' @(26, 13, 38, 13, 32, 19) }
    $S['lamp_floor'] = New-Sprite { Add-Oval '404040' 25 58 14 5; Add-Box '505050' 31 22 2 38; Add-Poly 'E0D8A0' @(24, 22, 40, 22, 36, 10, 28, 10); Add-Oval 'FFFFD0' 28 20 8 4 }
    $S['table'] = New-Sprite { Add-Box '5A3414' 16 44 4 18; Add-Box '5A3414' 44 44 4 18; Add-Box '8A5A28' 12 40 40 5; Add-Box '6A421C' 12 45 40 2; Add-Box '7A4A20' 4 48 8 14; Add-Box '7A4A20' 4 38 2 12; Add-Box '7A4A20' 52 48 8 14; Add-Box '7A4A20' 58 38 2 12 }
    $S['barrel'] = New-Sprite { Add-Oval '3A6A3A' 20 56 24 7; Add-Box '3A6A3A' 20 34 24 26; Add-Oval '4A8A4A' 20 31 24 7; Add-Oval '2A4A2A' 23 32 18 4; Add-Box '2A4A2A' 20 40 24 2; Add-Box '2A4A2A' 20 52 24 2; Add-Box '5A9A5A' 23 35 2 24 }
    $S['plant'] = New-Sprite { Add-Poly '9A5A2A' @(24, 50, 40, 50, 37, 62, 27, 62); Add-Box '7A4420' 23 48 18 3; foreach ($l in @(32, 48, 18, 26, 24, 22), @(32, 48, 46, 26, 40, 22), @(32, 48, 28, 16, 34, 14), @(32, 48, 14, 38, 18, 32), @(32, 48, 50, 38, 46, 32)) { Add-Poly '2A8A3A' $l }; Add-Poly '3AAA4A' @(32, 48, 30, 22, 35, 22) }
    $S['armor'] = New-Sprite { Add-Box '707880' 25 58 6 4; Add-Box '707880' 33 58 6 4; Add-Box '8A929A' 26 40 5 18; Add-Box '8A929A' 33 40 5 18; Add-Box '9AA2AA' 23 20 18 21; Add-Box 'B8C0C8' 25 22 4 16; Add-Box '8A929A' 19 21 4 16; Add-Box '8A929A' 41 21 4 16; Add-Oval '9AA2AA' 26 7 12 14; Add-Box '202020' 28 13 8 2; Add-Box 'C03030' 31 2 2 6; Add-Box '606870' 46 8 2 54; Add-Poly 'B8C0C8' @(44, 8, 50, 8, 47, 1) }
    $S['column'] = New-Sprite { Add-Box '8A8A8A' 22 0 20 4; Add-Box '9A9A9A' 25 4 14 56; Add-Box 'B4B4B4' 27 4 3 56; Add-Box '7A7A7A' 36 4 3 56; Add-Box '8A8A8A' 22 58 20 6 }
    $S['flag'] = New-Sprite { Add-Oval '404040' 27 59 10 4; Add-Box '9A7A3A' 31 4 2 56; Add-Oval 'E0B828' 30 1 4 4; Add-Poly '2C54C4' @(33, 6, 56, 9, 56, 28, 33, 30); Add-Emblem 36 12 }
    $S['crates'] = New-Sprite { foreach ($c in @(10, 40, 22), @(33, 40, 22), @(21, 18, 22)) { Add-Box '9A6A30' $c[0] $c[1] $c[2] $c[2]; Add-Box '6A4418' $c[0] $c[1] $c[2] 2; Add-Box '6A4418' $c[0] ($c[1] + $c[2] - 2) $c[2] 2; Add-Box '6A4418' $c[0] $c[1] 2 $c[2]; Add-Box '6A4418' ($c[0] + $c[2] - 2) $c[1] 2 $c[2]; Add-Poly '7A5020' @(($c[0] + 2), ($c[1] + 2), ($c[0] + 5), ($c[1] + 2), ($c[0] + $c[2] - 2), ($c[1] + $c[2] - 2), ($c[0] + $c[2] - 5), ($c[1] + $c[2] - 2)) } }
    $S['vat'] = New-Sprite { Add-Box '50585F' 18 56 28 6; Add-Box '30C050' 20 14 24 42; Add-Box '60F080' 22 16 4 38; Add-Box '50585F' 18 10 28 5; Add-Oval 'A0FFB0' 30 24 4 4; Add-Oval 'A0FFB0' 35 38 3 3; Add-Oval 'A0FFB0' 27 46 3 3; Add-Oval '4A6A40' 28 30 9 14 }
    $S['bones'] = New-Sprite { Add-Oval 'E0E0D0' 22 52 9 8; Add-Box '101010' 24 55 2 2; Add-Box '101010' 27 55 2 2; Add-Box 'E0E0D0' 32 57 18 2; Add-Box 'E0E0D0' 34 53 2 9; Add-Box 'E0E0D0' 40 54 2 8; Add-Box 'E0E0D0' 46 55 2 6 }
    $S['puddle'] = New-Sprite { Add-Oval '3A5A8A' 14 56 36 7; Add-Oval '5A7AAA' 20 57 16 3 }
}

# ---- the player's weapons (drawn bottom-centre, scaled to the full view height) -----------------
function Add-WeaponArt([string]$Key, [int]$Frame) {
    $dy = (0, -2, -5, -3, -1)[$Frame]
    $flash = ($Frame -eq 2) -or ($Key -eq 'chaingun' -and $Frame -eq 3)
    switch ($Key) {
        'knife' {
            $t = (0, 4, 12, 8, 3)[$Frame]
            Add-Poly 'D8DCE0' @((36 - $t), (30 - $t), (40 - $t), (28 - $t), (42), (50), (36), (52))
            Add-Poly 'F8F8F8' @((36 - $t), (30 - $t), (38 - $t), (29 - $t), (39), (51), (36), (52))
            Add-Box '3A2A1A' 34 (50 - [int]($t / 3)) 10 5
            Add-Poly 'E0A878' @(32, 64, 46, 64, 46, (53 - [int]($t / 3)), 33, (54 - [int]($t / 3)))
        }
        'pistol' {
            if ($flash) { Add-Oval 'FF9020' 23 (20 + $dy) 18 18; Add-Oval 'FFE060' 26 (23 + $dy) 12 12; Add-Oval 'FFFFFF' 29 (26 + $dy) 6 6 }
            Add-Box '303438' 28 (36 + $dy) 8 16; Add-Box '50565C' 28 (36 + $dy) 2 16; Add-Box '181818' 30 (34 + $dy) 4 3
            Add-Box '202020' 27 (50 + $dy) 10 4
            Add-Poly 'E0A878' @(24, 64, 40, 64, 40, (52 + $dy), 25, (53 + $dy)); Add-Box 'C89060' 26 (56 + $dy) 12 1
        }
        'mgun' {
            if ($flash) { Add-Oval 'FF9020' 21 (12 + $dy) 22 22; Add-Oval 'FFE060' 25 (16 + $dy) 14 14; Add-Oval 'FFFFFF' 29 (20 + $dy) 6 6 }
            Add-Box '202428' 30 (24 + $dy) 4 14; Add-Box '3A4046' 26 (36 + $dy) 12 20; Add-Box '5A626A' 26 (36 + $dy) 2 20
            Add-Box '181818' 29 (30 + $dy) 6 3; Add-Box '4A3018' 24 (54 + $dy) 16 10
            Add-Poly 'E0A878' @(38, 64, 50, 64, 46, (52 + $dy), 38, (50 + $dy))
        }
        'pipeline' {
            if ($flash) { Add-Oval '2090C0' 18 (2 + $dy) 28 28; Add-Oval '80F0FF' 23 (7 + $dy) 18 18; Add-Oval 'FFFFFF' 28 (12 + $dy) 8 8 }
            Add-Box '203040' 29 (18 + $dy) 6 30; Add-Box '35506A' 29 (18 + $dy) 2 30
            foreach ($ry in 22, 30, 38) { Add-Box $(if ($flash) { 'FFFFFF' } else { '40E0FF' }) 26 ($ry + $dy) 12 2 }
            Add-Box '2A3A4A' 23 (46 + $dy) 18 18; Add-Box '40E0FF' 26 (50 + $dy) 12 2; Add-Box '182430' 27 (54 + $dy) 10 6
            Add-Poly 'E0A878' @(10, 64, 24, 64, 24, (54 + $dy), 14, (56 + $dy)); Add-Poly 'E0A878' @(40, 64, 54, 64, 50, (56 + $dy), 40, (54 + $dy))
        }
        'forcegun' {
            if ($flash) { Add-Oval '20A040' 6 (0 + $dy) 52 44; Add-Oval 'A0FFB0' 14 (6 + $dy) 36 32; Add-Oval 'FFFFFF' 24 (14 + $dy) 16 16 }
            Add-Box '50585F' 14 (38 + $dy) 5 20; Add-Box '50585F' 45 (38 + $dy) 5 20
            Add-Box '2A2A30' 19 (34 + $dy) 26 28; Add-Box '44444C' 19 (34 + $dy) 3 28
            Add-Oval '101418' 20 (24 + $dy) 24 16
            Add-Oval $(if ($Frame -eq 1) { 'C0FFC8' } else { '40FF60' }) 25 (27 + $dy) 14 10
            Add-Box '30C050' 23 (46 + $dy) 18 2; Add-Box '30C050' 23 (51 + $dy) 18 2
            Add-Poly 'E0A878' @(6, 64, 20, 64, 20, (56 + $dy), 10, (58 + $dy)); Add-Poly 'E0A878' @(44, 64, 58, 64, 54, (58 + $dy), 44, (56 + $dy))
        }
        'chaingun' {
            if ($flash) { Add-Oval 'FF9020' 17 (10 + $dy) 30 26; Add-Oval 'FFE060' 22 (14 + $dy) 20 18; Add-Oval 'FFFFFF' 28 (19 + $dy) 8 8 }
            $spin = if ($Frame % 2) { 1 } else { 0 }
            foreach ($bx in 22, 28, 34, 40) { Add-Box '181C20' ($bx + $spin) (22 + $dy) 3 20; Add-Box '50585F' ($bx + $spin) (22 + $dy) 1 20 }
            Add-Box '30363C' 19 (28 + $dy) 27 4
            Add-Box '3A4046' 18 (40 + $dy) 28 18; Add-Box '5A626A' 18 (40 + $dy) 28 2; Add-Box '23282D' 22 (46 + $dy) 20 6
            Add-Box '282C30' 14 (56 + $dy) 36 10
            Add-Poly 'E0A878' @(8, 64, 20, 64, 20, (54 + $dy), 12, (56 + $dy)); Add-Poly 'E0A878' @(44, 64, 56, 64, 52, (56 + $dy), 44, (54 + $dy))
        }
    }
}

function Add-WeaponSprites {
    foreach ($w in $script:Weapons) {
        $frames = [object[]]::new(5)
        # drawn on the 64x64 grid, then shrunk towards the bottom centre so the gun does not fill the screen
        for ($f = 0; $f -lt 5; $f++) { $frames[$f] = New-Sprite { Set-Pivot 32 64 0 0.62 0.62; Add-WeaponArt $w.Key $f; Reset-Pivot } }
        $script:Spr["weapon.$($w.Key)"] = $frames
    }
}

function Initialize-Sprites {
    $script:Spr = @{}
    foreach ($k in 'guard', 'officer', 'elite', 'mutant', 'pilot') { Add-SoldierSprites $k }
    Add-BossSprites
    Add-UberSprites
    Add-DogSprites
    Add-ThingSprites
    Add-WeaponSprites
}

# ---- the super boss: a walking war machine -------------------------------------------------------
function Add-MechArt([string]$Pose) {
    if ($Pose -eq 'dead') {
        Add-Poly '2E3640' @(4, 63, 10, 48, 28, 40, 50, 44, 60, 63); Add-Poly '4A5668' @(12, 60, 18, 48, 30, 44, 40, 58)
        Add-Box '0E1A2A' 30 46 12 8; Add-Box '3C6A9A' 31 47 4 2
        Add-Box '262C34' 46 50 14 5; Add-Oval '0A0A0A' 57 51 3 3
        foreach ($f in @(16, 40, 'FF7010'), @(36, 34, 'FFD040'), @(44, 40, 'FF7010')) { Add-Poly $f[2] @($f[0], ($f[1] + 8), ($f[0] + 3), $f[1], ($f[0] + 6), ($f[1] + 8)) }
        Add-Oval '5A5A5A' 20 22 10 10; Add-Oval '6A6A6A' 26 12 12 12; Add-Oval '7A7A7A' 22 2 9 9
        return
    }
    $l = 0; $r = 0; $bob = 0
    switch ($Pose) { 'w1' { $l = -3 } 'w2' { $bob = -1 } 'w3' { $r = -3 } 'w4' { $bob = -1 } }
    if ($Pose -eq 'die2') { Set-Pivot 32 62 14 }
    if ($Pose -eq 'die3') { Set-Pivot 32 62 30 1 0.85 }

    # legs
    Add-Box '3A4450' 16 (38 + $bob) 10 (21 + $l - $bob); Add-Box '262C34' 12 (58 + $l) 17 6
    Add-Box '3A4450' 38 (38 + $bob) 10 (21 + $r - $bob); Add-Box '262C34' 35 (58 + $r) 17 6
    Add-Oval '59657A' 15 (46 + $l) 12 8; Add-Oval '59657A' 37 (46 + $r) 12 8
    Add-Box '2E3640' 17 (35 + $bob) 30 6
    # hull
    Add-Poly '4A5668' @(12, (11 + $bob), 52, (11 + $bob), 57, (36 + $bob), 7, (36 + $bob))
    Add-Box '5E6C82' 14 (12 + $bob) 36 2
    for ($x = 10; $x -lt 54; $x += 8) { Add-Poly 'E0C020' @($x, (36 + $bob), ($x + 4), (36 + $bob), ($x + 6), (32 + $bob), ($x + 2), (32 + $bob)) }
    Add-Box '0E1A2A' 23 (15 + $bob) 18 13; Add-Box '3C6A9A' 24 (16 + $bob) 16 3
    Add-Oval 'E0A878' 29 (19 + $bob) 6 7; Add-Box '101010' 30 (21 + $bob) 1 1; Add-Box '101010' 33 (21 + $bob) 1 1; Add-Box '2A2A2A' 29 (18 + $bob) 6 2
    # rocket pods on the shoulders
    foreach ($px in 1, 50) {
        Add-Box '30363E' $px (6 + $bob) 13 15; Add-Box '4A525C' $px (6 + $bob) 13 2
        foreach ($t in @(2, 3), @(7, 3), @(2, 9), @(7, 9)) { Add-Oval '0A0A0A' ($px + $t[0]) (6 + $bob + $t[1]) 4 4 }
        if ($Pose -eq 'rocket') { Add-Oval 'FF7010' ($px - 2) (2 + $bob) 17 17; Add-Oval 'FFE060' ($px + 2) (6 + $bob) 9 9 }
    }
    # arm cannons
    foreach ($ax in 1, 55) {
        Add-Box '262C34' $ax (23 + $bob) 8 22; Add-Box '3A424C' $ax (23 + $bob) 2 22
        Add-Oval '0A0A0A' $ax (42 + $bob) 4 4; Add-Oval '0A0A0A' ($ax + 4) (42 + $bob) 4 4
        if ($Pose -eq 'fire') { Add-Oval 'FF9020' ($ax - 4) (37 + $bob) 16 16; Add-Oval 'FFFFD0' ($ax) (41 + $bob) 8 8 }
    }
    Reset-Pivot

    # burning down
    $fires = switch ($Pose) { 'die1' { , @(@(18, 14, 14), @(40, 26, 12)) } 'die2' { , @(@(10, 10, 20), @(36, 20, 18), @(24, 36, 14)) } 'die3' { , @(@(4, 8, 30), @(28, 4, 30), @(16, 28, 32)) } default { , @() } }
    foreach ($f in $fires) {
        Add-Oval 'C03008' $f[0] $f[1] $f[2] $f[2]
        Add-Oval 'FF7010' ($f[0] + 2) ($f[1] + 2) ($f[2] - 4) ($f[2] - 4)
        Add-Oval 'FFD040' ($f[0] + [int]($f[2] / 4)) ($f[1] + [int]($f[2] / 4)) ([int]($f[2] / 2)) ([int]($f[2] / 2))
    }
}

function Add-UberSprites {
    foreach ($pose in 's', 'w1', 'w2', 'w3', 'w4', 'aim', 'fire', 'rocket', 'die1', 'die2', 'die3', 'dead') {
        $ps = if ($pose -in 's', 'aim') { 'stand' } else { $pose }
        $script:Spr["uber.$pose"] = New-Sprite { Add-MechArt $ps }
    }
}
