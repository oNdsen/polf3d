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

# ---- a 3x5 pixel font, for everything in this world that has PowerShell written on it ---------------
$script:TinyFont = @{}
foreach ($glyph in @(
        'A010101111101101', 'B110101110101110', 'C011100100100011', 'D110101101101110', 'E111100110100111', 'F111100110100100',
        'G011100101101011', 'H101101111101101', 'I111010010010111', 'J001001001101010', 'K101101110101101', 'L100100100100111',
        'M101111111101101', 'N110101101101101', 'O010101101101010', 'P110101110100100', 'Q010101101111011', 'R110101110101101',
        'S011100010001110', 'T111010010010010', 'U101101101101111', 'V101101101101010', 'W101101111111101', 'X101101010101101',
        'Y101101010010010', 'Z111001010100111', '0111101101101111', '1010110010010111', '2110001010100111', '3110001010001110',
        '4101101111001001', '5111100110001110', '6011100111101111', '7111001010010010', '8111101111101111', '9111101111001110',
        '>100010001010100', '<001010100010001', '_000000000000111', '-000000111000000', '|010010010010010', '.000000000000010',
        ':000010000010000', '$011110010011110', '(001010010010001', ')100010010010100', '=000111000111000', '+000010111010000',
        '/001001010100100', '\100100010001001', '{011010110010011', '}110010011010110', '[011010010010011', ']110010010010110',
        '*000101010101000', '?110001010000010', '!010010010000010', ',000000000010100', '%101001010100101', '#101111101111101', '@010101111100011')) {
    $script:TinyFont[$glyph[0]] = $glyph.Substring(1)
}

# Writes $Text (upper case) with its top left corner at $X,$Y. One character is 3x5 pixels plus a pixel of spacing.
function Add-TinyText([string]$C, [int]$X, [int]$Y, [string]$Text, [int]$Size = 1) {
    foreach ($ch in $Text.ToUpper().ToCharArray()) {
        $bits = $script:TinyFont[$ch]
        if ($bits) { for ($i = 0; $i -lt 15; $i++) { if ($bits[$i] -eq '1') { Add-Box $C ($X + ($i % 3) * $Size) ($Y + [int][Math]::Floor($i / 3) * $Size) $Size $Size } } }
        $X += 4 * $Size
    }
}

# A wall-mounted PowerShell console: grey frame, title bar, the blue screen and three lines of text.
function Add-ConsoleArt([string[]]$Lines, [string]$Screen = '012456') {
    Add-Box '15181E' 7 11 50 40; Add-Box '3A404C' 8 12 48 38
    Add-Box 'E4E6EA' 9 13 46 6; Add-Box '2C54C4' 10 14 5 4; Add-TinyText 'FFFFFF' 11 14 '>'; Add-TinyText '30343C' 17 14 'PWSH.EXE'
    Add-Box $Screen 9 19 46 30
    $y = 22
    foreach ($line in $Lines) {
        $color = if ($line -like 'PS>*') { 'F9F1A5' } else { 'EEEDF0' }
        Add-TinyText $color 11 $y $line
        $y += 8
    }
    Add-Box '6A7484' 28 51 8 3; Add-Box '20242C' 24 54 16 2                       # bracket
}

function Add-BigPrompt([string]$C, [int]$X, [int]$Y, [int]$T) {               # a large ">_", $T = stroke width
    Add-Poly $C @($X, $Y, ($X + $T), $Y, ($X + 12 + $T), ($Y + 12), ($X + $T), ($Y + 24), $X, ($Y + 24), ($X + 12), ($Y + 12))
    Add-Box $C ($X + 18) ($Y + 20) 16 $T
}

