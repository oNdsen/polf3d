# POLF 3D - Copyright (c) 2026 oNdsen. Licensed under the MIT License, see LICENSE.

# Ending.ps1 - what happens after the last lift switch of the campaign: the epilogue. The story of how
# it ends scrolls over a night sky that turns into morning while the windows of Shellstein go dark one
# by one and a small figure walks away from the building, to a melody of its own (src/Music.ps1, "ending").
# Space or the down arrow hurries the text along, Enter or Esc jumps to the last card and then leaves.

# @(text, kind): title | head | text | code | dim | '' (an empty line)
$script:EndingLines = @(
    @('POLF 3D', 'title'), @('', ''), @('EPILOGUE', 'head'), @('', ''), @('', ''),
    @('The lift doors close on Ring 0.', 'text'),
    @('Behind them, for the first time since 1993,', 'text'),
    @('nothing is running.', 'text'), @('', ''),
    @('LEGACY.BAT never had an exit condition.', 'text'),
    @('You turned out to be one.', 'text'), @('', ''), @('', ''),
    @('Ten floors down, the building notices.', 'text'), @('', ''),
    @('In the Data Centre the cold aisles fall silent, fan by fan.', 'text'),
    @('In the Foundry the crushers stop half way, as if embarrassed.', 'text'),
    @('In the Archive a single floppy disk finally becomes', 'text'),
    @('what it always was: a backup nobody will ever restore.', 'text'), @('', ''),
    @('THE PRINTER prints one last page.', 'text'),
    @('It says PC LOAD LETTER.', 'text'),
    @('Then it, too, lets go.', 'text'), @('', ''), @('', ''),
    @('The guards lower their guns and look at their hands.', 'text'),
    @('For thirty seconds now nobody has told them what to do.', 'text'),
    @('One of them opens a window.', 'text'),
    @('It is the first change to production in thirty-three years,', 'text'),
    @('and nothing breaks.', 'text'), @('', ''), @('', ''),
    @('You walk out through the front door.', 'text'),
    @('Nobody asks for your badge. You never had one.', 'text'), @('', ''),
    @('Outside it is morning. It is a Monday, of course.', 'text'),
    @('Somewhere behind you a phone starts to ring:', 'text'),
    @('a user cannot print.', 'text'), @('', ''),
    @('You let it ring.', 'text'), @('', ''), @('', ''),
    @('PS Shellstein:\> Get-Process LEGACY*', 'code'),
    @('PS Shellstein:\>', 'code'),
    @('PS Shellstein:\> Get-EventLog -Newest 1 | Select-Object -ExpandProperty Message', 'code'),
    @('The system has shut down cleanly. For once.', 'dim'),
    @('PS Shellstein:\> Stop-Computer -ComputerName SHELLSTEIN -Force', 'code'),
    @('PS Shellstein:\> exit', 'code'), @('', ''), @('', ''),
    @('You have escaped from Shellstein.', 'head'), @('', ''), @('', ''), @('', ''),
    @('POLF 3D', 'head'),
    @('written in PowerShell - yes, really - by oNdsen', 'text'), @('', ''),
    @('every wall and every face painted,', 'dim'),
    @('every shot, every voice and every note composed', 'dim'),
    @('by code, when the game starts', 'dim'), @('', ''),
    @('no assets, animals or administrators were harmed', 'dim'), @('', ''), @('', ''),
    @('And remember what the last admin wrote:', 'text'),
    @('test your restores. Somebody should.', 'text')
)

$script:ENDING_PITCH = 11.0                    # distance between two lines, in 320x240 units
$script:ENDING_SPEED = 0.145                   # units per tic: a line takes about a second
$script:Ending = $null

function Start-Ending {
    $rng = [System.Random]::new(1993)
    $stars = foreach ($i in 1..70) { , @(($rng.NextDouble() * 320), ($rng.NextDouble() * 150), (0.4 + $rng.NextDouble() * 0.6), $rng.Next(100)) }
    # the windows of the tower: @(column, row, the moment - 0..1 - when the light goes out)
    $windows = foreach ($row in 0..10) { foreach ($col in 0..4) { if ($rng.Next(100) -lt 72) { , @($col, $row, (0.08 + $rng.NextDouble() * 0.72)) } } }
    $script:Ending = @{
        Scroll = 0.0; Total = 240.0 + $script:EndingLines.Count * $script:ENDING_PITCH - 96.0
        Done = $false; DoneTics = 0.0; Stars = @($stars); Windows = @($windows)
    }
    Set-Mode 'ending'
    $script:MusicWanted = $script:MUSIC_ENDING; Start-Music $script:MUSIC_ENDING
}

function Update-Ending([double]$Tics, [int[]]$Hits) {
    $e = $script:Ending; $vk = $script:VK
    $leave = $Hits -contains $vk.Enter -or $Hits -contains $vk.Esc
    if (-not $e.Done) {
        $hurry = $script:KeyDown[$vk.Space] -or $script:KeyDown[$vk.Down]
        $e.Scroll += $Tics * $script:ENDING_SPEED * $(if ($hurry) { 6.0 } else { 1.0 })
        if ($leave -and $script:ModeTics -gt 35) { $e.Scroll = $e.Total }
        if ($e.Scroll -ge $e.Total) { $e.Scroll = $e.Total; $e.Done = $true }
        return
    }
    $e.DoneTics += $Tics
    if ($leave -and $e.DoneTics -gt 50) { Set-Mode 'title' }
}