function Add-WallArt([string]$Name) {
    switch ($Name) {
        { $_ -like '*_console' } {
            $base = $Name -replace '_console'
            Add-WallBase $base
            $text = switch ($base) {
                'stone' { 'PS> WHOAMI', 'INTRUDER', 'PS> _' }
                'blue'  { 'PS> GET-KEY', 'DENIED', 'PS> _' }
                'wood'  { 'PS> GET-ALE', 'EMPTY :(', 'PS> _' }
                'brick' { 'PS> GCI -R', '42 GUARDS', 'PS> _' }
                'steel' { 'PS> GET-JOB', 'RUNNING', 'PS> _' }
                'moss'  { 'PS> HELP', '...', '_' }
                default { 'PS> IWR LAB', '200 OK', 'PS> _' }
            }
            Add-ConsoleArt $text
            if ($base -eq 'moss') {                                  # long dead, cracked and overgrown
                Add-Poly '0C0C0C' @(30, 19, 33, 19, 40, 34, 36, 49, 34, 49, 37, 34)
                foreach ($vx in 12, 47) { $x = $vx; for ($y = 0; $y -lt 46; $y += 3) { $x += $script:Rng.Next(3) - 1; Add-Box '2E6A28' $x $y 2 3; if ($y % 9 -eq 0) { Add-Oval '4A9A3A' ($x - 3) $y 5 3 } } }
            }
        }
        { $_ -like '*_error' } {
            Add-WallBase ($Name -replace '_error')
            Add-ConsoleArt @() '0C0C0C'
            Add-TinyText 'F14C4C' 11 22 'ACCESS'; Add-TinyText 'F14C4C' 11 29 'DENIED'; Add-TinyText 'F14C4C' 11 36 '+ LINE:1'; Add-TinyText 'F14C4C' 11 43 '+ CHAR:1'
        }
        { $_ -like '*_poster' } {
            Add-WallBase ($Name -replace '_poster')
            Add-Box '20202A' 13 9 40 48; Add-Box 'ECE4CC' 14 10 38 46
            Add-Box '2C54C4' 14 10 38 17; Add-Emblem 24 12
            Add-TinyText '2C54C4' 17 30 'GET-HELP' ; Add-Box '9A927A' 17 37 32 1
            Add-TinyText '50483A' 16 40 'VERB-NOUN'; Add-TinyText '50483A' 16 47 'ALWAYS.'
        }
        { $_ -like '*_neon' } {
            Add-WallBase ($Name -replace '_neon')
            Add-Box '0A0E16' 8 12 48 40; Add-Box '141A26' 10 14 44 36
            Add-BigPrompt '2040E0FF' 13 18 8; Add-BigPrompt '5040E0FF' 14 19 6                 # the glow
            Add-BigPrompt '40E0FF' 15 20 4; Add-BigPrompt 'D8FFFF' 16 21 2
        }
        { $_ -like '*_graffiti' } {
            Add-WallBase ($Name -replace '_graffiti')
            Add-BigPrompt '60FFFFFF' 12 14 7; Add-BigPrompt 'F0F0F0' 13 15 5
            foreach ($drip in @(17, 39, 9), @(40, 40, 11)) { Add-Box 'F0F0F0' $drip[0] $drip[1] 2 $drip[2] }
            Add-TinyText '40E0FF' 9 55 'PS WAS HERE'
        }
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
        { $_ -like '*_window' } { Add-WallBase ($Name -replace '_window'); Add-WindowArt }
        { $_ -like '*_cracked' } {
            Add-WallBase ($Name -replace '_cracked')
            # a web of cracks radiating from a weak spot - the hint that explosives will do the rest
            $cx = 30; $cy = 34
            foreach ($ray in @(-26, -20), @(-8, -30), @(14, -26), @(28, -6), @(22, 20), @(2, 28), @(-18, 22), @(-28, 4)) {
                $x = $cx; $y = $cy
                for ($i = 1; $i -le 6; $i++) {
                    $nx = $cx + $ray[0] * $i / 6 + $script:Rng.Next(-2, 3); $ny = $cy + $ray[1] * $i / 6 + $script:Rng.Next(-2, 3)
                    Add-Poly '0C0C0C' @([int]$x, [int]$y, ([int]$x + 2), [int]$y, ([int]$nx + 1), [int]$ny, [int]$nx, [int]$ny)
                    $x = $nx; $y = $ny
                }
            }
            Add-Oval '0C0C0C' 26 30 9 8; Add-Oval '2A2A2A' 28 32 4 4
        }
        { $_ -in 'secret_switch_off', 'secret_switch_on' } {
            Add-WallBase steel
            Add-Box '1A1430' 20 14 24 36; Add-Box '0C0A1C' 22 16 20 32; Add-Box '3A3460' 30 20 4 24
            if ($Name -eq 'secret_switch_off') { Add-Box '4060F0' 27 18 10 8; Add-Box 'A0B8FF' 28 19 3 2 } else { Add-Box 'F0D040' 27 38 10 8; Add-Box 'FFF8C0' 28 39 3 2 }
            Add-Emblem 23 26
        }
        { $_ -in 'lever_off', 'lever_on' } {
            Add-WallBase stone
            Add-Box '2A2A2A' 22 16 20 32; Add-Box '484848' 24 18 16 28; Add-Box '181818' 30 22 4 20
            if ($Name -eq 'lever_off') { Add-Box '8A8A8A' 31 20 2 12; Add-Oval 'D02020' 28 16 8 8 } else { Add-Box '8A8A8A' 31 32 2 12; Add-Oval '20C040' 28 40 8 8 }
        }
        'door_remote' {
            Add-Box '4A3A5A' 0 0 64 64; Add-Box '6A5A7A' 0 0 64 2; Add-Box '2A1A3A' 0 62 64 2
            for ($y = 8; $y -lt 60; $y += 12) { Add-Box '3A2A4A' 4 $y 56 8; Add-Box '5A4A6A' 4 $y 56 1 }
            Add-Oval 'E040E0' 27 27 10 10; Add-Oval '2A1A3A' 30 30 4 4
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

# A window: frame, a hole punched through to transparency, and bars across it.
function Add-WindowArt {
    Add-Box '2A2A2A' 12 14 40 34; Add-Box '5A5A5A' 12 14 40 2; Add-Box '5A5A5A' 12 14 2 34
    $g = $script:GFX
    $g.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceCopy
    $g.FillRectangle([System.Drawing.Brushes]::Transparent, 15, 17, 34, 28)
    $g.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceOver
    foreach ($x in 23, 31, 39) { Add-Box '3A3A3A' $x 17 2 28; Add-Box '6A6A6A' $x 17 1 28 }
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
        if ($script:WallNames[$i] -like '*_window') { Add-WindowArt }      # ... but the hole must stay a hole
        $script:WallDark[$i] = Get-Pixels $bmp
        $script:GFX.Dispose(); $bmp.Dispose()
    }
}

# ---- flats: floor and ceiling textures ------------------------------------------------------------
function Add-FlatArt([string]$Name) {
    switch ($Name) {
        'flat_stone' { Add-BlockPattern '3A3A3A' @('6A6A6A', '626262', '707070', '5C5C5C') '787878' 32 32; Add-Speckle @('505050', '7A7A7A') 220 }
        'flat_wood' {
            Add-Box '6A4420' 0 0 64 64
            for ($y = 0; $y -lt 64; $y += 8) { Add-Box '4A2E14' 0 $y 64 1; Add-Box '7C5228' 0 ($y + 1) 64 1; Add-Box '4A2E14' (($y * 5) % 64) $y 1 8 }
            for ($i = 0; $i -lt 50; $i++) { Add-Box '5A3A1A' $script:Rng.Next(64) $script:Rng.Next(64) (3 + $script:Rng.Next(10)) 1 }
        }
        'flat_moss' {
            Add-Box '3A3428' 0 0 64 64; Add-Speckle @('2E2A20', '4A4232', '333026') 500
            for ($i = 0; $i -lt 22; $i++) { Add-Oval $(('2E5A28', '3A6A30', '264A22')[$script:Rng.Next(3)]) $script:Rng.Next(60) $script:Rng.Next(60) (4 + $script:Rng.Next(9)) (3 + $script:Rng.Next(7)) }
        }
        'flat_tech' {
            Add-Box '2E363F' 0 0 64 64
            foreach ($py in 0, 32) { foreach ($px in 0, 32) {
                Add-Box '3E4852' ($px + 1) ($py + 1) 30 30; Add-Box '4C5864' ($px + 1) ($py + 1) 30 1; Add-Box '4C5864' ($px + 1) ($py + 1) 1 30
                for ($g = 5; $g -lt 30; $g += 5) { Add-Box '343D46' ($px + 3) ($py + $g) 26 1 }
                foreach ($r in @(3, 3), @(27, 3), @(3, 27), @(27, 27)) { Add-Box '1E242A' ($px + $r[0]) ($py + $r[1]) 2 2 }
            } }
        }
        'flat_carpet' {
            Add-Box '6A1420' 0 0 64 64; Add-Speckle @('5A101A', '7A1A28') 300
            Add-Box 'C09010' 0 0 64 2; Add-Box 'C09010' 0 62 64 2; Add-Box 'C09010' 0 0 2 64; Add-Box 'C09010' 62 0 2 64
            Add-Poly '8A2030' @(32, 12, 52, 32, 32, 52, 12, 32); Add-Poly '6A1420' @(32, 20, 44, 32, 32, 44, 20, 32); Add-Box 'C09010' 30 30 4 4
        }
        'ceil_plain' {
            Add-Box '34343A' 0 0 64 64
            foreach ($py in 0, 32) { foreach ($px in 0, 32) { Add-Box '3E3E46' ($px + 1) ($py + 1) 30 30; Add-Box '2A2A30' ($px + 1) ($py + 30) 30 1; Add-Box '2A2A30' ($px + 30) ($py + 1) 1 30 } }
            Add-Speckle @('30303A', '444450') 120
        }
        'ceil_rock' {
            Add-Box '24221E' 0 0 64 64; Add-Speckle @('1A1916', '302E28', '2A2824') 600
            for ($i = 0; $i -lt 16; $i++) { Add-Oval $(('1C1B18', '2E2C26')[$script:Rng.Next(2)]) $script:Rng.Next(58) $script:Rng.Next(58) (5 + $script:Rng.Next(10)) (4 + $script:Rng.Next(8)) }
        }
        'ceil_tech' {
            Add-Box '20262E' 0 0 64 64
            for ($y = 0; $y -lt 64; $y += 16) { Add-Box '2C343E' 0 ($y + 1) 64 14; Add-Box '161A20' 0 $y 64 1 }
            Add-Box 'C8E8FF' 8 6 48 3; Add-Box 'E8F8FF' 10 7 44 1; Add-Box 'C8E8FF' 8 38 48 3; Add-Box 'E8F8FF' 10 39 44 1
        }
    }
}

function Initialize-Flats {
    $script:Flats = @{}
    foreach ($name in 'flat_stone', 'flat_wood', 'flat_moss', 'flat_tech', 'flat_carpet', 'ceil_plain', 'ceil_rock', 'ceil_tech') {
        $bmp = New-Canvas
        Add-FlatArt $name
        $script:Flats[$name] = Get-Pixels $bmp
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
    sniper  = @{ Skin = 'D8A070'; Hair = '2A2A1A'; Uniform = '4A5A32'; UniformDark = '36432A'; Pants = '3E4A2A'; PantsDark = '2C361E'; Boots = '1A1A12'; Belt = '20281A'; Hat = '3A4628'; HatDark = '262E1A'; HatStyle = 'cap'; Gun = 'rifle' }
    shield  = @{ Skin = 'E0A878'; Hair = '101010'; Uniform = '3A3E46'; UniformDark = '282C32'; Pants = '30343A'; PantsDark = '202428'; Boots = '101010'; Belt = '181818'; Hat = '2A2E36'; HatDark = '181C22'; HatStyle = 'helmet'; Gun = 'pistol' }
    # the players of a network game, by slot: orange, green, purple, yellow - all under a white helmet
    peer0   = @{ Skin = 'E0A878'; Hair = '6A3A1A'; Uniform = 'E07818'; UniformDark = 'B05A10'; Pants = '2A4A6A'; PantsDark = '1C3450'; Boots = '181818'; Belt = '202020'; Hat = 'E8E8E8'; HatDark = 'B0B0B0'; HatStyle = 'helmet'; Gun = 'mg' }
    peer1   = @{ Skin = 'E0A878'; Hair = '2A1A0E'; Uniform = '2E9A4A'; UniformDark = '1E7034'; Pants = '2A4A6A'; PantsDark = '1C3450'; Boots = '181818'; Belt = '202020'; Hat = 'E8E8E8'; HatDark = 'B0B0B0'; HatStyle = 'helmet'; Gun = 'mg' }
    peer2   = @{ Skin = 'C88A60'; Hair = '101010'; Uniform = '8A3AB8'; UniformDark = '642A88'; Pants = '2A4A6A'; PantsDark = '1C3450'; Boots = '181818'; Belt = '202020'; Hat = 'E8E8E8'; HatDark = 'B0B0B0'; HatStyle = 'helmet'; Gun = 'mg' }
    peer3   = @{ Skin = 'E0A878'; Hair = 'C0A050'; Uniform = 'D8C020'; UniformDark = 'A89418'; Pants = '2A4A6A'; PantsDark = '1C3450'; Boots = '181818'; Belt = '202020'; Hat = 'E8E8E8'; HatDark = 'B0B0B0'; HatStyle = 'helmet'; Gun = 'mg' }
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
            'rifle'  { Add-Box '181818' 30 (32 + $bob) 28 2; Add-Box '4A3018' 26 (31 + $bob) 8 5; Add-Box '181818' 38 (29 + $bob) 6 3 }
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
        if ($p.Gun -eq 'rifle') { Add-Box '101010' 29 23 6 11; Add-Oval '303030' 28 18 8 8; Add-Oval 'FF2020' 30 20 4 4; Add-Box 'FFA0A0' 31 21 1 1 }
        elseif ($p.Gun -eq 'mg') { Add-Box '101010' 29 25 6 9; Add-Box '404040' 31 27 2 2 } else { Add-Box '101010' 30 26 4 7; Add-Box '404040' 31 27 2 2 }
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
                'rifle'  { Add-Box '181818' 43 (14 + $bob) 2 30; Add-Box '4A3018' 42 (34 + $bob) 4 10 }
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
    $S['console'] = New-Sprite { Add-Box '3A4450' 14 30 36 32; Add-Box '56626F' 14 30 36 2; Add-Poly '4A5561' @(14, 30, 50, 30, 46, 20, 18, 20); Add-Box '012456' 20 22 24 7; Add-TinyText 'F9F1A5' 22 23 'PS>_'; foreach ($l in @(18, 36, 'E03030'), @(24, 36, '30E070'), @(30, 36, 'E0C020'), @(36, 36, '20C0E0'), @(42, 36, '30E070')) { Add-Box $l[2] $l[0] $l[1] 3 3 }; Add-Box '242B33' 18 44 28 14 }
    $S['stalagmite'] = New-Sprite { Add-Poly '5A6A52' @(18, 63, 46, 63, 36, 30, 32, 8, 27, 32); Add-Poly '7A8A6A' @(27, 60, 32, 12, 33, 60); Add-Poly '4E5E4A' @(8, 63, 24, 63, 17, 40); Add-Poly '4E5E4A' @(40, 63, 56, 63, 49, 44); Add-Oval '3E6A32' 22 54 8 4; Add-Oval '3E6A32' 38 57 9 4 }

    $S['lamp_ceiling'] = New-Sprite { Add-Box '303030' 31 0 2 8; Add-Poly '2A8A3A' @(24, 14, 40, 14, 36, 8, 28, 8); Add-Oval 'FFFFC0' 27 13 10 5 }
    $S['chandelier'] = New-Sprite { Add-Box 'C09010' 31 0 2 10; Add-Box 'E0B828' 18 10 28 3; foreach ($x in 18, 25, 37, 44) { Add-Box 'F0F0E0' $x 5 2 5; Add-Oval 'FFE060' ($x - 1) 1 4 5 }; Add-Poly 'C09010' @(26, 13, 38, 13, 32, 19) }
    $S['lamp_floor'] = New-Sprite { Add-Oval '404040' 25 58 14 5; Add-Box '505050' 31 22 2 38; Add-Poly 'E0D8A0' @(24, 22, 40, 22, 36, 10, 28, 10); Add-Oval 'FFFFD0' 28 20 8 4 }
    $S['rack'] = New-Sprite {
        Add-Oval '1C2028' 16 59 32 5
        Add-Box '14181E' 18 4 28 58; Add-Box '2A303A' 19 5 26 56; Add-Box '3A424E' 19 5 26 1
        foreach ($uy in 8, 15, 22, 40, 47, 54) {
            Add-Box '181C24' 21 $uy 22 5; Add-Box '0C0E12' 22 ($uy + 1) 9 3
            foreach ($led in @(33, '30E070'), @(36, '30E070'), @(39, 'E0C020')) { Add-Box $led[1] $led[0] ($uy + 2) 2 1 }
        }
        Add-Box '0C0E12' 21 29 22 10; Add-Box '012456' 22 30 20 8; Add-TinyText 'F9F1A5' 24 31 'PS>_'
        Add-Box 'E03030' 39 9 2 1
    }
    $S['crt'] = New-Sprite {
        Add-Oval '1C2028' 8 59 48 5
        Add-Box '5A3414' 10 44 4 18; Add-Box '5A3414' 50 44 4 18; Add-Box '8A5A28' 6 40 52 5; Add-Box '6A421C' 6 45 52 2      # the desk
        Add-Box 'B8B4A4' 18 14 28 24; Add-Box 'D8D4C4' 18 14 28 2; Add-Box '8A8678' 18 36 28 2; Add-Box '8A8678' 26 38 12 2          # the monitor
        Add-Box '0A0E16' 20 17 24 17; Add-Box '012456' 21 18 22 15
        Add-TinyText 'F9F1A5' 23 20 'PS>'; Add-TinyText 'EEEDF0' 23 27 'GCI'; Add-Box 'EEEDF0' 36 27 3 5
        Add-Box 'C8C4B4' 14 38 24 3; Add-Box '9A9688' 15 39 22 1; Add-Oval 'C8C4B4' 42 37 6 4                                     # keyboard and mouse
    }
    $S['table'] = New-Sprite { Add-Box '5A3414' 16 44 4 18; Add-Box '5A3414' 44 44 4 18; Add-Box '8A5A28' 12 40 40 5; Add-Box '6A421C' 12 45 40 2; Add-Box '7A4A20' 4 48 8 14; Add-Box '7A4A20' 4 38 2 12; Add-Box '7A4A20' 52 48 8 14; Add-Box '7A4A20' 58 38 2 12 }
    $S['barrel'] = New-Sprite { Add-Oval '3A6A3A' 20 56 24 7; Add-Box '3A6A3A' 20 34 24 26; Add-Oval '4A8A4A' 20 31 24 7; Add-Oval '2A4A2A' 23 32 18 4; Add-Box '2A4A2A' 20 40 24 2; Add-Box '2A4A2A' 20 52 24 2; Add-Box '5A9A5A' 23 35 2 24 }
    # hit feedback: blood at chest height, sparks where a bullet meets a wall
    $S['fx.blood1'] = New-Sprite { Add-Oval 'C01010' 28 26 8 8; Add-Box 'E02020' 30 28 3 3 }
    $S['fx.blood2'] = New-Sprite { Add-Oval 'B01010' 25 24 14 12; foreach ($d in @(20, 22), @(42, 25), @(24, 40), @(40, 38), @(32, 18)) { Add-Box 'C01010' $d[0] $d[1] 3 3 } }
    $S['fx.blood3'] = New-Sprite { foreach ($d in @(16, 26), @(46, 30), @(22, 46), @(42, 46), @(32, 14), @(28, 34), @(36, 40), @(30, 50)) { Add-Box '900C0C' $d[0] $d[1] 2 3 } }
    $S['fx.puff1'] = New-Sprite { Add-Oval 'FFE080' 29 29 6 6; Add-Box 'FFFFFF' 31 31 2 2 }
    $S['fx.puff2'] = New-Sprite { Add-Oval 'A0A0A0' 26 26 12 12; foreach ($d in @(22, 24), @(40, 26), @(30, 20), @(36, 40)) { Add-Box 'FFD040' $d[0] $d[1] 2 2 } }
    $S['fx.puff3'] = New-Sprite { Add-Oval '707070' 24 22 16 14; Add-Oval '8A8A8A' 28 24 8 7 }
    $S['fx.flame1'] = New-Sprite { Add-Oval 'FF5010' 22 26 20 22; Add-Oval 'FF9020' 26 30 12 14; Add-Oval 'FFE060' 29 34 6 8 }
    $S['fx.flame2'] = New-Sprite { Add-Oval 'E04010' 16 18 32 32; Add-Oval 'FF9020' 22 24 20 22; Add-Oval 'FFE060' 28 32 8 10 }
    $S['fx.flame3'] = New-Sprite { Add-Oval '803010' 18 12 28 30; Add-Oval 'C05010' 24 18 16 18; Add-Oval '5A5A5A' 26 8 10 10 }
    $S['tknife'] = New-Sprite { Add-Poly 'E8ECF0' @(30, 24, 34, 24, 33, 36, 31, 36); Add-Box '3A2A1A' 30 36 4 6 }
    $S['launcher'] = New-Sprite { Add-Box '3A4A32' 10 50 40 8; Add-Box '55683F' 10 50 40 2; Add-Oval '101410' 46 49 8 10; Add-Box 'E0C020' 22 50 2 8; Add-Box '20281A' 26 58 5 5 }
    $S['rockets'] = New-Sprite { foreach ($x in 22, 30, 38) { Add-Box '8A929A' $x 46 5 14; Add-Poly 'C03030' @($x, 46, ($x + 5), 46, ($x + 2), 40); Add-Box 'E0C020' $x 56 5 2 } }
    $S['flamer'] = New-Sprite { Add-Box '8A2A1A' 12 48 22 12; Add-Box 'B03A24' 12 48 22 2; Add-Box '404850' 34 52 20 4; Add-Box 'FF9020' 54 51 3 6; Add-Box 'E0C020' 12 54 22 2 }
    $S['tknives'] = New-Sprite { foreach ($k in @(22, -2), @(30, 0), @(38, -2)) { Add-Poly 'E8ECF0' @($k[0], (44 + $k[1]), ($k[0] + 4), (44 + $k[1]), ($k[0] + 3), (56 + $k[1]), ($k[0] + 1), (56 + $k[1])); Add-Box '3A2A1A' $k[0] (56 + $k[1]) 4 6 } }
    $S['telepad'] = New-Sprite { Add-Oval '1A3A6A' 10 53 44 10; Add-Oval '40E0FF' 14 54 36 8; Add-Oval '0A1A3A' 18 55 28 6; Add-Oval 'A0F0FF' 26 56 12 4; foreach ($x in 20, 31, 42) { Add-Box '80F0FF' $x 38 1 14; Add-Box 'FFFFFF' $x 44 1 3 } }
    # traps
    $S['spikes.0'] = New-Sprite { Add-Oval '3A3A3A' 12 55 40 8; foreach ($h in @(18, 57), @(26, 59), @(34, 57), @(42, 59), @(30, 56)) { Add-Oval '101010' $h[0] $h[1] 4 2 } }
    $S['spikes.1'] = New-Sprite { Add-Oval '3A3A3A' 12 55 40 8; foreach ($h in @(18, 57, 30), @(26, 59, 24), @(34, 57, 28), @(42, 59, 32), @(30, 56, 20)) { Add-Poly 'C8CCD0' @($h[0], $h[1], ($h[0] + 4), $h[1], ($h[0] + 2), $h[2]); Add-Poly 'F0F4F8' @($h[0], $h[1], ($h[0] + 1), $h[1], ($h[0] + 2), $h[2]) }; Add-Box 'B01010' 27 30 2 5 }
    foreach ($c in @(0, 12), @(1, 38), @(2, 64)) {
        $len = $c[1]
        $S["crusher.$($c[0])"] = New-Sprite { Add-Box '50585F' 27 0 10 ([Math]::Max(1, $len - 12)); Add-Box '7A848C' 27 0 3 ([Math]::Max(1, $len - 12)); Add-Box '3A4248' 14 ($len - 12) 36 12; Add-Box '6A747C' 14 ($len - 12) 36 2; for ($x = 14; $x -lt 50; $x += 8) { Add-Poly 'E0C020' @($x, ($len - 1), ($x + 4), ($len - 1), ($x + 8), ($len - 6), ($x + 4), ($len - 6)) } }
    }
    $S['barrel_red'] = New-Sprite { Add-Oval '8A1C1C' 20 56 24 7; Add-Box '8A1C1C' 20 34 24 26; Add-Oval 'B02828' 20 31 24 7; Add-Oval '5A1010' 23 32 18 4; Add-Box '5A1010' 20 40 24 2; Add-Box '5A1010' 20 52 24 2; Add-Box 'D04040' 23 35 2 24; Add-Poly 'F0D040' @(32, 42, 38, 51, 26, 51); Add-Box '101010' 31 45 2 3; Add-Box '101010' 31 49 2 1 }
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
        'launcher' {
            if ($flash) { Add-Oval 'FF7010' 14 (4 + $dy) 36 30; Add-Oval 'FFD040' 21 (10 + $dy) 22 18; Add-Oval 'FFFFFF' 27 (14 + $dy) 10 10 }
            Add-Box '3A4A32' 22 (26 + $dy) 20 34; Add-Box '55683F' 22 (26 + $dy) 3 34; Add-Oval '101410' 23 (20 + $dy) 18 12; Add-Oval '2A3424' 26 (22 + $dy) 12 8
            Add-Box 'E0C020' 22 (44 + $dy) 20 2; Add-Box '20281A' 28 (52 + $dy) 8 10
            Add-Poly 'E0A878' @(8, 64, 22, 64, 22, (54 + $dy), 12, (56 + $dy)); Add-Poly 'E0A878' @(42, 64, 56, 64, 52, (56 + $dy), 42, (54 + $dy))
        }
        'flamer' {
            if ($Frame -in 2, 3) { Add-Oval 'FF5010' 16 (0 + $dy) 32 30; Add-Oval 'FF9020' 20 (6 + $dy) 24 22; Add-Oval 'FFE060' 26 (12 + $dy) 12 12 }
            Add-Box '404850' 29 (24 + $dy) 6 22; Add-Box '606A74' 29 (24 + $dy) 2 22; Add-Box 'FF9020' 30 (21 + $dy) 4 3
            Add-Box '8A2A1A' 22 (44 + $dy) 20 18; Add-Box 'B03A24' 22 (44 + $dy) 3 18; Add-Box 'E0C020' 22 (52 + $dy) 20 2
            Add-Poly 'E0A878' @(8, 64, 22, 64, 22, (56 + $dy), 12, (58 + $dy)); Add-Poly 'E0A878' @(42, 64, 56, 64, 52, (58 + $dy), 42, (56 + $dy))
        }
        'tknife' {
            $t = (0, -6, 14, 6, 0)[$Frame]
            if ($Frame -ne 2 -and $Frame -ne 3) { Add-Poly 'D8DCE0' @(30, (30 - $t), 34, (30 - $t), 33, (48 - $t), 31, (48 - $t)); Add-Box '3A2A1A' 30 (48 - $t) 4 7 }
            Add-Poly 'E0A878' @(26, 64, 40, 64, 40, (54 - [int]($t / 2)), 27, (55 - [int]($t / 2)))
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

# -WhatIf: a see-through figure (every other pixel of the guard, in one colour) and a way mark.
function Add-WhatIfSprites {
    $guard = $script:Spr['guard.s'][0]
    foreach ($mark in @('ghost', 0xFF40E0FF), @('threat', 0xFFFF5040)) {
        $px = [int[]]::new(4096)
        for ($i = 0; $i -lt 4096; $i++) { if ($guard[$i] -ne 0 -and (($i % 64) + [int][Math]::Floor($i / 64)) % 2 -eq 0) { $px[$i] = [int]$mark[1] } }
        $script:Spr["whatif.$($mark[0])"] = $px
    }
    $script:Spr['whatif.dot'] = New-Sprite { Add-Poly '40E0FF' @(32, 50, 36, 54, 32, 58, 28, 54); Add-Poly 'D8FFFF' @(32, 52, 34, 54, 32, 56, 30, 54) }
}

function Initialize-Sprites {
    $script:Spr = @{}
    foreach ($k in 'guard', 'officer', 'elite', 'mutant', 'pilot', 'sniper', 'shield') { Add-SoldierSprites $k }
    foreach ($k in $script:ModKinds) { Add-SoldierSprites $k }     # newcomers from mods: a palette is all they need
    Add-ShieldOverlay
    Add-BossSprites
    Add-UberSprites
    Add-DogSprites
    Add-ThingSprites
    Add-BotSprites              # after the things: the bot dies in the rocket's explosion frames
    Add-SecuritySprites
    Add-WhatIfSprites
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

# ---- shield bearer: the soldier sprites get a riot shield painted over them -------------------------
function Add-ShieldArt([string]$View, [string]$Pose) {
    switch ($View) {
        'f' {
            if ($Pose -in 'aim', 'fire') { Add-Box '50585F' 8 20 9 36; Add-Box '7A848C' 8 20 2 36; return }      # lowered to the side
            Add-Poly '50585F' @(18, 18, 46, 18, 46, 54, 40, 60, 24, 60, 18, 54)
            Add-Poly '6A747C' @(20, 20, 44, 20, 44, 53, 39, 58, 25, 58, 20, 53)
            Add-Box '101418' 25 24 14 4; Add-Box '9AA4AC' 20 20 24 1; Add-Box 'E0C020' 30 40 4 8
        }
        's' { Add-Box '50585F' 38 18 4 42; Add-Box '7A848C' 41 18 1 42 }
        'b' { Add-Box '50585F' 17 22 3 34; Add-Box '50585F' 44 22 3 34 }
    }
}

function Add-ShieldOverlay {
    $p = $script:Palettes.shield
    foreach ($pose in 's', 'w1', 'w2', 'w3', 'w4') {
        $ps = if ($pose -eq 's') { 'stand' } else { $pose }
        $f = New-Sprite { Add-SoldierArt $p 'f' $ps; Add-ShieldArt 'f' $ps }
        $b = New-Sprite { Add-SoldierArt $p 'b' $ps; Add-ShieldArt 'b' $ps }
        $r = New-Sprite { Add-SoldierArt $p 's' $ps; Add-ShieldArt 's' $ps }
        $l = New-Sprite { Add-SoldierArt $p 's' $ps; Add-ShieldArt 's' $ps } -FlipX
        $script:Spr["shield.$pose"] = @($f, $l, $b, $r)
    }
    foreach ($pose in 'aim', 'fire') { $script:Spr["shield.$pose"] = New-Sprite { Add-SoldierArt $p 'f' $pose; Add-ShieldArt 'f' $pose } }
}

# ---- kamikaze bot: a rolling ball with a bad attitude -------------------------------------------------
function Add-BotArt([string]$Pose) {
    $blink = $Pose -in 'w2', 'w4'
    $roll = switch ($Pose) { 'w1' { 0 } 'w2' { 2 } 'w3' { 4 } 'w4' { 6 } default { 0 } }
    Add-Oval '101010' 22 56 20 6
    Add-Oval '3A4450' 20 36 24 24; Add-Oval '56626F' 23 38 12 10
    Add-Box '242B33' 20 47 24 3
    for ($i = 0; $i -lt 3; $i++) { Add-Box '101418' (22 + (($roll + $i * 8) % 22)) 47 2 3 }
    Add-Oval '101418' 27 40 10 8; Add-Oval $(if ($blink) { 'FF2020' } else { '801010' }) 29 41 6 6
    if ($blink) { Add-Oval 'FFA0A0' 31 42 2 2 }
    Add-Box '8A929A' 31 30 2 7; Add-Oval $(if ($blink) { 'FFD040' } else { 'C03030' }) 30 27 4 4
}

# Cameras hang from the ceiling, sentry guns stand on a tripod. Both blink while they are awake.
function Add-CameraArt([bool]$Blink, [bool]$Broken) {
    Add-Box '50585F' 30 0 4 8
    if ($Broken) { Add-Poly '2A3038' @(24, 8, 40, 12, 38, 22, 22, 18); Add-Oval '101418' 25 11 7 7; Add-Box 'FFD040' 36 20 1 3; Add-Box 'FFD040' 33 22 1 2; return }
    Add-Box '2A3038' 21 8 22 11; Add-Box '3A424C' 21 8 22 2
    Add-Oval '101418' 27 9 10 10; Add-Oval '3060A0' 30 12 4 4; Add-Box 'A0C8FF' 31 12 1 1
    Add-Box $(if ($Blink) { 'FF2020' } else { '601010' }) 39 11 2 2
}

function Add-TurretArt([string]$Pose) {
    Add-Oval '101010' 20 57 24 6
    Add-Poly '20262C' @(23, 60, 30, 44, 34, 44, 41, 60, 38, 60, 32, 48, 26, 60)
    Add-Box '20262C' 31 44 2 16
    Add-Box '3A4450' 21 31 22 15; Add-Box '56626F' 23 33 18 3; Add-Box '242B33' 21 44 22 2
    Add-Oval '101418' 26 35 12 12; Add-Oval '000000' 29 38 6 6
    Add-Box $(if ($Pose -in 'aim', 'fire', 'w2', 'w4') { 'FF2020' } else { '601010' }) 39 32 3 3
    if ($Pose -eq 'fire') { Add-Oval 'FFB030' 23 32 18 18; Add-Oval 'FFE880' 26 35 12 12; Add-Oval 'FFFFFF' 29 38 6 6 }
}

# Start-Job's drone: a small quadcopter under the ceiling, with a claw for whatever it finds.
function Add-DroneArt([bool]$Flip) {
    Add-Box '20262C' 20 13 24 2                                   # the arms
    foreach ($x in 17, 41) { Add-Box '8A929A' ($x + $(if ($Flip) { 1 } else { 0 })) 11 $(if ($Flip) { 4 } else { 6 }) 1; Add-Box '50585F' ($x + 2) 12 2 2 }
    Add-Box '2C54C4' 27 12 10 7; Add-Box '4070E0' 28 13 8 2
    Add-Box '101418' 30 16 4 2; Add-Box $(if ($Flip) { '40E0FF' } else { '2080A0' }) 31 16 2 1
    Add-Box '50585F' 29 19 1 4; Add-Box '50585F' 34 19 1 4; Add-Box '50585F' 30 22 1 1; Add-Box '50585F' 33 22 1 1
}

function Add-SecuritySprites {
    $script:Spr['drone.a'] = New-Sprite { Add-DroneArt $false }
    $script:Spr['drone.b'] = New-Sprite { Add-DroneArt $true }
    foreach ($pose in 's', 'w1', 'w2', 'w3', 'w4') {
        $script:Spr["camera.$pose"] = New-Sprite { Add-CameraArt ($pose -in 'w2', 'w4') $false }
        $script:Spr["turret.$pose"] = New-Sprite { Add-TurretArt $pose }
    }
    foreach ($pose in 'aim', 'fire') { $script:Spr["turret.$pose"] = New-Sprite { Add-TurretArt $pose } }
    foreach ($i in 1, 2, 3) { $script:Spr["turret.die$i"] = $script:Spr["rocket.boom$i"]; $script:Spr["camera.die$i"] = $script:Spr["fx.puff$i"] }
    $script:Spr['camera.dead'] = New-Sprite { Add-CameraArt $false $true }
    $script:Spr['turret.dead'] = New-Sprite { Add-Oval '101010' 18 56 28 6; Add-Poly '20262C' @(20, 60, 27, 52, 40, 50, 45, 60); Add-Box '3A4450' 26 48 12 5; Add-Box '101418' 36 46 9 3 }
}

function Add-BotSprites {
    foreach ($pose in 's', 'w1', 'w2', 'w3', 'w4') { $script:Spr["bot.$pose"] = New-Sprite { Add-BotArt $pose } }
    foreach ($i in 1, 2, 3) { $script:Spr["bot.die$i"] = $script:Spr["rocket.boom$i"] }
    $script:Spr['bot.dead'] = New-Sprite { Add-Oval '101010' 18 56 28 6; Add-Poly '2E3640' @(22, 60, 26, 50, 34, 47, 42, 52, 44, 60); Add-Box '56626F' 28 51 5 3; Add-Oval '5A5A5A' 28 38 8 8; Add-Oval '6A6A6A' 32 30 7 7 }
}

# ---------------------------------------------------------------------------------------------
# The face in the status bar: the admin on call - headset, stubble, hoodie with a >_ on the zipper.
# Painted at 30x34 pixels and enlarged without smoothing, like every other sprite.
#   Tier  0 fresh .. 4 nearly dead (a new layer of damage every 20 health), 5 dead
#   Expr  idle | pain | grin | rage | sneak | sudo | god          Look  -1 left, 0, 1 right
# ---------------------------------------------------------------------------------------------
$script:FaceCache = @{}

function Get-FaceBitmap([int]$Tier, [string]$Expr, [int]$Look) {
    $key = "$Tier|$Expr|$Look"
    if (-not $script:FaceCache[$key]) { $script:FaceCache[$key] = New-FaceBitmap $Tier $Expr $Look }
    $script:FaceCache[$key]
}

function New-FaceBitmap([int]$Tier, [string]$Expr, [int]$Look) {
    $bmp = [System.Drawing.Bitmap]::new(30, 34)
    $gfx = [System.Drawing.Graphics]::FromImage($bmp)
    $box = { param([string]$C, [int]$X, [int]$Y, [int]$W = 1, [int]$H = 1) $gfx.FillRectangle((Get-Brush $C), $X, $Y, $W, $H) }
    $dead = $Tier -ge 5
    $skin, $shade, $dark = if ($dead) { 'A9B4BC', '8E9AA4', '74808A' } elseif ($Tier -ge 4) { 'D8A07C', 'B8825E', '9A6A4A' } else { 'E4AC7C', 'C48C60', 'A47048' }

    # neck and hoodie
    & $box $shade 11 28 8 4
    & $box '2A3344' 3 31 24 3; & $box '3A465C' 5 30 6 2; & $box '3A465C' 19 30 6 2; & $box '1C2230' 13 31 4 3
    & $box '40E0FF' 14 32; & $box '40E0FF' 15 33                     # the >_ on the zipper tag

    # head, ears, stubble
    & $box $skin 6 6 18 20; & $box $skin 7 26 16 2; & $box $skin 9 28 12 1; & $box $skin 11 29 8 1
    & $box $shade 6 8 2 16; & $box $shade 22 8 2 16; & $box $shade 7 24 2 3; & $box $shade 21 24 2 3
    & $box $skin 4 13 2 6; & $box $shade 4 15 1 3; & $box $skin 24 13 2 6; & $box $shade 25 15 1 3
    foreach ($st in @(8, 23), @(10, 25), @(12, 27), @(14, 27), @(16, 27), @(18, 27), @(20, 25), @(22, 23), @(9, 26), @(21, 26), @(11, 24), @(19, 24)) { & $box $dark $st[0] $st[1] }

    # hair: short, a bit of a mess
    & $box '3A2616' 6 3 18 5; & $box '3A2616' 5 5 2 6; & $box '3A2616' 23 5 2 6; & $box '3A2616' 8 2 12 1
    & $box '4E3422' 9 3 4 1; & $box '4E3422' 16 4 5 1; & $box '3A2616' 11 1 2 1; & $box '3A2616' 17 1 3 1
    & $box '3A2616' 7 8 3 1; & $box '3A2616' 20 8 3 1
    # headset: band, ear cups, microphone
    & $box '39435A' 5 0 20 2; & $box '5A6884' 7 0 16 1
    & $box '39435A' 2 11 3 9; & $box '5A6884' 3 12 1 7; & $box '40E0FF' 2 14 1 2
    & $box '39435A' 25 11 3 9; & $box '5A6884' 26 12 1 7
    & $box '39435A' 3 20 1 3; & $box '39435A' 4 22 1 2; & $box '39435A' 5 24 2 1; & $box '262E40' 7 25 3 2; & $box '7080A0' 8 25

    # brows
    $brow = switch ($Expr) { 'pain' { 10 } 'grin' { 10 } 'rage' { 12 } default { 11 } }
    $worn = $Tier -ge 4 -and $Expr -eq 'idle'
    if ($worn) { $brow = 10 }
    & $box '2A1A0E' 8 $brow 5 1; & $box '2A1A0E' 17 $brow 5 1
    if ($Expr -eq 'rage') { & $box '2A1A0E' 11 13 2 1; & $box '2A1A0E' 17 13 2 1 }              # pulled together
    if ($Expr -eq 'pain' -or $worn) { & $box '2A1A0E' 8 11 2 1; & $box '2A1A0E' 20 11 2 1 }     # worried: outer ends down

    # eyes
    if ($dead) {
        foreach ($ex in 8, 17) { foreach ($o in @(0, 13), @(4, 13), @(1, 14), @(3, 14), @(2, 15), @(1, 16), @(3, 16), @(0, 17), @(4, 17)) { & $box '20242C' ($ex + $o[0]) $o[1] } }
    }
    elseif ($Expr -eq 'sudo') {
        & $box '0C0E14' 6 12 18 2; & $box '0C0E14' 7 14 7 3; & $box '0C0E14' 16 14 7 3                # deal-with-it shades
        & $box 'F0D040' 8 13 2 1; & $box 'F0D040' 17 13 2 1; & $box 'FFFFFF' 9 14; & $box 'FFFFFF' 18 14
    }
    elseif ($Expr -eq 'pain') {
        & $box '2A1A0E' 8 14 5 1; & $box '2A1A0E' 17 14 5 1; & $box $dark 9 15 3 1; & $box $dark 18 15 3 1    # squeezed shut
    }
    else {
        $open = if ($Expr -eq 'sneak') { 1 } elseif ($Tier -ge 4) { 2 } else { 3 }
        $top = 16 - $open
        $white = if ($Expr -eq 'god') { 'FFF4A0' } elseif ($Tier -ge 3) { 'F4E0DA' } else { 'FFFFFF' }
        $iris = if ($Expr -eq 'god') { 'FFB000' } elseif ($Expr -eq 'rage') { '7A1414' } else { '2A4A8A' }
        foreach ($ex in 8, 17) {
            if ($Tier -ge 4 -and $ex -eq 8) { & $box '6A3A6A' 8 13 5 3; & $box '4A2448' 8 15 5 1; & $box '2A1A0E' 9 14 3 1; continue }     # swollen shut
            & $box $white $ex $top 5 $open
            & $box $iris ($ex + 1 + $Look) $top 3 $open
            if ($Expr -ne 'god') { & $box '101828' ($ex + 2 + $Look) ($top + [int][Math]::Floor($open / 2)) }
            & $box $dark $ex ($top - 1) 5 1
            if ($Tier -ge 4) { & $box $shade $ex 16 5 1 }                                          # bags under the eyes
        }
        if ($Expr -eq 'god') { & $box 'FFE860' 8 0 14 1 }
    }

    # nose
    & $box $shade 14 15 2 5; & $box $dark 13 20 4 1; & $box $skin 14 19 2 1

    # mouth
    switch ($(if ($dead) { 'dead' } else { $Expr })) {
        'grin'  { & $box '5A2020' 10 22 10 4; & $box 'FFFFFF' 11 23 8 2; & $box 'D0D0D0' 13 23 1 2; & $box 'D0D0D0' 16 23 1 2 }
        'sudo'  { & $box '7A3030' 11 24 8 1; & $box '7A3030' 19 23; & $box '7A3030' 20 22 }       # smirk
        'pain'  { & $box '3A1010' 11 22 8 5; & $box 'FFFFFF' 12 22 6 1; & $box 'A03030' 13 25 4 2 }
        'rage'  { & $box '5A2020' 10 22 10 4; & $box 'FFFFFF' 11 23 8 2; foreach ($t in 12, 14, 16, 18) { & $box 'A0A0A0' $t 23 1 2 } }
        'sneak' { & $box '7A3030' 13 24 4 1 }
        'dead'  { & $box '3A2020' 11 23 8 2; & $box 'B05060' 14 24 3 3 }                           # tongue out
        default {
            if ($Tier -ge 4) { & $box '3A1010' 11 23 8 3; & $box 'FFFFFF' 12 23 6 1 }              # panting
            elseif ($Tier -ge 2) { & $box '7A3030' 11 24 8 1; & $box '7A3030' 10 25; & $box '7A3030' 19 25 }
            else { & $box '7A3030' 11 24 8 1 }
        }
    }

    # wounds: one more layer per tier
    $blood = 'B01010'; $clot = '7A0808'
    if ($Tier -ge 1) { & $box $blood 20 9 2 1; & $box $blood 21 10 1 2; & $box $clot 21 12 }                                         # a cut over the brow
    if ($Tier -ge 2) { & $box $blood 14 21 1 3; & $box $clot 14 24; & $box '8A5A8A' 17 17 4 1; & $box '7A4A7A' 18 18 3 1 }           # nose bleed, a bruise
    if ($Tier -ge 3) { & $box $blood 22 5 1 9; & $box $blood 23 9 1 8; & $box $clot 22 14 1 5; & $box $blood 18 25 2 1; & $box $blood 19 26 1 3; & $box $blood 8 7 3 1 }
    if ($Tier -ge 4) {
        & $box $blood 7 8 1 10; & $box $clot 8 12 1 9; & $box $blood 9 21 1 4; & $box $blood 12 27 2 2; & $box $clot 13 29 1 2; & $box $blood 16 21 1 2
        & $box '9AD8FF' 12 7 1 2; & $box '9AD8FF' 20 20 1 2; & $box '9AD8FF' 5 21 1 2                                                 # sweat
    }
    if ($dead) { & $box $clot 6 6 4 3; & $box $blood 6 9 2 12; & $box $clot 22 5 2 16; & $box $blood 10 27 3 3 }
    $gfx.Dispose()
    $bmp
}