# "00RRGGBB" with an alpha in front, for Get-Brush
function Get-EndingColor([double]$Alpha, [string]$Rgb) { '{0:X2}{1}' -f [int][Math]::Max(0, [Math]::Min(255, $Alpha * 255)), $Rgb }

# Height of the hill's ridge at x (320x240 units).
function Get-EndingRidge([double]$X) { 196.0 - 14.0 * [Math]::Sin(($X + 40.0) / 320.0 * [Math]::PI) - 3.0 * [Math]::Sin($X / 23.0) }

function Show-Ending {
    $e = $script:Ending; $g = $script:BackG; $s = $script:Scale
    $t = [Math]::Max(0.0, [Math]::Min(1.0, $e.Scroll / $e.Total))                       # 0 = night ... 1 = morning
    $now = $script:Clock.Elapsed.TotalSeconds
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $full = [System.Drawing.RectangleF]::new(0, 0, [single](320 * $s), [single](240 * $s))

    # the sky: night, and the morning fading in over it
    $night = [System.Drawing.Drawing2D.LinearGradientBrush]::new($full, [System.Drawing.Color]::FromArgb(255, 4, 6, 20), [System.Drawing.Color]::FromArgb(255, 20, 28, 66), 90.0)
    $g.FillRectangle($night, $full); $night.Dispose()
    $dawn = [Math]::Max(0.0, ($t - 0.25) / 0.75)
    if ($dawn -gt 0) {
        $a = [int](235 * $dawn)
        $day = [System.Drawing.Drawing2D.LinearGradientBrush]::new($full, [System.Drawing.Color]::FromArgb($a, 36, 58, 120), [System.Drawing.Color]::FromArgb($a, 255, 150, 70), 90.0)
        $g.FillRectangle($day, $full); $day.Dispose()
    }
    foreach ($star in $e.Stars) {
        $twinkle = 0.65 + 0.35 * [Math]::Sin($now * 2.0 + $star[3])
        $alpha = $star[2] * $twinkle * (1.0 - $dawn * 1.15)
        if ($alpha -gt 0.02) { Write-HudBar (Get-EndingColor $alpha 'FFFFFF') $star[0] $star[1] 0.7 0.7 }
    }
    # the sun comes up behind the hill, on the side he is walking to
    if ($dawn -gt 0) {
        $sunY = 214.0 - 46.0 * $dawn
        foreach ($ring in @(34.0, 0.10), @(24.0, 0.16), @(16.0, 0.30), @(10.0, 1.0)) {
            $g.FillEllipse((Get-Brush (Get-EndingColor ($ring[1] * [Math]::Min(1.0, $dawn * 1.6)) 'FFE9A0')), [single]((62 - $ring[0]) * $s), [single](($sunY - $ring[0]) * $s), [single]($ring[0] * 2 * $s), [single]($ring[0] * 2 * $s))
        }
    }

    # the hill and Shellstein on top of it
    $ground = '05070C'
    $pts = [System.Collections.Generic.List[System.Drawing.PointF]]::new()
    for ($x = 0; $x -le 320; $x += 8) { $pts.Add([System.Drawing.PointF]::new([single]($x * $s), [single]((Get-EndingRidge $x) * $s))) }
    $pts.Add([System.Drawing.PointF]::new([single](320 * $s), [single](240 * $s))); $pts.Add([System.Drawing.PointF]::new(0, [single](240 * $s)))
    $g.FillPolygon((Get-Brush $ground), $pts.ToArray())
    $bx = 262.0; $by = 92.0; $bw = 44.0; $base = (Get-EndingRidge 284) + 6
    Write-HudBar $ground $bx $by $bw ($base - $by)                                       # the tower
    Write-HudBar $ground ($bx - 16) ($by + 46) 16 ($base - $by - 46); Write-HudBar $ground ($bx + $bw) ($by + 58) 14 ($base - $by - 58)      # the wings
    foreach ($m in 0..5) { Write-HudBar $ground ($bx + $m * 8) ($by - 4) 4 4 }            # battlements
    Write-HudBar $ground ($bx + 20) ($by - 22) 1.2 18                                    # the mast
    if ($t -lt 0.93 -and [int]($now * 1.4) % 2 -eq 0) { Write-HudBar 'FFFF3020' ($bx + 19.2) ($by - 24) 2.8 2.8 }      # its beacon blinks while anything is running
    foreach ($w in $e.Windows) {
        if ($t -ge $w[2]) { continue }
        $flicker = if ($w[2] - $t -lt 0.015 -and [int]($now * 14) % 2 -eq 0) { 0.2 } else { 0.8 }      # it flickers before it goes out
        Write-HudBar (Get-EndingColor $flicker 'FFD870') ($bx + 4 + $w[0] * 8) ($by + 6 + $w[1] * 8.5) 4 4.6
    }
    # somebody walks away from it
    $hx = 250.0 - 174.0 * $t; $hy = (Get-EndingRidge $hx) - 0.5
    $step = if ($e.Done) { 0 } else { [int]($now * 3.2) % 2 }
    Write-HudBar $ground ($hx - 1.2) ($hy - 9) 2.4 2.4                                   # head
    Write-HudBar $ground ($hx - 1.6) ($hy - 6.6) 3.2 4.2                                 # body
    Write-HudBar $ground ($hx - 1.6 + $step * 0.6) ($hy - 2.6) 1.2 3.0; Write-HudBar $ground ($hx + 0.4 - $step * 0.6) ($hy - 2.6) 1.2 3.0
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::None

    # the text: fades in at the bottom and out at the top
    $fade = 1.0
    if ($e.Done) { $fade = [Math]::Max(0.0, 1.0 - $e.DoneTics / 70.0) }
    if ($fade -gt 0) {
        for ($i = 0; $i -lt $script:EndingLines.Count; $i++) {
            $line = $script:EndingLines[$i]
            if (-not $line[0]) { continue }
            $y = 240.0 + $i * $script:ENDING_PITCH - $e.Scroll
            if ($y -lt -14 -or $y -gt 240) { continue }
            $alpha = $fade * [Math]::Min(1.0, [Math]::Min(($y + 4) / 40.0, (236 - $y) / 36.0))
            if ($alpha -le 0.02) { continue }
            $font, $rgb = switch ($line[1]) { 'title' { 'Big', 'F0D040' } 'head' { 'Mid', '8FD0FF' } 'code' { 'Small', '60FF80' } 'dim' { 'Small', 'C0C8D8' } default { 'Mid', 'FFFFFF' } }
            Write-HudText $line[0] $font (Get-EndingColor ($alpha * 0.8) '000000') 0.6 ($y + 0.6) 320 12      # a shadow keeps it readable over the sunrise
            Write-HudText $line[0] $font (Get-EndingColor $alpha $rgb) 0 $y 320 12
        }
    }
    if ($e.Done) {
        $in = [Math]::Max(0.0, [Math]::Min(1.0, ($e.DoneTics - 40) / 90.0))
        Write-HudText 'THE END' 'Huge' (Get-EndingColor ($in * 0.8) '000000') 1.2 41.2 320 40
        Write-HudText 'THE END' 'Huge' (Get-EndingColor $in 'FFFFFF') 0 40 320 40
        $p = $script:P
        $sum = "$($script:Difficulties[$script:Difficulty].Name)   -   $(Format-Time ($p.RunTics / $script:TICRATE))   -   score $($p.Score)   -   tests passed $(Get-AchievementCount)"
        Write-HudText $sum 'Small' (Get-EndingColor $in 'FFFFFF') 0 92 320 8
        if ($e.DoneTics -gt 50) { Write-HudText 'Enter = main menu' 'Small' (Get-EndingColor $in 'FFE860') 0 226 320 8 }
    }
    elseif ($script:ModeTics -lt 420) { Write-HudText 'Space = faster     Enter = skip' 'Small' (Get-EndingColor 0.5 'FFFFFF') 0 230 320 8 }
}

# The same for a terminal: the lines that are on the screen right now.
function Get-EndingScreen {
    $e = $script:Ending; $esc = [char]27; $reset = "$esc[0m"
    $lines = [System.Collections.Generic.List[string]]::new()
    if ($e.Done) {
        foreach ($n in 1..6) { $lines.Add('') }
        $lines.Add("$esc[97m" + (' ' * 46) + "T H E   E N D$reset"); $lines.Add('')
        $lines.Add((' ' * 20) + "$($script:Difficulties[$script:Difficulty].Name)   -   $(Format-Time ($script:P.RunTics / $script:TICRATE))   -   score $($script:P.Score)"); $lines.Add('')
        $lines.Add("$esc[38;2;255;232;96m" + (' ' * 44) + "Enter = main menu$reset")
        return $lines
    }
    $rows = 22; $shown = -1
    for ($row = 0; $row -lt $rows; $row++) {
        $i = [int][Math]::Floor(($e.Scroll - 240.0 + $row * 240.0 / $rows) / $script:ENDING_PITCH)
        if ($i -eq $shown) { $lines.Add(''); continue }
        $shown = $i
        if ($i -lt 0 -or $i -ge $script:EndingLines.Count -or -not $script:EndingLines[$i][0]) { $lines.Add(''); continue }
        $line = $script:EndingLines[$i]
        $colour = switch ($line[1]) { 'title' { "$esc[38;2;240;208;64m" } 'head' { "$esc[38;2;143;208;255m" } 'code' { "$esc[38;2;96;255;128m" } 'dim' { "$esc[38;2;160;168;184m" } default { "$esc[97m" } }
        $lines.Add($colour + (' ' * [Math]::Max(0, [int]((104 - $line[0].Length) / 2))) + $line[0] + $reset)
    }
    $lines
}
