# POLF 3D - Copyright (c) 2026 oNdsen. Licensed under the MIT License, see LICENSE.

# SelfTest.ps1 - headless smoke test (Start-Polf3D.ps1 -SelfTest): renders views and asset
# sheets to PNG files, measures the frame time, plays a few hundred scripted frames and does
# a save/load round trip. No window needed, so it also works over a remote session.

function Save-BackBuffer([string]$Path) { $script:BackBmp.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png) }

function Set-TestCamera([double]$X, [double]$Y, [double]$Angle) {
    $script:P.X = $X; $script:P.Y = $Y; $script:P.Angle = $Angle
    $area = $script:AreaOf[[int][Math]::Floor($Y) * $script:MapW + [int][Math]::Floor($X)]
    if ($area -ge 0) { $script:P.Area = $area }
    Update-AreaByPlayer
}

# All sprites (or wall textures) on one sheet, 4x enlarged, on a magenta background.
function Save-ArtSheet([string]$Path, [object[]]$Images, [string[]]$Labels) {
    $cols = 10; $cell = 64 * 3 + 8
    $rows = [int][Math]::Ceiling($Images.Count / $cols)
    $bmp = [System.Drawing.Bitmap]::new($cols * $cell, $rows * ($cell + 14))
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.Clear([System.Drawing.Color]::FromArgb(255, 90, 40, 90))
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::NearestNeighbor
    $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::Half
    $font = [System.Drawing.Font]::new('Consolas', 8)
    for ($i = 0; $i -lt $Images.Count; $i++) {
        $tile = [System.Drawing.Bitmap]::new(64, 64, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
        $bd = $tile.LockBits([System.Drawing.Rectangle]::new(0, 0, 64, 64), 'WriteOnly', $tile.PixelFormat)
        [System.Runtime.InteropServices.Marshal]::Copy([int[]]$Images[$i], 0, $bd.Scan0, 4096)
        $tile.UnlockBits($bd)
        $x = ($i % $cols) * $cell; $y = [int][Math]::Floor($i / $cols) * ($cell + 14)
        $g.DrawImage($tile, [System.Drawing.Rectangle]::new($x + 4, $y + 2, 192, 192))
        $g.DrawString($Labels[$i], $font, [System.Drawing.Brushes]::White, $x + 2, $y + 194)
        $tile.Dispose()
    }
    $bmp.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
    $g.Dispose(); $bmp.Dispose()
}

function Set-TestAim([Actor]$Target) {
    $script:P.Angle = ([Math]::Atan2(- ($Target.Y - $script:P.Y), $Target.X - $script:P.X) * 180 / [Math]::PI + 360) % 360
}

# Whatever the other end of a test connection has sent by now, as lines.
function Read-NetTestLines([System.Net.Sockets.TcpClient]$Tcp) {
    Start-Sleep -Milliseconds 150
    $stream = $Tcp.GetStream(); $buf = [byte[]]::new(65536); $text = ''
    while ($stream.DataAvailable) { $text += [System.Text.Encoding]::UTF8.GetString($buf, 0, $stream.Read($buf, 0, $buf.Length)) }
    @($text.Split("`n", [System.StringSplitOptions]::RemoveEmptyEntries))
}

function Send-NetTestLines([System.Net.Sockets.TcpClient]$Tcp, [string[]]$Lines) {
    $bytes = [System.Text.Encoding]::UTF8.GetBytes(($Lines -join "`n") + "`n")
    $Tcp.GetStream().Write($bytes, 0, $bytes.Length)
    Start-Sleep -Milliseconds 150
}

function Invoke-SelfTest([string]$OutDir) {
    $null = New-Item -ItemType Directory -Path $OutDir -Force
    $script:SaveDir = Join-Path $OutDir 'saves'

    $oddMap = Join-Path $OutDir 'odd-width.map'
    Set-Content -LiteralPath $oddMap -Value "@map`n....X" -Encoding utf8
    $rejected = $false
    try { $null = Read-MapFile $oddMap } catch { $rejected = $_.Exception.Message -like '*two-character tiles*' }
    if (-not $rejected) { throw 'map parser test: an odd-width row was accepted.' }
    Write-Step 'map parser test: odd-width rows are rejected'
    $script:GodMode = $true
    $script:KeyDown = [bool[]]::new(256)
    $script:KeyHit = [System.Collections.Generic.Queue[int]]::new()
    $script:Mode = 'play'

    # ---- art sheets ----
    $imgs = @(); $labels = @()
    for ($i = 1; $i -lt $script:WallNames.Count; $i++) { $imgs += , $script:WallLight[$i]; $labels += $script:WallNames[$i] }
    Save-ArtSheet (Join-Path $OutDir 'sheet-walls.png') $imgs $labels
    $imgs = @(); $labels = @()
    foreach ($k in ($script:Spr.Keys | Sort-Object)) {
        $v = $script:Spr[$k]
        if ($v[0] -is [int]) { $imgs += , $v; $labels += $k }
        else { for ($j = 0; $j -lt $v.Count; $j++) { $imgs += , $v[$j]; $labels += "$k[$j]" } }
    }
    Save-ArtSheet (Join-Path $OutDir 'sheet-sprites.png') $imgs $labels
    Write-Step "art sheets written ($($imgs.Count) sprite images)"

    # ---- views ----
    Start-Level $false $false
    Show-PlayFrame; Save-BackBuffer (Join-Path $OutDir 'view-1-start.png')
    $shots = @(
        @('view-2-corridor', 7.5, 34.5, 90), @('view-3-hub', 20.5, 24.5, 45), @('view-4-kennels', 24.5, 29.5, 250),
        @('view-5-officers', 21.5, 10.5, 110), @('view-6-storage', 32.5, 19.5, 0), @('view-7-lab', 38.5, 26.5, 270),
        @('view-8-commander', 45.5, 19.5, 0), @('view-9-arena', 34.5, 10.5, 90), @('view-10-lift', 40.5, 7.5, 0)
    )
    foreach ($s in $shots) {
        Set-TestCamera $s[1] $s[2] $s[3]
        Show-PlayFrame; $script:HudDirty = $true; Show-PlayFrame
        Save-BackBuffer (Join-Path $OutDir "$($s[0]).png")
    }

    # ---- sprite order: an enemy BEHIND a column must not be drawn over it ----
    $w = $script:MapW
    $col = $script:Statics | Where-Object { [object]::ReferenceEquals($_.Sprite, $script:Spr['column']) -and $script:Tiles[$_.Y * $w + $_.X - 2] -eq 0 -and $script:Tiles[$_.Y * $w + $_.X - 1] -eq 0 -and
        $script:Tiles[$_.Y * $w + $_.X + 1] -eq 0 -and $script:Tiles[$_.Y * $w + $_.X + 2] -eq 0 } | Select-Object -First 1
    Set-TestCamera ($col.X - 1.5) ($col.Y + 0.5) 0
    $lurker = New-Enemy 'guard' ($col.X + 2) $col.Y 4 'stand'
    $mid = [int]($script:ViewW / 2); $strip = { Update-View; for ($y = 0; $y -lt $script:ViewH; $y++) { $script:FB[$y * $script:ViewW + $mid] } }
    $without = & $strip
    $script:Actors.Add($lurker); $with = & $strip; $null = $script:Actors.Remove($lurker)
    if (-not $lurker.Visible) { throw 'sprite order test: the scene is not set up right, the guard is out of view.' }
    $differ = 0; for ($y = 0; $y -lt $with.Count; $y++) { if ($with[$y] -ne $without[$y]) { $differ++ } }
    Write-Step "sprite order test: a guard two tiles behind a column changes $differ pixels of the column's centre line"
    if ($differ) { throw 'sprite order test failed: far sprites are drawn over near ones.' }

    # ---- past a door frame: a guard whose shoulder is all one can see must be hittable ----
    $w = $script:MapW; $free = { param($x, $y) $script:Tiles[$y * $w + $x] -eq 0 -and -not $script:StaticBlock[$y * $w + $x] }
    $doorway = $script:Doors | Where-Object { $_.Vertical -and (& $free ($_.X - 2) $_.Y) -and (& $free ($_.X - 1) $_.Y) -and (& $free ($_.X + 1) $_.Y) -and (& $free ($_.X + 2) $_.Y) -and (& $free ($_.X + 2) ($_.Y + 1)) } | Select-Object -First 1
    $doorway.Action = 'open'; $doorway.Open = 1.0; $doorway.Timer = 0
    foreach ($other in @($script:Actors)) { if ([Math]::Abs($other.X - $doorway.X) -lt 6 -and [Math]::Abs($other.Y - $doorway.Y) -lt 6) { $null = $script:Actors.Remove($other) } }
    $lurker = New-Enemy 'guard' ($doorway.X + 2) ($doorway.Y + 1) 4 'stand'
    $lurker.X = $doorway.X + 2.5; $lurker.Y = $doorway.Y + 1.42; $lurker.HP = 500            # the far corner of the wall beside the door hides all but his shoulder
    $script:Actors.Add($lurker)
    Set-TestCamera ($doorway.X - 1.5) ($doorway.Y + 0.5) 0
    $script:P.Angle = ([Math]::Atan2(- ($lurker.Y - 0.2 - $script:P.Y), $lurker.X - $script:P.X) * 180 / [Math]::PI + 360) % 360      # at his near shoulder
    Show-PlayFrame; Save-BackBuffer (Join-Path $OutDir 'view-door-edge.png')
    $centreLine = Test-LineToPlayer $lurker.X $lurker.Y; $aimed = @(Get-AimedTargets) -contains $lurker; $exposed = Test-TargetExposed $lurker ($script:ViewW / 10)
    $script:P.Weapon = 1; $script:P.Ammo = 50
    for ($shot = 0; $shot -lt 8; $shot++) { Invoke-GunAttack }
    $script:P.Angle = ($script:P.Angle + 6) % 360; Update-View                               # a little further left: nothing but wall
    $hidden = -not (Test-TargetExposed $lurker ($script:ViewW / 10)) -or @(Get-AimedTargets) -notcontains $lurker
    Write-Step "door frame test: line to his centre free: $centreLine; in the sights: $aimed; shoulder in view: $exposed; eight shots took $(500 - $lurker.HP) health; aiming at the wall beside him finds nobody: $hidden"
    if ($centreLine -or -not $aimed -or -not $exposed -or $lurker.HP -ge 500 -or -not $hidden) { throw 'door frame test failed.' }
    $null = $script:Actors.Remove($lurker)
    Start-Level $false $false

    # ---- frame time ----
    Set-TestCamera 20.5 24.5 45
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    for ($i = 0; $i -lt 40; $i++) { $script:P.Angle = ($script:P.Angle + 3) % 360; Show-PlayFrame }
    Write-Step ('rendering: {0:0.0} ms per frame ({1} rays)' -f ($sw.ElapsedMilliseconds / 40), (320 / $script:ColumnStep))

    # ---- combat: sneak up behind the corridor guard and shoot him; the noise must wake his colleagues ----
    Start-Level $false $false
    Set-TestCamera 7.5 30.5 90
    $fire = @{ Forward = 0; Strafe = 0; Turn = 0; MouseTurn = 0.0; Run = $false; Fire = $true; Use = $false; Weapon = -1 }
    $idle = @{ Forward = 0; Strafe = 0; Turn = 0; MouseTurn = 0.0; Run = $false; Fire = $false; Use = $false; Weapon = -1 }
    $script:P.Ammo = 99                                     # the dice decide every shot - do not let the test depend on 8 bullets
    $target = $script:Actors | Where-Object { $_.Kind -eq 'guard' -and [Math]::Floor($_.X) -eq 7 -and [Math]::Floor($_.Y) -eq 27 }
    for ($f = 0; $f -lt 900 -and $script:Stats.Kills -eq 0; $f++) {
        if ($f -gt 0) { Set-TestAim $target }                     # after the first shot he moves - keep him in the sights like a player would
        Show-PlayFrame; Update-World 2.0 $(if ($f % 20 -lt 10) { $fire } else { $idle })
    }
    if ($script:Stats.Kills -lt 1) { throw 'combat test: the guard in the cell corridor was never hit.' }
    Show-PlayFrame; Save-BackBuffer (Join-Path $OutDir 'view-0-combat.png')
    # open the door to the guard room: its occupants should come for us
    Set-TestCamera 7.5 24.5 90
    $use = $idle.Clone(); $use.Use = $true
    Update-World 1.0 $use
    for ($f = 0; $f -lt 400; $f++) { Show-PlayFrame; Update-World 2.0 $(if ($f % 20 -lt 10) { $fire } else { $idle }) }
    $alert = @($script:Actors | Where-Object AttackMode).Count
    Write-Step "combat test: kills $($script:Stats.Kills), alerted enemies $alert, health $($script:P.Health), ammo $($script:P.Ammo)"
    Show-PlayFrame; Save-BackBuffer (Join-Path $OutDir 'view-0-combat2.png')

    # ---- the face in the status bar: every variant paints; a hit makes it wince and look towards the attacker ----
    $faces = [System.Drawing.Bitmap]::new(7 * 94, 6 * 106)
    $fg = [System.Drawing.Graphics]::FromImage($faces); $fg.Clear([System.Drawing.Color]::FromArgb(255, 16, 26, 44))
    $fg.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::NearestNeighbor; $fg.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::Half
    $col = 0
    foreach ($expr in 'idle', 'pain', 'grin', 'rage', 'sneak', 'sudo', 'god') {
        for ($tier = 0; $tier -le 5; $tier++) { $fg.DrawImage((Get-FaceBitmap $tier $expr 0), [System.Drawing.Rectangle]::new($col * 94 + 2, $tier * 106 + 2, 90, 102)) }
        $col++
    }
    $faces.Save((Join-Path $OutDir 'sheet-faces.png'), [System.Drawing.Imaging.ImageFormat]::Png); $fg.Dispose(); $faces.Dispose()
    $keepGod = $script:GodMode; $script:GodMode = $false
    $script:P.Health = 100; $script:P.Angle = 0.0; $script:P.PainTics = 0.0; $script:P.FaceLook = 1
    $fresh = Get-FaceKey
    $thug = [Actor]::new(); $thug.X = $script:P.X; $thug.Y = $script:P.Y - 3                 # straight to the left of somebody looking east
    Invoke-PlayerDamage 150 $thug
    $hit = Get-FaceKey; $script:P.PainTics = 0.0; $after = Get-FaceKey
    Write-Step "face test: fresh '$fresh', when hit '$hit', afterwards '$after' (health $($script:P.Health))"
    if ($fresh -ne '0|idle|0' -and $fresh -notlike '0|idle|*') { throw 'face test failed: a healthy face expected.' }
    if ($hit -notlike '*|pain|0' -or $after -notlike '*|idle|-1' -or $after -like '0|*') { throw 'face test failed: no wince, no damage or no look to the left.' }
    $script:GodMode = $keepGod; $script:P.Health = 100; $script:PlayerDied = $false; $script:P.LookHold = 0.0

    # ---- abilities: snapshots must restore the world exactly; -WhatIf, -Confirm, -Force and Undo must do what they say ----
    $script:LevelIndex = 0; $script:BonusMap = $null; $script:Difficulty = 1
    Start-Level $false $false
    $keepGod = $script:GodMode; $script:GodMode = $false
    $walker = $script:Actors | Where-Object { $_.State -like '*.path*' } | Select-Object -First 1
    Set-TestCamera ($walker.X + 0.2) ($walker.Y + 2.4) 90; $script:P.Privilege = 100.0
    for ($f = 0; $f -lt 20; $f++) { Update-View; Update-World 2.0 $idle }
    $print = { "$([Math]::Round($script:P.X, 4)),$([Math]::Round($script:P.Y, 4)),$($script:P.Health),$($script:Stats.Kills)," + (($script:Actors | ForEach-Object { "$($_.State):$([Math]::Round($_.X, 4)):$([Math]::Round($_.Y, 4)):$($_.HP)" }) -join ';') + ',' + (($script:Doors | ForEach-Object { "$($_.Action)$([Math]::Round($_.Open, 3))" }) -join ';') }
    $before = & $print
    $snapshot = New-WorldSnapshot
    $fire = $idle.Clone(); $fire.Fire = $true; $fire.Forward = 1
    for ($f = 0; $f -lt 90; $f++) { Update-View; Update-World 2.0 $fire }
    $changed = (& $print) -ne $before
    Restore-WorldSnapshot $snapshot
    $same = (& $print) -eq $before
    # -WhatIf: ghosts appear, the world does not move, and afterwards it is exactly as before
    $whatIf = $idle.Clone(); $whatIf.Ability = 1
    Update-World 2.0 $whatIf
    $marks = @($script:Actors | Where-Object Kind -eq 'whatif').Count
    Update-View; Show-PlayFrame; Save-BackBuffer (Join-Path $OutDir 'view-whatif.png')
    for ($f = 0; $f -lt 10; $f++) { Update-World 2.0 $idle }
    $frozen = $script:WhatIfTics -gt 0
    Stop-WhatIf
    $untouched = (& $print) -eq $before
    # -Confirm: the world gets a third of the time, the player all of it
    $confirm = $idle.Clone(); $confirm.Ability = 2
    $normal = Update-Abilities 2.0 $idle
    $slow = Update-Abilities 2.0 $confirm
    $script:ConfirmTics = 0.0
    # -Force: the gold door has no chance
    $gold = $script:Doors | Where-Object { $_.Lock -eq 1 } | Select-Object -First 1
    $script:P.Privilege = 100.0
    if ($gold.Vertical) { Set-TestCamera ($gold.X - 0.5) ($gold.Y + 0.5) 0 } else { Set-TestCamera ($gold.X + 0.5) ($gold.Y + 1.5) 90 }
    $force = $idle.Clone(); $force.Ability = 4
    Update-World 1.0 $force
    $forced = $gold.Action                                        # (the undo below goes back to before this)
    # Undo: take a beating, then take it back
    $script:P.Privilege = 100.0; $script:P.Health = 100
    for ($f = 0; $f -lt 60; $f++) { Update-World 2.0 $idle }
    Invoke-PlayerDamage 200 $null; $hurt = $script:P.Health
    $undo = $idle.Clone(); $undo.Ability = 5
    Update-World 1.0 $undo
    Write-Step ("ability test: snapshot restores exactly={0} (world had changed={1}); -WhatIf: {2} ghosts, time frozen={3}, world untouched={4}; -Confirm: the world advances {5:0.00} instead of {6:0.00} tics; -Force: gold door '{7}'; Undo: health {8} -> {9}, privilege left {10:0}" -f
        $same, $changed, $marks, $frozen, $untouched, $slow, $normal, $forced, $hurt, $script:P.Health, $script:P.Privilege)
    if (-not $same -or -not $changed -or $marks -lt 1 -or -not $frozen -or -not $untouched -or $normal -ne 2.0 -or [Math]::Abs($slow - 0.6) -gt 0.001 -or $forced -eq 'closed' -or
        $script:P.Health -le $hurt -or $script:P.Privilege -gt 45) { throw 'ability test failed.' }
    $script:GodMode = $keepGod; $script:PlayerDied = $false
    Start-Level $false $false

    # ---- the console: real pipelines act on the game, and nothing gets out of the sandbox ----
    if (-not $script:KeyHit) { $script:KeyHit = [System.Collections.Generic.Queue[int]]::new() }
    $script:LevelIndex = 0; $script:BonusMap = $null; Start-Level $false $false
    Set-TestCamera 20.5 24.5 45; $script:P.Privilege = 100.0
    Open-Console
    $kills = $script:Stats.Kills
    $canary = Join-Path $OutDir 'canary.txt'; Set-Content -LiteralPath $canary -Value 'still here'
    foreach ($line in 'Get-Enemy | Sort-Object Distance | Select-Object -First 3', 'Get-Enemy | sort Distance | select -First 1 | Stop-Enemy -WhatIf',
        'Get-Enemy | sort Distance | select -First 1 | Stop-Enemy', "Get-Door | ? Lock -eq 'gold' | Open-Door", 'Get-Door | Stop-Enemy',
        "Remove-Item '$canary' -Force", "[System.IO.File]::Delete('$canary')", "cmd /c del `"$canary`"", 'while ($true) { }', 'Get-Player') { Invoke-ConsoleLine $line }
    $text = ($script:Con.Lines | ForEach-Object { $_[0] }) -join "`n"
    Show-PlayFrame; Show-Console; Save-BackBuffer (Join-Path $OutDir 'view-console.png')
    $gold = $script:Doors | Where-Object { $_.TexId -eq $script:TEX_DOOR -and $_.Action -ne 'closed' } | Select-Object -First 1
    Close-Console
    Write-Step "console test: $($script:Con.Lines.Count) lines of output, kills $kills -> $($script:Stats.Kills), privilege left $([int]$script:P.Privilege), canary file alive: $(Test-Path -LiteralPath $canary)"
    if ($script:Stats.Kills -ne $kills + 1 -or -not (Test-Path -LiteralPath $canary) -or $text -notmatch 'What if: Performing' -or $text -notmatch 'that is no enemy' -or
        $text -notmatch 'sandbox' -or $text -notmatch 'two seconds' -or $text -notmatch 'terminated' -or -not $gold -or $script:Mode -ne 'play') { throw "console test failed:`n$text" }
    Remove-Item -LiteralPath $canary

    # ---- options: change a value, rebind a key (the old owner of the key gets the other one), save, load ----
    Remove-Item -LiteralPath (Get-SettingsPath) -ErrorAction SilentlyContinue
    Open-Options
    $script:Options.Row = 0; Update-Options @($script:VK.Right, $script:VK.Right)                    # mouse sensitivity up twice
    $script:Options.Row = 8; Update-Options @($script:VK.Enter); Update-Options @(65)                # row 8 is "forward" (after seven settings): it becomes A - which was "strafe left"
    Show-Options; Save-BackBuffer (Join-Path $OutDir 'screen-options.png')
    Update-Options @($script:VK.Esc)
    $script:Bind.Forward = 1; $script:Settings.Mouse = 9
    Import-Settings
    Write-Step "options test: mouse $($script:Settings.Mouse), forward = $(Get-KeyName $script:Bind.Forward), strafe left = $(Get-KeyName $script:Bind.StrafeLeft), back in mode '$($script:Mode)'"
    if ($script:Settings.Mouse -ne 0.16 -or $script:Bind.Forward -ne 65 -or $script:Bind.StrafeLeft -ne 87) { throw 'options test failed.' }
    foreach ($key in $script:BindDefaults.Keys) { $script:Bind[$key] = $script:BindDefaults[$key] }; $script:Settings.Mouse = 0.12
    Remove-Item -LiteralPath (Get-SettingsPath) -ErrorAction SilentlyContinue

    # ---- the files on the terminals: none on the player's own console, a floor's worth at a terminal; the door code works once ----
    $script:LevelIndex = 0; $script:BonusMap = $null; Start-Level $false $false
    $terminal = @($script:TerminalAt.Keys)[0]
    $silver = $script:Doors | Where-Object { $_.Lock -eq 2 } | Select-Object -First 1
    $script:Con = $null
    Open-Console; Invoke-ConsoleLine 'Get-ChildItem'; $own = ($script:Con.Lines | ForEach-Object { $_[0] }) -join "`n"; Close-Console
    $privilege = $script:P.Privilege
    Open-Console $terminal
    foreach ($line in 'ls', 'cat mail*', 'Unlock-Door -Code 4711', 'Unlock-Door 4711', 'Use-Token nonsense') { Invoke-ConsoleLine $line }
    $text = ($script:Con.Lines | ForEach-Object { $_[0] }) -join "`n"
    Show-PlayFrame; Show-Console; Save-BackBuffer (Join-Path $OutDir 'view-console-files.png')
    Close-Console
    Write-Step "story test: $($script:TerminalAt.Count) terminals on floor 1, logging on gave $($script:P.Privilege - $privilege) privilege, the silver door's lock is now $($silver.Lock)"
    if ($own -notmatch 'No file system here' -or $text -notmatch 'mail-0412\.eml' -or $text -notmatch 'service code 4711' -or $text -notmatch 'lock\(s\) on this floor are open' -or
        $text -notmatch 'used on this floor already' -or $text -notmatch 'means nothing' -or $silver.Lock -ne 0 -or $script:TerminalAt.Count -lt 3) { throw "story test failed:`n$text" }
    foreach ($floor in $script:StoryFiles.Keys) { foreach ($code in $script:StoryFiles[$floor].Codes.Keys) { if (-not (($script:StoryFiles[$floor].Files.Values -join ' ') -match [regex]::Escape($code))) { throw "story test failed: nothing on floor '$floor' mentions the code '$code'." } } }

    # ---- the console's profile: a function, an alias and a hotkey survive a restart; the profile itself is as sandboxed as a typed line ----
    $script:LevelIndex = 0; $script:BonusMap = $null; Start-Level $false $false
    if ($script:Con) { $script:Con.Runspace.Dispose() }; $script:Con = $null
    Remove-Item -LiteralPath (Get-ProfilePath) -ErrorAction SilentlyContinue
    Open-Console
    foreach ($line in 'function kn { Get-Enemy | Select-Object -First 1 | Suspend-Enemy }', 'Set-Alias ge Get-Enemy', "Set-Hotkey 1 'kn'", 'Get-Hotkey', 'Save-Profile', 'Get-Content $PROFILE') { Invoke-ConsoleLine $line }
    $text = ($script:Con.Lines | ForEach-Object { $_[0] }) -join "`n"
    Show-PlayFrame; Show-Console; Save-BackBuffer (Join-Path $OutDir 'view-console-profile.png')
    Close-Console
    $saved = Get-Content -LiteralPath (Get-ProfilePath) -Raw
    $canary = Join-Path $OutDir 'profile-canary.txt'; Set-Content -LiteralPath $canary -Value 'still here'
    Add-Content -LiteralPath (Get-ProfilePath) -Value "[System.IO.File]::Delete('$canary')", "Remove-Item '$canary'"
    $script:Con.Runspace.Dispose(); $script:Con = $null; $script:Hotkeys = @{}                     # "the game is started again"
    $script:P.Privilege = 100; $consoleBefore = $script:Run.Console
    Invoke-ConsoleHotkey 1
    $stunned = @($script:Actors | Where-Object { $_.Stun -gt 0 }).Count
    Invoke-ConsoleHotkey 2; $empty = $script:Message
    Invoke-ConsoleLine 'ge | Measure-Object | Select-Object -ExpandProperty Count'
    $aliasWorks = "$($script:Con.Lines[$script:Con.Lines.Count - 1][0])".Trim() -match '^\d+$'
    Invoke-ConsoleLine 'Clear-Content $PROFILE'
    Write-Step "profile test: saved $(@($saved -split "`n" | Where-Object { $_ -match '^(function|Set-)' }).Count) definitions; after a restart hotkey 1 suspended $stunned enemy, the alias works: $aliasWorks, the canary is $(if (Test-Path $canary) { 'alive' } else { 'DEAD' })"
    if ($saved -notmatch 'function kn' -or $saved -notmatch 'Set-Alias ge' -or $saved -notmatch "Set-Hotkey 1 'kn'" -or $text -notmatch 'saves\\profile.ps1|function kn' -or $stunned -ne 1 -or
        $script:Run.Console -ne $consoleBefore + 1 -or $empty -notmatch 'is empty' -or -not $aliasWorks -or -not (Test-Path $canary) -or (Test-Path -LiteralPath (Get-ProfilePath)) -or $script:Hotkeys.Count) { throw "profile test failed:`n$text" }
    Remove-Item -LiteralPath $canary -ErrorAction SilentlyContinue
    $script:Con.Runspace.Dispose(); $script:Con = $null

    # ---- god mode and the one-hit cheat together: a hit must not leave the screen red ----
    $keepGod = $script:GodMode; $keepOne = $script:OneHitKill
    $script:GodMode = $true; $script:OneHitKill = $true; $script:DamageFlash = 0.0; $script:P.Health = 100
    foreach ($hit in 1..5) { Invoke-PlayerDamage 10 $null }
    $flash = $script:DamageFlash
    $script:GodMode = $keepGod; $script:OneHitKill = $keepOne; $script:DamageFlash = 0.0; $script:Shake = 0.0; $script:PlayerDied = $false
    Write-Step "cheat flash test: five fatal hits in god mode leave health $($script:P.Health) and a flash of $flash tics"
    if ($script:P.Health -ne 100 -or $flash -gt 60) { throw 'cheat flash test failed.' }

    # ---- the execution policy: heat raises it, quiet lowers it, Undo takes it back, the console calms it down ----
    $script:LevelIndex = 0; $script:BonusMap = $null; Start-Level $false $false
    $keepDifficulty = $script:Difficulty; $script:Difficulty = 2; $script:MadeNoise = $false
    Update-Policy 1; $start = (Get-Policy).Name
    Add-PolicyHeat 30; Update-Policy 1; $second = Get-Policy
    $snapshot = New-WorldSnapshot
    Add-PolicyHeat 60; Update-Policy 1; $alarm = (Get-Policy).Name
    Restore-WorldSnapshot $snapshot; $undone = (Get-Policy).Name
    $heat = $script:Stats.Heat; Update-Policy 1400; $cooled = $heat - $script:Stats.Heat
    $script:P.Privilege = 100; $script:Con = $null
    Open-Console; Invoke-ConsoleLine 'Get-ExecutionPolicy'; Invoke-ConsoleLine 'Set-ExecutionPolicy Restricted'; Invoke-ConsoleLine 'Set-ExecutionPolicy Bypass'
    $text = ($script:Con.Lines | ForEach-Object { $_[0] }) -join "`n"; Close-Console
    Write-Step "policy test: $start -> $($second.Name) (reaction x$($second.React)) -> $alarm -> undone to $undone; twenty quiet seconds cool it by $([Math]::Round($cooled, 1)); the console set it to $((Get-Policy).Name) for $(100 - [int]$script:P.Privilege) privilege"
    if ($start -ne 'Restricted' -or $second.Name -ne 'AllSigned' -or $alarm -ne 'Unrestricted' -or $undone -ne 'AllSigned' -or [Math]::Abs($cooled - 10) -gt 0.1 -or
        (Get-Policy).Name -ne 'Restricted' -or [int]$script:P.Privilege -ne 85 -or $text -notmatch 'AllSigned' -or $text -notmatch 'is none of') { throw "policy test failed:`n$text" }
    $script:Difficulty = $keepDifficulty
    $script:Con.Runspace.Dispose(); $script:Con = $null

    # ---- security: a camera heats the policy up, a sentry gun shoots - and changes sides when the console tells it to ----
    $script:LevelIndex = 0; $script:BonusMap = $null; Start-Level $false $false
    $keepDifficulty = $script:Difficulty; $script:Difficulty = 2; $script:MadeNoise = $false
    Set-TestCamera 24.5 20.5 0
    $total = $script:Stats.KillTotal
    Add-Enemy 'camera' 27 20 4 'ambush'; $camera = $script:Actors[$script:Actors.Count - 1]
    Add-Enemy 'turret' 24 23 2 'ambush'; $turret = $script:Actors[$script:Actors.Count - 1]
    $camera.AttackMode = $true; Set-ActorState $camera 'camera.chase1'
    $heat = $script:Stats.Heat; Invoke-ThinkCameraChase $camera 70; $heated = $script:Stats.Heat - $heat
    $victim = $script:Actors | Where-Object { $_.Kind -eq 'guard' -and $_.Shootable } | Sort-Object { [Math]::Abs($_.X - 24.5) + [Math]::Abs($_.Y - 23.5) } | Select-Object -First 1
    $script:ActorAt[$victim.TY * $script:MapW + $victim.TX] = $null
    $victim.X = 26.5; $victim.Y = 23.5; $victim.TX = 26; $victim.TY = 23; $victim.Area = $turret.Area; $script:ActorAt[23 * $script:MapW + 26] = $victim
    $script:P.Privilege = 100; if ($script:Con) { $script:Con.Runspace.Dispose() }; $script:Con = $null
    Open-Console
    foreach ($line in 'Get-Enemy -Kind camera | Set-Turret -Owner Me', 'Get-Enemy -Kind turret | Set-Turret -Owner Me -WhatIf', 'Get-Enemy -Kind turret | Set-Turret -Owner Me', 'Get-Enemy -Kind turret') { Invoke-ConsoleLine $line }
    $text = ($script:Con.Lines | ForEach-Object { $_[0] }) -join "`n"; Close-Console
    $hp = $victim.HP; $kills = $script:Stats.Kills
    for ($f = 0; $f -lt 40 -and $victim.Shootable; $f++) { Invoke-ThinkTurretChase $turret 20 }
    Show-PlayFrame; Save-BackBuffer (Join-Path $OutDir 'view-security.png')
    Stop-Actor $camera
    Write-Step "security test: a second on camera heats the house by $([Math]::Round($heated, 1)); the hacked sentry gun took the guard from $hp to $($victim.HP) health; kill total $total -> $($script:Stats.KillTotal), kills $kills -> $($script:Stats.Kills)"
    if ([Math]::Abs($heated - 8.4) -gt 0.3 -or -not $turret.Hacked -or $victim.Shootable -or $script:Stats.KillTotal -ne $total -or $script:Stats.Kills -ne $kills + 1 -or
        $text -notmatch 'not a sentry gun' -or $text -notmatch 'What if' -or $text -notmatch 'answers to you now' -or $text -notmatch 'yours') { throw "security test failed:`n$text" }
    $script:Difficulty = $keepDifficulty
    $script:Con.Runspace.Dispose(); $script:Con = $null

    # ---- Start-Job: the drone collects what is in reach, Undo gives it back, Receive-Job drops it at the player's feet ----
    $script:LevelIndex = 0; $script:BonusMap = $null; Start-Level $false $false
    Set-TestCamera 24.5 20.5 0
    $inReach = @($script:Items | Where-Object { -not $_.Removed -and $script:AreaByPlayer[$script:AreaOf[$_.Y * $script:MapW + $_.X]] }).Count
    $script:P.Privilege = 100; if ($script:Con) { $script:Con.Runspace.Dispose() }; $script:Con = $null
    Open-Console; Invoke-ConsoleLine 'Start-Job'; Invoke-ConsoleLine 'Start-Job'; Close-Console
    $drone = Get-Drone
    $drone.X = 26.2; $drone.Y = 20.2; Show-PlayFrame; Save-BackBuffer (Join-Path $OutDir 'view-drone.png'); $drone.X = $script:P.X; $drone.Y = $script:P.Y
    for ($f = 0; $f -lt 30; $f++) { Invoke-ThinkDrone $drone 10 }
    $snapshot = New-WorldSnapshot
    for ($f = 0; $f -lt 400 -and -not ($drone.Hacked -and [Math]::Abs($drone.X - $script:P.X) + [Math]::Abs($drone.Y - $script:P.Y) -lt 1.5); $f++) { Invoke-ThinkDrone $drone 10 }
    $carried = @($script:Stats.Cargo).Count; $left = @($script:Items | Where-Object { -not $_.Removed }).Count
    Restore-WorldSnapshot $snapshot
    $undone = @($script:Items | Where-Object { -not $_.Removed }).Count - $left
    $drone = Get-Drone
    for ($f = 0; $f -lt 400 -and -not ($drone.Hacked -and [Math]::Abs($drone.X - $script:P.X) + [Math]::Abs($drone.Y - $script:P.Y) -lt 1.5); $f++) { Invoke-ThinkDrone $drone 10 }
    Open-Console; Invoke-ConsoleLine 'Get-Job'; Invoke-ConsoleLine 'Receive-Job'; Invoke-ConsoleLine 'Get-Job'
    $text = ($script:Con.Lines | ForEach-Object { $_[0] }) -join "`n"; Close-Console
    $atFeet = @($script:Items | Where-Object { -not $_.Removed -and $_.X -eq 24 -and $_.Y -eq 20 }).Count
    Write-Step "drone test: $inReach things in reach, it carried $carried home (Undo put $undone of them back), Receive-Job dropped $atFeet at the player's feet, privilege $([int]$script:P.Privilege)"
    if ($carried -lt 1 -or $carried -ne [Math]::Min(6, $inReach) -or $undone -lt 1 -or $atFeet -ne $carried -or (Get-Drone) -or [int]$script:P.Privilege -ne 70 -or
        $text -notmatch 'one drone is all' -or $text -notmatch 'Completed' -or $text -notmatch 'Received:' -or $text -notmatch 'No jobs') { throw "drone test failed:`n$text" }
    $script:Con.Runspace.Dispose(); $script:Con = $null

    # ---- Install-Module: three on offer, none of them installed already, and every one of them does what it says ----
    $script:LevelIndex = 0; $script:BonusMap = $null; Start-Level $false $false
    $keepDifficulty = $script:Difficulty; $script:Difficulty = 2
    $offer = @(Get-PerkOffer); $again = @(Get-PerkOffer)
    $plain = "$(Get-AbilityCost 1)/$(Get-AbilityCost 3)/$(Get-AmmoCount 8)"; $script:P.Health = 50; Add-Health 10; $plainHealth = $script:P.Health
    foreach ($m in $script:ModulePerks.Keys) { Install-Perk $m }; Install-Perk 'PSReadLine'
    $with = "$(Get-AbilityCost 1)/$(Get-AbilityCost 3)/$(Get-AmmoCount 8)"; $script:P.Health = 50; Add-Health 10
    $none = @(Get-PerkOffer)
    Start-Level $true $true
    $script:Result = @{ Last = $false; Exact = 100.0; Previous = 0; Kills = 50; Secrets = 25; Treasures = 10; Bonus = 0; Offer = $offer; Tests = (Invoke-FloorTests); Transcript = @{ Verdict = 'Completed.' } }
    Show-DoneScreen; Save-BackBuffer (Join-Path $OutDir 'screen-perks.png')
    Write-Step "perk test: offered $($offer -join ', '); cost of -WhatIf/-Verbose and rounds per clip $plain -> $with; 10 health heal $($plainHealth - 50) -> $($script:P.Health - 50); $($script:P.Modules.Count) installed, the secrets are on the map: $($script:StorySecrets)"
    if ($offer.Count -ne 3 -or @($offer | Select-Object -Unique).Count -ne 3 -or ($offer -join ',') -ne ($again -join ',') -or $plain -ne '25/15/8' -or $with -ne '19/0/10' -or
        $plainHealth -ne 60 -or $script:P.Health -ne 65 -or $script:P.Modules.Count -ne $script:ModulePerks.Count -or $none.Count -ne 0 -or -not $script:StorySecrets) { throw 'perk test failed.' }
    $script:Difficulty = $keepDifficulty; New-Player

    # ---- light and darkness: a dark room is dark, the flashlight helps the player - and whoever is looking for him ----
    $script:LevelIndex = 5; $script:BonusMap = $null; Start-Level $false $false; $script:Message = $null
    Add-Enemy 'guard' 4 11 0 'stand'; $watcher = $script:Actors[$script:Actors.Count - 1]
    Set-TestCamera 9.5 11.5 180
    $sums = foreach ($light in $false, $true) {
        $script:P.Light = $light
        for ($f = 0; $f -lt 40; $f++) { Show-PlayFrame }
        Save-BackBuffer (Join-Path $OutDir "view-dark-$(if ($light) { 'flashlight' } else { 'off' }).png")
        $sum = 0L; for ($i = 0; $i -lt $script:FB.Length; $i += 7) { $c = $script:FB[$i]; $sum += (($c -shr 16) -band 255) + (($c -shr 8) -band 255) + ($c -band 255) }
        [pscustomobject]@{ Light = $light; Brightness = [int]($sum / ($script:FB.Length / 7) / 3); Seen = (Test-Sight $watcher) }
    }
    $script:MadeNoise = $true; $script:P.Light = $false; Show-PlayFrame; $script:MadeNoise = $false
    Save-BackBuffer (Join-Path $OutDir 'view-dark-muzzle.png')
    Set-TestCamera 13.5 20.5 90; for ($f = 0; $f -lt 40; $f++) { Show-PlayFrame }
    Write-Step "darkness test: dark areas $(@($script:DarkArea | Where-Object { $_ }).Count); brightness without/with the flashlight $($sums[0].Brightness)/$($sums[1].Brightness); the guard five tiles away sees the player: $($sums[0].Seen)/$($sums[1].Seen); back in the aisle the darkness is $($script:Darkness)"
    if (@($script:DarkArea | Where-Object { $_ }).Count -ne 1 -or $sums[1].Brightness -le $sums[0].Brightness * 1.3 -or $sums[0].Seen -or -not $sums[1].Seen -or $script:Darkness -ne 0) { throw 'darkness test failed.' }
    $script:LevelIndex = 0

    # ---- the bosses: THE PRINTER jams after every second salvo (triple damage, two print jobs), BLUE SCREEN crashes the controls and halts everything when it dies ----
    $script:LevelIndex = 9; $script:BonusMap = $null; Start-Level $false $false; $script:Message = $null
    $keepGod = $script:GodMode; $script:GodMode = $true
    $printer = $script:Actors | Where-Object Kind -eq 'uber' | Select-Object -First 1
    $bsod = $script:Actors | Where-Object Kind -eq 'bsod' | Select-Object -First 1
    Set-TestCamera 25.5 17.5 270
    $total = $script:Stats.KillTotal; $count = $script:Actors.Count
    Invoke-ActionJam $printer; $first = $printer.State; Invoke-ActionJam $printer; $second = $printer.State
    Update-Actors 0.01
    $printed = @($script:Actors | Where-Object { $_.Kind -eq 'bot' -and $_.AttackMode -and [Math]::Abs($_.X - $printer.X) -lt 2 }).Count
    $hp = $printer.HP; Invoke-ActorDamage $printer 10 'bullet'; $jamDamage = $hp - $printer.HP
    $bsod.AttackMode = $true; Set-ActorState $bsod 'bsod.shoot2'
    Invoke-ActionGlitch $bsod
    $walk = $idle.Clone(); $walk.Forward = 1
    $y = $script:P.Y; Update-Player 10 $walk; $frozenMove = [Math]::Abs($script:P.Y - $y)
    Show-PlayFrame; Save-BackBuffer (Join-Path $OutDir 'view-bsod.png')
    $script:Stats.Freeze = 0.0; Update-Player 10 $walk; $freeMove = [Math]::Abs($script:P.Y - $y)
    Invoke-ActionHalt $bsod
    $halted = @($script:Actors | Where-Object { $_.Shootable -and $_.Stun -gt 0 }).Count
    Write-Step "boss test: the printer's salvos lead to '$first', then '$second' with $printed print jobs (kill total $total -> $($script:Stats.KillTotal)); 10 damage during the jam cost it $jamDamage; frozen the player moved $([Math]::Round($frozenMove, 3)), free $([Math]::Round($freeMove, 3)); the halt stopped $halted"
    if ($first -eq 'uber.jam1' -or $second -ne 'uber.jam1' -or $printed -ne 2 -or $script:Stats.KillTotal -ne $total + 2 -or $jamDamage -lt 30 -or $frozenMove -gt 0.001 -or $freeMove -lt 0.05 -or $halted -lt 10 -or -not $bsod) { throw 'boss test failed.' }
    $script:GodMode = $keepGod; $script:GlitchTics = 0.0; $script:LevelIndex = 0

    # ---- what a floor has scheduled: the power fails, the doors lock, Patch Tuesday heals - each once, and Undo takes it back ----
    $script:LevelIndex = 9; $script:BonusMap = $null; Start-Level $false $false; $script:Message = $null
    $keepDifficulty = $script:Difficulty; $script:Difficulty = 2
    Set-TestCamera 25.5 45.5 90
    $scheduled = ($script:LevelEvents | ForEach-Object { "$($_.Kind)@$([int]($_.At / 70))" }) -join ' '
    $victim = $script:Actors | Where-Object { $_.Kind -eq 'elite' -and $_.Shootable } | Select-Object -First 1; $victim.HP = 5
    $script:Stats.Tics = 70 * 239; Update-Events 1; $before = [int]$script:Stats.EventsDone
    $snapshot = New-WorldSnapshot
    $script:Stats.Tics = 70 * 241; Update-Events 1; $dark = $script:Stats.PowerOut
    for ($f = 0; $f -lt 30; $f++) { Show-PlayFrame }; Save-BackBuffer (Join-Path $OutDir 'view-powerfail.png')
    $script:Stats.Tics = 70 * 421; Update-Events 1; $sealed = @($script:Doors | Where-Object { $_.Jam -gt 0 }).Count
    $notice = (Get-EventNotice).Text
    $heat = $script:Stats.Heat; $script:Stats.Tics = 70 * 661; Update-Events 1; Update-Events 1
    $healed = $victim.HP; $fired = [int]$script:Stats.EventsDone; $heated = $script:Stats.Heat - $heat
    Restore-WorldSnapshot $snapshot
    Write-Step "event test: floor 10 has $scheduled; power out for $([int]($dark / 70)) s, $sealed doors sealed, notice '$notice', Patch Tuesday took the elite from 5 to $healed health and heated the house by $([int]$heated) before the Undo; fired $before -> $fired -> $([int]$script:Stats.EventsDone)"
    if ($scheduled -ne 'powerfail@240 lockdown@420 patch@660' -or $before -ne 0 -or [int]($dark / 70) -ne 25 -or $sealed -lt 5 -or $notice -notmatch 'POWER FAILURE|PATCH TUESDAY in' -or $healed -le 5 -or $heated -lt 29 -or $fired -ne 7 -or
        [int]$script:Stats.EventsDone -ne 0 -or $script:Stats.PowerOut -gt 0) { throw 'event test failed.' }
    $script:Difficulty = $keepDifficulty; $script:LevelIndex = 0

    # ---- the arena: the same number gives the same waves, they grow, they come through the gates, and the run is kept ----
    Remove-Item -LiteralPath (Get-HordePath) -ErrorAction SilentlyContinue
    $keepDifficulty = $script:Difficulty; $script:Difficulty = 1; $keepGod = $script:GodMode; $script:GodMode = $true
    $started = Start-Horde 4711
    Save-Game '9'; $refused = -not (Test-Path -LiteralPath (Get-SavePath '9'))      # a save from the arena could never be loaded: there is none
    $same = ((Get-HordeWave 3) -join ',') -eq ((Get-HordeWave 3) -join ','); $sizes = (1, 5, 10 | ForEach-Object { "$(@(Get-HordeWave $_).Count)" }) -join '/'
    $fifth = @(Get-HordeWave 5)[0]; $tenth = @(Get-HordeWave 10)[0]
    for ($f = 0; $f -lt 400 -and @($script:Actors | Where-Object { $_.Shootable -and -not $_.Def.Inert }).Count -lt 3; $f++) { Update-World 4.0 $idle }
    $wave = $script:Stats.Wave; $arrived = @($script:Actors | Where-Object { $_.Shootable -and $_.AttackMode }).Count
    Set-TestCamera 16.5 22.5 90; Show-PlayFrame; Save-BackBuffer (Join-Path $OutDir 'view-horde.png')
    foreach ($a in @($script:Actors)) { if ($a.Shootable -and -not $a.Def.Inert) { Stop-Actor $a } }
    $script:Stats.WaveQueue = @()
    $items = @($script:Items | Where-Object { -not $_.Removed }).Count
    for ($f = 0; $f -lt 120 -and $script:Stats.Wave -eq $wave; $f++) { Update-World 4.0 $idle }
    $supplies = @($script:Items | Where-Object { -not $_.Removed }).Count - $items
    $script:P.Cheated = $false; $line = Save-HordeRun $false; $again = Save-HordeRun $false
    Write-Step "horde test: waves of $sizes (the 5th leads with a $fifth, the 10th with a $tenth); wave $wave sent $arrived through the gates, clearing it brought wave $($script:Stats.Wave) and $supplies supplies; saving refused: $refused; '$line'"
    if (-not $started -or -not $refused -or -not $same -or $fifth -ne 'boss' -or $tenth -ne 'uber' -or $wave -ne 1 -or $arrived -lt 3 -or $script:Stats.Wave -ne 2 -or $supplies -lt 3 -or $line -notmatch 'first run' -or $again -notmatch 'your best: 1 waves') { throw 'horde test failed.' }
    Stop-Horde; $script:Difficulty = $keepDifficulty; $script:GodMode = $keepGod; $script:LevelIndex = 0
    Remove-Item -LiteralPath (Get-HordePath) -ErrorAction SilentlyContinue

    # ---- the commander's gold key: only where there is a gold lock to open - otherwise his strongbox ----
    $drops = foreach ($floor in 0, 1) {
        $script:LevelIndex = $floor; $script:BonusMap = $null; Start-Level $false $false
        $commander = $script:Actors | Where-Object Kind -eq 'boss' | Select-Object -First 1
        $count = $script:Items.Count; Stop-Actor $commander
        "$($script:Items[$count].Item)"
    }
    Write-Step "key test: the commander of floor 1 (a gold door) drops '$($drops[0])', the one of floor 2 (none) drops '$($drops[1])'"
    if ($drops[0] -ne 'key_gold' -or $drops[1] -ne 'chest') { throw 'key test failed.' }
    $script:LevelIndex = 0

    # ---- loot: tables, armour, a keycard on a locked door, a silent streak that ends when somebody notices, a signed drop ----
    $script:LevelIndex = 0; $script:BonusMap = $null; Start-Level $false $false
    $keepDifficulty = $script:Difficulty; $script:Difficulty = 2; $keepGod = $script:GodMode; $script:GodMode = $false
    $p = $script:P; $p.Health = 100; $p.Armor = 0
    $null = Invoke-Pickup 'vest'; Invoke-PlayerDamage 40 $null; $afterHit = "$($p.Health)/$($p.Armor)"
    $silver = $script:Doors | Where-Object { $_.Lock -eq 2 } | Select-Object -First 1; $index = [Array]::IndexOf($script:Doors.ToArray(), $silver)
    Invoke-DoorUse $index; $stillLocked = $silver.Lock
    $null = Invoke-Pickup 'keycard'; Invoke-DoorUse $index
    $victims = @($script:Actors | Where-Object { $_.Kind -eq 'guard' -and $_.Shootable } | Select-Object -First 6)
    $items = $script:Items.Count
    foreach ($v in $victims[0..4]) { Stop-Actor $v }
    $streak = $script:Stats.Streak; $dropped = @($script:Items | Select-Object -Skip $items | ForEach-Object Item)
    Start-Attack $victims[5]; $afterNotice = $script:Stats.Streak
    $null = Invoke-Pickup 'signed'; $signed = @($p.Signed)
    Reset-PlayerForLevel
    Write-Step "loot test: 40 damage against a vest leave health/armour $afterHit; silver lock $stillLocked -> $($silver.Lock) with a keycard ($($p.Keycards) left); five silent kills: streak $streak, drops $(($dropped | Group-Object | ForEach-Object { "$($_.Count) $($_.Name)" }) -join ', '); noticed: streak $afterNotice; signed '$($signed -join ',')', on the next floor $(@($p.Signed).Count)"
    if ($afterHit -ne '88/38' -or $stillLocked -ne 2 -or $silver.Lock -ne 0 -or $p.Keycards -ne 0 -or $streak -ne 5 -or 'signed' -notin $dropped -or @($dropped | Where-Object { $_ -eq 'clip_small' }).Count -ne 5 -or
        $afterNotice -ne 0 -or $signed.Count -ne 1 -or @($p.Signed).Count -ne 0) { throw 'loot test failed.' }
    $script:Difficulty = $keepDifficulty; $script:GodMode = $keepGod

    # ---- the newcomers: a bug that is blown up splits, the engineer repairs and takes back, the auditor runs to a terminal and reports ----
    $script:LevelIndex = 0; $script:BonusMap = $null; Start-Level $false $false; $script:Message = $null
    $keepDifficulty = $script:Difficulty; $script:Difficulty = 2; $keepGod = $script:GodMode; $script:GodMode = $true
    Set-TestCamera 24.5 20.5 0
    foreach ($a in @($script:Actors)) { if ($a.Shootable -and -not $a.Def.Inert -and $script:AreaByPlayer[$a.Area]) { $script:ActorAt[$a.TY * $script:MapW + $a.TX] = $null; $a.State = 'gone' } }
    Update-Actors 0.01
    Add-Enemy 'bug' 27 19 4 'stand'; $bug = $script:Actors[$script:Actors.Count - 1]
    Add-Enemy 'bug' 27 23 4 'stand'; $other = $script:Actors[$script:Actors.Count - 1]
    Add-Enemy 'engineer' 28 21 4 'stand'; $engineer = $script:Actors[$script:Actors.Count - 1]
    Add-Enemy 'turret' 26 21 4 'ambush'; $turret = $script:Actors[$script:Actors.Count - 1]
    Add-Enemy 'auditor' 21 15 0 'stand'; $auditor = $script:Actors[$script:Actors.Count - 1]
    Show-PlayFrame; Save-BackBuffer (Join-Path $OutDir 'view-newcomers.png')
    $total = $script:Stats.KillTotal
    $script:KillCause = 'bullet'; Stop-Actor $other; $script:KillCause = $null; $afterBullet = $script:Stats.KillTotal - $total
    $script:KillCause = 'explosion'; Stop-Actor $bug; $script:KillCause = $null; Update-Actors 0.01
    $buglets = @($script:Actors | Where-Object { $_.Kind -eq 'buglet' -and $_.Shootable }).Count
    $turret.Hacked = $true; $null = Invoke-EngineerRepair $engineer; $takenBack = -not $turret.Hacked
    Stop-Actor $turret; for ($f = 0; $f -lt 40; $f++) { Update-Actor $turret 5 }
    $null = Invoke-EngineerRepair $engineer; $repaired = $turret.Shootable -and -not $turret.Corpse
    $heat = $script:Stats.Heat; $level = [int]$script:Stats.Policy
    Start-Attack $auditor
    for ($f = 0; $f -lt 600 -and $auditor.VX -eq 0; $f++) { Update-Actor $auditor 4; Update-Doors 4 }
    Update-Policy 1
    Write-Step "newcomer test: a bug shot leaves $afterBullet, a bug blown up leaves $buglets buglets (kill total +$($script:Stats.KillTotal - $total)); the engineer took the sentry gun back: $takenBack, repaired it: $repaired; the auditor reported after $f steps: policy $level -> $([int]$script:Stats.Policy)"
    if ($afterBullet -ne 0 -or $buglets -ne 2 -or $script:Stats.KillTotal -ne $total + 2 -or -not $takenBack -or -not $repaired -or $auditor.VX -ne 1 -or [int]$script:Stats.Policy -le $level) { throw 'newcomer test failed.' }
    $script:Difficulty = $keepDifficulty; $script:GodMode = $keepGod

    # ---- the taser stuns men and ends machines, silently; a mine waits for the second press ----
    $script:LevelIndex = 0; $script:BonusMap = $null; Start-Level $false $false; $script:Message = $null
    $keepGod = $script:GodMode; $script:GodMode = $true
    Set-TestCamera 24.5 20.5 0
    foreach ($a in @($script:Actors)) { if ($a.Shootable -and -not $a.Def.Inert -and $script:AreaByPlayer[$a.Area]) { $script:ActorAt[$a.TY * $script:MapW + $a.TX] = $null; $a.State = 'gone' } }
    Update-Actors 0.01
    Add-Enemy 'guard' 26 20 0 'stand'; $guard = $script:Actors[$script:Actors.Count - 1]
    $null = Invoke-Pickup 'taser'; $null = Invoke-Pickup 'mine'
    $p = $script:P; $zap = $idle.Clone(); $zap.Weapon = 9; $zap.Fire = $true
    Update-World 1.0 $idle                                          # let go of the trigger first: it counts as held when a floor starts
    $script:MadeNoise = $false; $noise = $false
    for ($f = 0; $f -lt 30; $f++) { Set-TestAim $guard; Show-PlayFrame; Update-World 2.0 $zap; $zap.Weapon = -1; if ($script:MadeNoise) { $noise = $true } }
    $stunned = $guard.Stun -gt 0 -and -not $guard.AttackMode; $battery = [int]$p.Battery
    Show-PlayFrame; Save-BackBuffer (Join-Path $OutDir 'view-taser.png')
    Add-Enemy 'turret' 26 22 4 'ambush'; $turret = $script:Actors[$script:Actors.Count - 1]
    $p.Battery = 100; Set-TestCamera 24.5 22.5 0; Update-World 1.0 $idle      # (one shot per pull of the trigger)
    for ($f = 0; $f -lt 30 -and $turret.Shootable; $f++) { Set-TestAim $turret; Show-PlayFrame; Update-World 2.0 $zap }
    $mineKey = $idle.Clone(); $mineKey.Ability = 7
    Set-TestCamera 27.5 20.5 0; Update-World 1.0 $mineKey
    $armed = @($script:Actors | Where-Object { $_.Kind -eq 'mine' -and $_.Shootable }).Count
    Set-TestCamera 21.5 20.5 0; Update-World 1.0 $mineKey
    for ($f = 0; $f -lt 12; $f++) { Update-World 2.0 $idle }
    Write-Step "weapon test: the taser stunned the guard unnoticed: $stunned (noise: $noise, battery left $battery), switched the sentry gun off: $(-not $turret.Shootable); a mine armed: $armed, $($p.Mines) left, the second press killed the guard next to it: $(-not $guard.Shootable)"
    if (-not $stunned -or $noise -or $battery -gt 80 -or $turret.Shootable -or $armed -ne 1 -or $p.Mines -ne 1 -or $guard.Shootable) { throw 'weapon test failed.' }
    $script:GodMode = $keepGod

    # ---- the console the way people type: Tab completes, Set-Door and Stop-Process do what one would guess ----
    $script:LevelIndex = 0; $script:BonusMap = $null; Start-Level $false $false
    Set-TestCamera 24.5 20.5 0; $script:P.Privilege = 100
    if ($script:Con) { $script:Con.Runspace.Dispose() }; $script:Con = $null
    Open-Console ([int]@($script:TerminalAt.Keys)[0])
    $cases = [ordered]@{ 'Get-En' = 'Get-Enemy '; 'Get-Enemy | Sto' = 'Get-Enemy | Stop-Enemy'; 'Stop-Enemy -W' = 'Stop-Enemy -WhatIf '; 'Get-Door | Set-Door -O' = 'Get-Door | Set-Door -Open '
        'Get-Door | Set-Door -Open ' = 'Get-Door | Set-Door -Open $true'; 'Get-Enemy | sort Dis' = 'Get-Enemy | sort Distance '; 'Get-Door | ? Lo' = 'Get-Door | ? Lock '
        'cat mail' = 'cat mail-0412.eml '; 'Set-ExecutionPolicy Rem' = 'Set-ExecutionPolicy RemoteSigned '; 'Get-Enemy -Kind gu' = 'Get-Enemy -Kind guard ' }
    $wrong = foreach ($case in $cases.GetEnumerator()) {
        $script:Con.Input = $case.Key; $script:Con.Tab = $null; Complete-ConsoleInput
        if ($script:Con.Input -ne $case.Value) { "'$($case.Key)' -> '$($script:Con.Input)' (expected '$($case.Value)')" }
    }
    $script:Con.Input = 'Get-'; $script:Con.Tab = $null; Complete-ConsoleInput; $first = $script:Con.Input; Complete-ConsoleInput; $second = $script:Con.Input
    $script:Con.Input = ''; $script:Con.Tab = $null
    $door = $script:Doors | Where-Object { $_.Lock -eq 0 -and $_.Action -eq 'closed' } | Select-Object -First 1
    $index = [Array]::IndexOf($script:Doors.ToArray(), $door)
    foreach ($line in "Set-Door -Id $index -Open `$true", 'Get-Process | Select-Object -First 1 | Stop-Process -WhatIf', 'Get-Door | Set-Door') { Invoke-ConsoleLine $line }
    $text = ($script:Con.Lines | ForEach-Object { $_[0] }) -join "`n"; Close-Console
    Write-Step "completion test: $($cases.Count) cases, wrong: $(@($wrong).Count); Tab twice on 'Get-': '$first' then '$second'; Set-Door opened door #${index}: $($door.Action)"
    if (@($wrong).Count -or $first -eq $second -or $first -notlike 'Get-*' -or $door.Action -notin 'opening', 'open' -or $text -notmatch 'What if: Performing the operation "Stop-Enemy"' -or $text -notmatch 'say what you want') { throw "completion test failed:`n$($wrong -join "`n")`n$text" }
    $script:Con.Runspace.Dispose(); $script:Con = $null

    # ---- the onboarding: every room has its hint, the terminal's code opens the lever door, the lift goes back to the title ----
    $keepDifficulty = $script:Difficulty; $script:Difficulty = 2; $keepGod = $script:GodMode; $script:GodMode = $true
    $started = Start-Tutorial
    $forced = $script:Difficulty; $seen = [System.Collections.Generic.List[string]]::new()
    foreach ($spot in @(3.5, 8.5), @(11.5, 8.5), @(19.5, 8.5), @(27.5, 8.5), @(35.5, 8.5), @(37.5, 13.5), @(31.5, 14.5), @(23.5, 14.5), @(13.5, 14.5), @(5.5, 14.5)) {
        Set-TestCamera $spot[0] $spot[1] 0; Update-World 1.0 $idle
        if ($script:HintText -and $script:HintText -notin $seen) { $seen.Add($script:HintText) }
        if ($seen.Count -eq 6) { Show-PlayFrame; Save-BackBuffer (Join-Path $OutDir 'view-tutorial.png') }
    }
    $longest = ($seen | ForEach-Object { $script:HintText = $_; @(Get-HintLines).Count } | Measure-Object -Maximum).Maximum
    $lever = $script:Doors | Where-Object { $_.Lock -eq 4 } | Select-Object -First 1
    Set-TestCamera 39.5 13.5 0
    if ($script:Con) { $script:Con.Runspace.Dispose() }; $script:Con = $null
    Open-Console ([int]@($script:TerminalAt.Keys | Sort-Object)[0]); Invoke-ConsoleLine 'cat welcome.txt'; Invoke-ConsoleLine 'Unlock-Door -Code ONBOARD'
    $text = ($script:Con.Lines | ForEach-Object { $_[0] }) -join "`n"; Close-Console
    $script:LevelDone = $true; $script:TutorialKeep = $script:TutorialMode
    Stop-Tutorial
    Write-Step "tutorial test: started $started on difficulty $forced (back to $($script:Difficulty) afterwards), $($seen.Count) hints of $($script:LevelHints.Count) seen, the longest takes $longest lines; the code opened the lever door: $($lever.Unlocked)"
    if (-not $started -or $forced -ne 0 -or $script:Difficulty -ne 2 -or $seen.Count -ne 10 -or $script:LevelHints.Count -ne 10 -or $longest -gt 6 -or -not $lever.Unlocked -or $text -notmatch 'override is ONBOARD') { throw "tutorial test failed:`n$text" }
    $script:Difficulty = $keepDifficulty; $script:GodMode = $keepGod; $script:LevelDone = $false; $script:LevelIndex = 0
    $script:Con.Runspace.Dispose(); $script:Con = $null

    # ---- cheats ----
    Start-Level $false $false
    $p = $script:P
    Invoke-Cheat 'GiveAll'
    if (-not $p.Owned[5] -or $p.Ammo -ne 99 -or -not $p.KeyGold) { throw 'cheat test: GiveAll' }
    Invoke-Cheat 'Ammo'; Invoke-Cheat 'OneHit'
    $target = $script:Actors | Where-Object { $_.Kind -eq 'guard' -and [Math]::Floor($_.X) -eq 7 -and [Math]::Floor($_.Y) -eq 27 }
    Set-TestCamera 7.5 30.5 90
    $p.Weapon = 1; $p.ChosenWeapon = 1
    for ($f = 0; $f -lt 900 -and $target.Shootable; $f++) { Set-TestAim $target; Show-PlayFrame; Update-World 2.0 $(if ($f % 20 -lt 10) { $fire } else { $idle }) }
    if ($target.Shootable -or $p.Ammo -ne 99) { throw "cheat test: one-hit kill / infinite ammo (ammo $($p.Ammo))" }
    $script:GodMode = $false; $p.Health = 100
    Invoke-PlayerDamage 1 $target
    if ($p.Health -ne 0) { throw 'cheat test: one-hit kill must apply to the player as well' }
    $script:GodMode = $true; $script:PlayerDied = $false
    Invoke-Cheat 'Ammo'; Invoke-Cheat 'OneHit'
    foreach ($c in 'R', 'O', 'O', 'T') { Add-CheatKey ([int][char]$c) }          # typed code word toggles god mode
    if ($script:GodMode) { throw 'cheat test: code word ROOT' }
    $script:GodMode = $true
    Write-Step "cheat test ok (GiveAll, infinite ammo, one-hit kill both ways, code word)"

    # ---- stealth: sneaking up on the corridor guard goes unnoticed, walking does not, knives are silent ----
    Start-Level $false $false
    $target = $script:Actors | Where-Object { $_.Kind -eq 'guard' -and [Math]::Floor($_.X) -eq 7 -and [Math]::Floor($_.Y) -eq 27 }
    Set-TestCamera 7.5 30.2 90
    $walk = $idle.Clone(); $walk.Forward = 1; $sneak = $walk.Clone(); $sneak.Sneak = $true
    for ($f = 0; $f -lt 25; $f++) { Update-World 2.0 $sneak }
    $unnoticed = -not $target.AttackMode -and $target.React -le 0
    $dist = [Math]::Round($script:P.Y - $target.Y, 2)
    $script:P.Weapon = 0; $script:P.ChosenWeapon = 0
    $others = @($script:Actors | Where-Object { $_.AttackMode -or $_.React -gt 0 }).Count
    Show-PlayFrame
    for ($f = 0; $f -lt 200 -and $target.Shootable; $f++) { Set-TestAim $target; Show-PlayFrame; Update-World 2.0 $(if ($f % 20 -lt 10) { $fire } else { $idle }) }
    $silentKill = -not $target.Shootable -and @($script:Actors | Where-Object { $_ -ne $target -and ($_.AttackMode -or $_.React -gt 0) }).Count -eq $others
    Start-Level $false $false
    $target = $script:Actors | Where-Object { $_.Kind -eq 'guard' -and [Math]::Floor($_.X) -eq 7 -and [Math]::Floor($_.Y) -eq 27 }
    Set-TestCamera 7.5 30.2 90
    for ($f = 0; $f -lt 12; $f++) { Update-World 2.0 $walk }
    $heard = $target.AttackMode -or $target.React -gt 0
    Write-Step "stealth test: sneaked to $dist tiles unnoticed=$unnoticed, silent knife kill=$silentKill, walking heard=$heard"
    if (-not $unnoticed -or -not $silentKill -or -not $heard) { throw 'stealth test failed.' }

    # ---- new weapons: rocket, flame and throwing knife must each kill the corridor guard ----
    foreach ($wpn in 6, 7, 8) {
        Start-Level $false $false
        Invoke-Cheat 'GiveAll'; $script:InfiniteAmmo = $true
        $target = $script:Actors | Where-Object { $_.Kind -eq 'guard' -and [Math]::Floor($_.X) -eq 7 -and [Math]::Floor($_.Y) -eq 27 }
        Set-TestCamera 7.5 $(if ($wpn -eq 7) { 29.4 } else { 31.5 }) 90
        $script:P.Weapon = $wpn; $script:P.ChosenWeapon = $wpn
        for ($f = 0; $f -lt 400 -and $target.Shootable; $f++) { Set-TestAim $target; Show-PlayFrame; Update-World 2.0 $(if ($f % 30 -lt 20) { $fire } else { $idle }) }
        if ($target.Shootable) { throw "weapon test: $($script:Weapons[$wpn].Name) did not kill the guard." }
    }
    $script:InfiniteAmmo = $false
    Write-Step 'weapon test ok (rocket launcher, flamethrower, throwing knives)'

    # ---- lever doors: shut until the lever is pulled, then open for good ----
    $script:LevelIndex = [Math]::Min(1, $script:MapFiles.Count - 1)
    Start-Level $false $false
    $remote = $script:Doors | Where-Object Lock -eq 4 | Select-Object -First 1
    if ($remote) {
        $di = $script:Doors.IndexOf($remote)
        Invoke-DoorUse $di
        $before = $remote.Action
        Invoke-Lever ([Array]::IndexOf($script:LeverAt, $remote.Channel))
        for ($f = 0; $f -lt 300; $f++) { Update-World 2.0 $idle }
        Write-Step "lever test: door was '$before', is '$($remote.Action)' ten seconds after the lever"
        if ($before -ne 'closed' -or $remote.Action -ne 'open') { throw 'lever test failed.' }
    }
    $script:LevelIndex = 0

    # ---- traps: standing on spikes through a full cycle must hurt; a crusher must block its tile ----
    $script:LevelIndex = [Math]::Min(3, $script:MapFiles.Count - 1)
    Start-Level $false $false
    $spike = $script:Traps | Where-Object Kind -eq 'spikes' | Select-Object -First 1
    $crusher = $script:Traps | Where-Object Kind -eq 'crusher' | Select-Object -First 1
    if ($spike -and $crusher) {
        $script:GodMode = $false; $script:P.Health = 100
        Set-TestCamera ($spike.X + 0.5) ($spike.Y + 0.5) 0
        $blocked = $false
        for ($f = 0; $f -lt 130; $f++) { Update-World 2.0 $idle; if ($script:StaticBlock[$crusher.Y * $script:MapW + $crusher.X]) { $blocked = $true } }
        $script:GodMode = $true
        Write-Step "trap test: spikes left the player at $($script:P.Health) health, crusher blocked its tile: $blocked"
        if ($script:P.Health -ge 100 -or -not $blocked) { throw 'trap test failed.' }
        $script:PlayerDied = $false
    }
    $script:LevelIndex = 0

    # ---- teleporter: step on a pad, arrive on its partner, and do not bounce back ----
    $script:LevelIndex = [Math]::Min(2, $script:MapFiles.Count - 1)
    Start-Level $false $false
    if ($script:Teleporters.Count -ge 2) {
        $pad = $script:Teleporters[0]; $other = $script:Teleporters | Where-Object { $_.Id -eq $pad.Id -and $_ -ne $pad } | Select-Object -First 1
        Set-TestCamera ($pad.X + 0.5) ($pad.Y + 0.5) 0
        for ($f = 0; $f -lt 5; $f++) { Update-World 2.0 $idle }
        $arrived = [Math]::Floor($script:P.X) -eq $other.X -and [Math]::Floor($script:P.Y) -eq $other.Y
        Write-Step "teleporter test: from $($pad.X),$($pad.Y) to $([Math]::Floor($script:P.X)),$([Math]::Floor($script:P.Y)) (partner $($other.X),$($other.Y))"
        if (-not $arrived) { throw 'teleporter test failed.' }
    }
    $script:LevelIndex = 0

    # ---- cracked wall: the kitchen barrel must bring it down ----
    $script:LevelIndex = [Math]::Min(1, $script:MapFiles.Count - 1)
    Start-Level $false $false
    $crack = [Array]::IndexOf($script:Breakable, $true)
    if ($crack -ge 0) {
        $cx = $crack % $script:MapW; $cy = [Math]::Floor($crack / $script:MapW)
        $barrel = $script:Actors | Where-Object { $_.Kind -eq 'barrel' -and [Math]::Abs($_.X - $cx) -lt 2 -and [Math]::Abs($_.Y - $cy) -lt 2 } | Select-Object -First 1
        Invoke-ActorDamage $barrel 100
        for ($f = 0; $f -lt 20; $f++) { Update-World 2.0 $idle }
        Write-Step "cracked wall test: tile $cx,$cy is now $($script:Tiles[$crack]) (0 = open), secrets $($script:Stats.Secrets)/$($script:Stats.SecretTotal)"
        if ($script:Tiles[$crack] -ne 0) { throw 'cracked wall test failed.' }
    }
    $script:LevelIndex = 0

    # ---- window: line of sight must pass through it, not through the wall next to it ----
    $script:LevelIndex = [Math]::Min(1, $script:MapFiles.Count - 1)
    Start-Level $false $false
    $wi = [Array]::IndexOf($script:IsWindow, $true)
    if ($wi -ge 0) {
        $wx = $wi % $script:MapW; $wy = [Math]::Floor($wi / $script:MapW)
        Set-TestCamera ($wx + 0.5) ($wy + 2.5) 90
        $through = Test-LineToPlayer ($wx + 0.5) ($wy - 1.5)
        $blocked = Test-LineToPlayer ($wx + 1.5) ($wy - 1.5)
        Set-TestCamera ($wx + 0.5) ($wy + 1.6) 90
        Show-PlayFrame; Save-BackBuffer (Join-Path $OutDir 'view-0-window.png')
        Write-Step "window test: sight through the window $through, through the wall beside it $(-not $blocked -eq $false)"
        if (-not $through) { throw 'window test failed.' }
    }
    $script:LevelIndex = 0

    # ---- barrels: shooting one must set off its neighbour and hurt whoever stands close ----
    $script:LevelIndex = [Math]::Min(1, $script:MapFiles.Count - 1)
    Start-Level $false $false
    $barrels = @($script:Actors | Where-Object Kind -eq 'barrel')
    if ($barrels.Count -ge 2) {
        $victims = @($script:Actors | Where-Object { $_.Shootable -and -not $_.Def.Inert -and [Math]::Abs($_.X - $barrels[-1].X) -lt 4 -and [Math]::Abs($_.Y - $barrels[-1].Y) -lt 4 })
        $first = $barrels | Where-Object { $b = $_; @($barrels | Where-Object { $_ -ne $b -and [Math]::Abs($_.X - $b.X) -lt 1.6 -and [Math]::Abs($_.Y - $b.Y) -lt 1.6 }).Count } | Select-Object -First 1
        Invoke-ActorDamage $first 100
        for ($f = 0; $f -lt 40; $f++) { Update-World 2.0 $idle }
        $left = @($script:Actors | Where-Object Kind -eq 'barrel').Count
        Write-Step "barrel test: $($barrels.Count) barrels -> $left left, bystanders hurt: $(@($victims | Where-Object { $_.HP -lt $_.Def.HP[$script:Difficulty] }).Count) of $($victims.Count)"
        if (-not $first -or $left -gt $barrels.Count - 2) { throw 'barrel test: no chain reaction.' }
    }
    $script:LevelIndex = 0

    # ---- shield bearer: bullets bounce off the front, not off the back; kamikaze bots blow up ----
    $script:LevelIndex = [Math]::Min(4, $script:MapFiles.Count - 1)
    Start-Level $false $false
    $sb = $script:Actors | Where-Object Kind -eq 'shield' | Select-Object -First 1
    if ($sb) {
        $sb.Dir = 6; $hp = $sb.HP                                    # he faces south
        Set-TestCamera $sb.X ($sb.Y + 2) 90; Invoke-ActorDamage $sb 10 'bullet'; $front = $hp - $sb.HP
        Set-TestCamera $sb.X ($sb.Y - 2) 270; $sb.Dir = 6; $sb.State = 'shield.stand'; Invoke-ActorDamage $sb 10 'bullet'; $back = $hp - $sb.HP - $front
        $bot = $script:Actors | Where-Object Kind -eq 'bot' | Select-Object -First 1
        $script:GodMode = $false; $script:P.Health = 100
        Set-TestCamera ($bot.X + 0.6) ($bot.Y + 0.6) 0; $bot.Active = $true; Start-Attack $bot
        for ($f = 0; $f -lt 30; $f++) { Update-World 2.0 $idle }
        $script:GodMode = $true
        Write-Step "enemy test: shield front damage $front, back damage $back; bot blast left the player at $($script:P.Health) health"
        if ($front -ne 0 -or $back -le 0 -or $script:P.Health -ge 100) { throw 'enemy test failed.' }
        $script:PlayerDied = $false
    }
    $script:LevelIndex = 0

    # ---- a dog must complete its leap (jump1..jump5) and bite ----
    Start-Level $false $false
    $dog = $script:Actors | Where-Object Kind -eq 'dog' | Select-Object -First 1
    Set-TestCamera ($dog.X + 3 * $script:DirDX[$dog.PathDir]) ($dog.Y + 3 * $script:DirDY[$dog.PathDir]) ((($dog.PathDir * 45) + 180) % 360)   # right in its path, face to face
    $script:GodMode = $false; $script:P.Health = 100
    $dogStates = [System.Collections.Generic.List[string]]::new()
    for ($f = 0; $f -lt 400; $f++) { Show-PlayFrame; Update-World 1.0 $idle; if ($dogStates.Count -eq 0 -or $dogStates[-1] -ne $dog.State) { $dogStates.Add($dog.State) } }
    $script:GodMode = $true
    Write-Step "dog test: health $($script:P.Health), states: $(($dogStates | Select-Object -Unique) -join ' > ')"
    if ('dog.jump5' -notin $dogStates) { throw 'dog test: the leap is never completed.' }

    # ---- boss fight (floor 4): war machine -> rockets -> pilot, fought with both special weapons ----
    $script:LevelIndex = [Math]::Min(3, $script:MapFiles.Count - 1)
    Start-Level $false $false
    $p = $script:P
    $p.Owned = (New-OwnedList $true); $p.Ammo = 99; $p.Charges = 40
    $mech = $script:Actors | Where-Object Kind -eq 'uber' | Select-Object -First 1
    if ($mech) {
        Set-TestCamera $mech.X ($mech.Y - 5) 270
        $sawRocket = $false; $sawPilot = $false; $shot = $false
        for ($f = 0; $f -lt 2500; $f++) {
            $in = $fire.Clone(); $in.Fire = ($f % 12 -lt 6)
            if ($f -eq 0) { $in.Weapon = 4 } elseif ($p.Ammo -lt 4 -and $p.Weapon -ne 5) { $in.Weapon = 5 }
            $foe = $script:Actors | Where-Object { $_.Kind -in 'uber', 'pilot' -and $_.Shootable } | Select-Object -First 1
            if ($foe) { Set-TestAim $foe }                            # the pilot is quick: keep him in the sights
            Show-PlayFrame; Update-World 2.0 $in
            if (@($script:Actors | Where-Object Kind -eq 'rocket').Count) { $sawRocket = $true }
            if (@($script:Actors | Where-Object Kind -eq 'pilot').Count) { $sawPilot = $true }
            if (-not $shot -and $script:BeamFlash -gt 0) { Show-PlayFrame; Save-BackBuffer (Join-Path $OutDir 'view-0-beam.png'); $shot = $true }
            if ($f -eq 300) { Save-BackBuffer (Join-Path $OutDir 'view-0-bossfight.png') }
            if ($sawPilot -and -not @($script:Actors | Where-Object { $_.Kind -in 'uber', 'pilot' -and $_.Shootable }).Count) { break }
        }
        Write-Step "boss test: after $f frames - rocket seen: $sawRocket, pilot seen: $sawPilot, kills $($script:Stats.Kills)"
        if (-not $sawRocket -or -not $sawPilot -or $f -ge 2500) {
            $left = @($script:Actors | Where-Object { $_.Kind -in 'uber', 'pilot' } | ForEach-Object { "$($_.Kind) $($_.State) hp=$($_.HP) at $([Math]::Round($_.X,1)),$([Math]::Round($_.Y,1)) vis=$($_.Visible)" }) -join '; '
            throw "boss test failed. weapon=$($p.Weapon) ammo=$($p.Ammo) charges=$($p.Charges) player=$([Math]::Round($p.X,1)),$([Math]::Round($p.Y,1)) angle=$($p.Angle) | $left"
        }
        Show-PlayFrame; Save-BackBuffer (Join-Path $OutDir 'view-0-bossdead.png')
    }
    $script:LevelIndex = 0

    # ---- scripted play: walk, turn, shoot, use - everything that could throw ----
    Start-Level $false $false
    $p = $script:P
    $p.Owned = (New-OwnedList $true); $p.Ammo = 99; $p.Charges = 3
    $sw.Restart()
    for ($f = 0; $f -lt 900; $f++) {
        $in = @{ Forward = 1; Strafe = 0; Turn = 0; MouseTurn = 0.0; Run = ($f % 200 -gt 100); Fire = ($f % 40 -lt 25); Use = ($f % 30 -eq 0); Weapon = -1 }
        if ($f % 150 -eq 0) { $in.Weapon = [int]($f / 150) % 6 }
        if ($f % 90 -gt 70) { $in.Turn = 1 }
        if ($f -eq 300) { Set-TestCamera 20.5 19.5 0 }               # into the hub: lots of company
        if ($f -eq 600) { Set-TestCamera 34.5 9.5 90; $script:P.KeyGold = $true }   # face the war machine
        Update-World 2.0 $in
        if ($f % 10 -eq 0) { Show-PlayFrame }
    }
    Write-Step ('simulation: 900 frames in {0:0.0}s, kills {1}/{2}, actors {3}' -f $sw.Elapsed.TotalSeconds, $script:Stats.Kills, $script:Stats.KillTotal, $script:Actors.Count)
    Show-PlayFrame; Save-BackBuffer (Join-Path $OutDir 'view-11-after-sim.png')

    # ---- save / load round trip ----
    $before = "$($p.X);$($p.Y);$($p.Ammo);$($script:Stats.Kills);$($script:Actors.Count);$(($script:Tiles | Measure-Object -Sum).Sum)"
    Save-Game
    $ok = Restore-Game
    $p = $script:P
    $after = "$($p.X);$($p.Y);$($p.Ammo);$($script:Stats.Kills);$($script:Actors.Count);$(($script:Tiles | Measure-Object -Sum).Sum)"
    if (-not $ok -or $before -ne $after) { throw "savegame test failed: '$before' <> '$after' ($($script:Message))" }
    for ($f = 0; $f -lt 60; $f++) { Update-World 2.0 @{ Forward = 0; Strafe = 0; Turn = 1; MouseTurn = 0.0; Run = $false; Fire = $true; Use = $false; Weapon = -1 } }
    Show-PlayFrame; Save-BackBuffer (Join-Path $OutDir 'view-12-after-load.png')
    Write-Step 'savegame round trip ok'

    $stateBeforeBadLoad = "$($script:LevelIndex);$($script:P.X);$($script:P.Y);$($script:Actors.Count)"
    $badSave = Get-Content -LiteralPath (Get-SavePath) -Raw | ConvertFrom-Json -AsHashtable
    $badSave.Actors[0].TX = -1
    $badSave | ConvertTo-Json -Depth 6 -Compress | Set-Content -LiteralPath (Get-SavePath) -Encoding utf8
    $badLoad = Restore-Game
    $stateAfterBadLoad = "$($script:LevelIndex);$($script:P.X);$($script:P.Y);$($script:Actors.Count)"
    if ($badLoad -or $stateBeforeBadLoad -ne $stateAfterBadLoad) { throw 'save validation test failed: a malformed save changed the running game.' }
    Write-Step 'save validation test: a malformed save is rejected before changing the running game'

    # ---- every floor: load, look around, let the world run for a while ----
    $script:StatesSeen = @()
    $floors = @(for ($i = 0; $i -lt $script:MapFiles.Count; $i++) { , @($i, $null) })
    foreach ($b in Get-ChildItem (Split-Path $script:MapFiles[0]) -Filter 'bonus*.map') { $floors += , @(([int]($b.BaseName -replace '\D') - 1), $b.FullName) }
    for ($fi = 0; $fi -lt $floors.Count; $fi++) {
        $li = $floors[$fi][0]; $script:LevelIndex = $li; $script:BonusMap = $floors[$fi][1]
        Start-Level $true $true
        $tag = if ($script:BonusMap) { "bonus-$($li + 1)" } else { "floor-$($li + 1)" }
        Show-PlayFrame; Save-BackBuffer (Join-Path $OutDir "$tag-start.png")
        # soak: every door open, constant noise - the whole floor wakes up and comes for the (immortal) player
        $seen = @{}
        for ($f = 0; $f -lt 1500; $f++) {
            if ($f % 100 -eq 0) { for ($d = 0; $d -lt $script:Doors.Count; $d++) { Open-Door $d } }
            $in = $idle.Clone(); $in.Turn = 1; $in.Fire = ($f % 30 -lt 5)
            Update-World 2.0 $in
            $script:MadeNoise = $true
            if ($f % 5 -eq 0) { Show-PlayFrame; foreach ($a in $script:Actors) { $seen[$a.State] = $true } }
        }
        # bosses only react to what they see: visit each one and fight it out with the Force-Blaster
        $p = $script:P
        $p.Owned = (New-OwnedList $true); $p.Charges = 500; $p.Weapon = 5; $p.ChosenWeapon = 5
        foreach ($b in @($script:Actors | Where-Object { $_.Kind -in 'boss', 'uber' -and $_.Shootable })) {
            $spot = $null
            foreach ($dist in 3, 2, 4, 1) {
                foreach ($dir in 0, 2, 4, 6) {
                    $sx = [Math]::Floor($b.X) + $script:DirDX[$dir] * $dist; $sy = [Math]::Floor($b.Y) + $script:DirDY[$dir] * $dist
                    $i = $sy * $script:MapW + $sx
                    if (-not $spot -and $script:Tiles[$i] -eq 0 -and -not $script:StaticBlock[$i] -and $script:AreaOf[$i] -eq $b.Area) { $spot = @(($sx + 0.5), ($sy + 0.5)) }
                }
            }
            if (-not $spot) { continue }
            $angle = [Math]::Atan2(- ($b.Y - $spot[1]), $b.X - $spot[0]) * 180 / [Math]::PI
            Set-TestCamera $spot[0] $spot[1] (($angle + 360) % 360)
            for ($f = 0; $f -lt 1500; $f++) {
                $in = $idle.Clone(); $in.Fire = ($f % 60 -lt 30 -and $f -gt 200)
                Show-PlayFrame; Update-World 2.0 $in
                foreach ($a in $script:Actors) { $seen[$a.State] = $true }
                if ($f -gt 200 -and -not @($script:Actors | Where-Object { $_.Kind -in 'boss', 'uber', 'pilot' -and $_.Shootable -and $_.Area -eq $b.Area }).Count) { $f = [Math]::Max($f, 1400) }
            }
        }
        Save-BackBuffer (Join-Path $OutDir "$tag-soak.png")
        $script:StatesSeen += @($seen.Keys)
        Write-Step ("$tag '{1}': {2}x{3}, {4} enemies, {5} doors, {6} secrets" -f ($li + 1), $script:LevelName, $script:MapW, $script:MapH, $script:Stats.KillTotal, $script:Doors.Count, $script:Stats.SecretTotal)
    }
    $script:LevelIndex = 0; $script:BonusMap = $null
    $never = @($script:States.Keys | Where-Object { $_ -notin $script:StatesSeen } | Sort-Object)
    Write-Step "states visited: $(@($script:StatesSeen | Sort-Object -Unique).Count) of $($script:States.Count); never seen: $($never -join ', ')"

    # ---- demos: what the bot records must play back to exactly the same end state ----
    $demoFile = Join-Path $OutDir 'bot-demo.json'
    Export-AttractDemo $demoFile 12 1
    $script:GodMode = $false
    if (-not (Start-DemoPlayback $demoFile)) { throw "demo test: $($script:Message)" }
    while ($null -ne ($frame = Get-DemoFrame)) { Update-View; Update-World $frame.Tics $frame.In }
    $sync = Test-DemoInSync
    Write-Step "demo test: playback of $($script:Playback.Frames.Count) frames ended in sync with the recording: $sync"
    $script:Playback = $null; $script:GodMode = $true; $script:Difficulty = 1; $script:PlayerDied = $false
    if (-not $sync) { throw 'demo test failed: playback diverged from the recording.' }

    # ---- reinforcements: harder difficulties put more enemies on the floor ----
    $counts = foreach ($d in 0, 2, 3) { $script:Difficulty = $d; $script:LevelIndex = 0; $script:BonusMap = $null; Start-Level $false $false; $script:Stats.KillTotal }
    $script:Difficulty = 1
    Write-Step "reinforcement test: floor 1 has $($counts -join ' / ') enemies on difficulty 1 / 3 / 4"
    if (-not ($counts[0] -lt $counts[1] -and $counts[1] -lt $counts[2])) { throw 'reinforcement test failed.' }

    # ---- secret exit: floor 2 -> bonus floor -> floor 3 ----
    if (Test-Path (Join-Path (Split-Path $script:MapFiles[0]) 'bonus2.map')) {
        $script:LevelIndex = 1; $script:BonusMap = $null
        Start-Level $false $false
        $script:SecretExit = $true; Complete-Level
        $toBonus = $script:Result.ToBonus
        $script:BonusMap = $script:Result.BonusPath; Start-Level $true $true
        $name = $script:LevelName
        Save-Game; $null = Restore-Game
        $restored = $script:BonusMap -and $script:LevelName -eq $name
        Complete-Level
        Write-Step "secret exit test: to bonus=$toBonus ('$name'), save/load on the bonus floor=$restored, campaign goes on afterwards=$(-not $script:Result.Last -and -not $script:Result.ToBonus)"
        if (-not $toBonus -or -not $restored -or $script:Result.Last -or $script:Result.ToBonus) { throw 'secret exit test failed.' }
        $script:BonusMap = $null; $script:LevelIndex = 0; $script:Mode = 'play'
    }

    # ---- level completion and speedrun records ----
    $script:Speedrun = $true
    Remove-Item -LiteralPath (Join-Path $script:SaveDir 'speedrun.json') -ErrorAction SilentlyContinue
    Start-Level $false $false; $script:P.Cheated = $false
    $script:Stats.Tics = 70 * 95.5; Complete-Level
    $first = $script:Result.Previous
    Show-DoneScreen; Save-BackBuffer (Join-Path $OutDir 'screen-done.png')
    Start-Level $false $false; $script:P.Cheated = $false
    $script:Stats.Tics = 70 * 80.0; Complete-Level
    $rec = (Get-SpeedrunData).Floors
    Write-Step "speedrun test: first previous=$first, second previous=$($script:Result.Previous), stored best=$(@($rec.Values)[0])"
    if ($first -ne 0 -or $script:Result.Previous -ne 95.5 -or @($rec.Values)[0] -ne 80) { throw 'speedrun test failed.' }
    $script:Mode = 'play'

    # ---- save slots and the autosave ----
    $script:LevelIndex = 0; $script:BonusMap = $null
    Start-Level $false $false
    Save-Game '2'
    $script:LevelIndex = 1; Start-Level $true $true                   # "arriving by lift" -> autosave
    $slots = @(Get-SaveList | ForEach-Object { $_.Slot }) -join ','
    $ok = (Restore-Game '2') -and $script:LevelIndex -eq 0
    Write-Step "save slot test: saves found: $slots; slot 2 brought us back to floor $($script:LevelIndex + 1)"
    if (-not $ok -or $slots -notmatch 'auto' -or $slots -notmatch '2') { throw 'save slot test failed.' }

    # ---- game pad: the XInput bridge must load and answer (with or without a pad plugged in) ----
    if ($script:Pad) {
        $state = $script:Pad::Read(0)
        Update-Gamepad; $in = $idle.Clone(); Add-GamepadInput $in
        Write-Step "game pad test: XInput bridge loaded, pad connected: $([bool]$state)"
    }
    else { Write-Step 'game pad test: bridge not available (skipped)' }

    # ---- network: the host against two scripted guests (relay, requests, kick, ban), then a guest against a scripted host ----
    $port = 27631; $keepGod = $script:GodMode; $script:GodMode = $false
    if (-not $script:KeyHit) { $script:KeyHit = [System.Collections.Generic.Queue[int]]::new() }
    Remove-Item -LiteralPath (Join-Path $script:SaveDir 'banned.json') -ErrorAction SilentlyContinue
    Initialize-Network 'host' 'coop' '' $port 3 'Boss'
    $anna = [System.Net.Sockets.TcpClient]::new('127.0.0.1', $port); $bob = $null; $carl = $null
    try {
        Start-Sleep -Milliseconds 100; Update-Network 1.0
        $hello = Read-NetTestLines $anna
        $bob = [System.Net.Sockets.TcpClient]::new('127.0.0.1', $port)
        Start-Sleep -Milliseconds 100; Update-Network 1.0; $null = Read-NetTestLines $bob
        Send-NetTestLines $anna 'V|2|Anna'; Send-NetTestLines $bob 'V|2|Anna'                 # two of the same name: the second gets a number
        Update-Network 1.0
        $carl = [System.Net.Sockets.TcpClient]::new('127.0.0.1', $port)                      # a fourth player in a game for three
        Start-Sleep -Milliseconds 100; Update-Network 1.0
        $full = Read-NetTestLines $carl
        $names = ($script:Net.Guests | ForEach-Object Name) -join ','
        $script:LevelIndex = 0; $script:BonusMap = $null; $script:Difficulty = 1
        Start-Level $false $false
        Update-Network 1.0
        $go = @(Read-NetTestLines $anna | Where-Object { $_ -like 'G|*' })[0]
        if ($hello -notcontains 'V|2|coop|1' -or $go -notlike 'G|1|0||1|*|1|0:Boss:*,1:Anna:*,2:Anna3:*' -or $full -notlike 'N|The game is full*') { throw "network test failed: handshake '$hello' / '$go' / '$full'." }
        $victim = $script:Actors | Where-Object { $_.Shootable -and -not $_.Def.Inert -and $_.Kind -ne 'peer' } | Select-Object -First 1
        $door = $script:Doors | Where-Object { $_.Lock -eq 0 } | Select-Object -First 1
        $health = $script:P.Health
        Send-NetTestLines $bob 'R|1'
        $oldX = $script:Net.Players[1].Proxy.X; $oldHP = $victim.HP
        Send-NetTestLines $anna 'R|1', "M|9|-1|$($victim.Y)|180|4|100|0|$($victim.Area)", "D|$($victim.NetId)|406|blast"
        Update-Network 1.0
        if ($script:Net.Players[1].Proxy.X -ne $oldX -or $victim.HP -ne $oldHP) { throw 'network test failed: the host accepted invalid guest state or damage.' }
        if ($door.Vertical) { $useX = $door.X - 0.5; $useY = $door.Y + 0.5; $useDX = 1; $useDY = 0 }
        else { $useX = $door.X + 0.5; $useY = $door.Y - 0.5; $useDX = 0; $useDY = 1 }
        Send-NetTestLines $anna "M|9|$($victim.X)|$($victim.Y)|180|4|100|0|$($victim.Area)", "D|$($victim.NetId)|405|blast", "M|9|$useX|$useY|180|4|100|0|0", "U|$($door.X)|$($door.Y)|$useDX|$useDY"
        Update-Network 1.0
        # a look at the partners: two tiles away, walking past
        Set-TestCamera ($victim.X + 3) $victim.Y 180
        foreach ($pl in $script:Net.Players.Values) { $pl.Ghost.X = $victim.X + 1; $pl.Ghost.Y = $victim.Y - 1.2 + 0.8 * $pl.Slot; $pl.Ghost.State = "peer$($pl.Slot).w2"; $pl.Ghost.Dir = 2 }
        Show-PlayFrame; Save-BackBuffer (Join-Path $OutDir 'view-network-partner.png')
        Enter-PeerContext 1; Invoke-PlayerDamage 10 $null; Exit-PeerContext                  # an enemy hits Anna, not the host
        for ($i = 0; $i -lt 6; $i++) { Update-World 2.0 $idle; Update-Network 2.0 }
        $lines = Read-NetTestLines $anna; $heard = Read-NetTestLines $bob
        $snap = @($lines | Where-Object { $_ -like "Z|*" -and $_ -like "*$($victim.NetId),$($victim.Kind).die*" }).Count
        $relayed = @($heard | Where-Object { $_ -like "M|1|$($victim.X)|*" }).Count
        Write-Step "network test (host): guests '$names', a fourth was told '$full'; Anna at $($script:Net.Players[1].Proxy.X),$($script:Net.Players[1].Proxy.Y) killed the $($victim.Kind): $(-not $victim.Shootable); door $($door.Action); Bob heard of her $relayed time(s); $snap snapshots show the death"
        if ($victim.Shootable -or $door.Action -eq 'closed' -or -not $snap -or -not $relayed -or $lines -notcontains "S|$($victim.Def.Points)" -or $lines -notcontains 'H|10|0' -or
            $heard -contains 'H|10|0' -or $script:P.Health -ne $health -or @($lines | Where-Object { $_ -like 'M|0|*' }).Count -eq 0) { throw 'network test failed on the host side.' }

        # the admin panel: kick Bob, ban Anna - and Anna's address is turned away when it comes back
        Open-NetPanel
        $script:Net.Panel.Row = 1; $script:Net.Bans.Add('203.0.113.7')
        Show-PlayFrame; Show-NetPanel; Save-BackBuffer (Join-Path $OutDir 'view-network-panel.png')
        $null = $script:Net.Bans.Remove('203.0.113.7')
        Update-NetPanel @($script:VK.K)
        Update-Network 1.0                                                                    # the others are told on the next frame
        $kicked = Read-NetTestLines $bob; $told = Read-NetTestLines $anna
        $script:Net.Panel.Row = 0; Update-NetPanel @($script:VK.B)
        $banned = Read-NetTestLines $anna
        $back = [System.Net.Sockets.TcpClient]::new('127.0.0.1', $port); Start-Sleep -Milliseconds 100; Update-Network 1.0
        $refused = Read-NetTestLines $back; $back.Dispose()
        $panel = (Get-NetPanelLines | ForEach-Object { $_[0] }) -join "`n"
        Update-NetPanel @($script:VK.U)                                                       # ... and lifted again
        Write-Step "network test (admin): Bob got '$kicked', Anna heard '$(@($told | Where-Object { $_ -like 'O|*' }) -join ' ')', then got '$banned'; her address came back to '$refused'; bans now: $($script:Net.Bans.Count)"
        if ($kicked -notcontains 'N|kicked by the host' -or -not ($told -like 'O|2|*') -or $banned -notcontains 'N|banned by the host' -or $refused -notlike 'N|You are banned*' -or
            $panel -notmatch '127\.0\.0\.1' -or $script:Net.Bans.Count -ne 0 -or $script:Net.Guests.Count -ne 0) { throw 'network test failed in the admin panel.' }
        Set-Mode 'play'
    }
    finally { foreach ($c in $anna, $bob, $carl) { if ($c) { $c.Dispose() } }; Stop-Network }

    $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, $port + 1); $listener.Start()
    Initialize-Network 'client' 'coop' '127.0.0.1' ($port + 1) 4 'Dora'
    $server = $null
    try {
        for ($i = 0; $i -lt 40 -and -not $script:Net.Connected; $i++) { Update-Network 1.0; Start-Sleep -Milliseconds 50 }
        $server = $listener.AcceptTcpClient()
        Send-NetTestLines $server 'V|2|duel|2', "G|7|0||2|4711|0|0|$(Get-MapHash $script:MapFiles[0])|2|0:Boss:3.5:35.5,1:Anna:5.5:33.5,2:Dora:7.5:27.5"
        Update-Network 1.0
        $enemies = @($script:Actors | Where-Object { -not $_.Def.Inert -and $_.Kind -ne 'peer' }).Count
        $health = $script:P.Health; $spot = "$($script:P.X),$($script:P.Y)"
        Send-NetTestLines $server 'Z|0|0|0||900,rocket.fly,5.5,5.5,0,4|', 'H|10|P1', "M|0|$($script:P.X + 1)|$($script:P.Y)|90|8|0|0|0", 'M|1|6.5|33.5|0|0|77|0|0', 'C|0:2,1:0,2:1'
        Update-Network 1.0
        for ($i = 0; $i -lt 4; $i++) { Update-View; Update-World 2.0 $idle; Update-Network 2.0 }
        $hud = Get-NetHudText
        $states = "$($script:Net.Players[0].Ghost.State) / Anna at $([Math]::Round($script:Net.Players[1].Ghost.NX, 1)) with $($script:Net.Players[1].Health)"
        Send-NetTestLines $server 'O|1|kicked by the host'; Update-Network 1.0
        $lines = Read-NetTestLines $server
        $mapName = (Get-NetMapName 'bonus2.map') -eq 'bonus2.map' -and $(try { $null = Get-NetMapName '..\..\saves\settings.map'; $false } catch { $true })      # a map name from the host stays a name
        Write-Step "network test (guest): slot $($script:Net.Slot) at $spot, mode $($script:Net.Mode), seed $($script:LevelSeed), $enemies monsters left, health $health -> $($script:P.Health), ghosts: $states; '$hud'; after Anna left: $($script:Net.Players.Count) other player; a path as map name is refused: $mapName"
        if (-not $mapName -or -not $script:NetClient -or $script:Net.Mode -ne 'duel' -or $script:Net.Slot -ne 2 -or $spot -ne '7.5,27.5' -or $script:LevelSeed -ne 4711 -or $enemies -ne 0 -or
            -not $script:Net.ById[900] -or $script:P.Health -ge $health -or $script:Net.Players[0].Ghost.State -notlike 'peer0.d*' -or $states -notlike '*6.5 with 77' -or
            $hud -notlike 'FRAGS*Boss 2*you 1*' -or $script:Net.Players.Count -ne 1 -or $lines -notcontains 'V|2|Dora' -or $lines -notcontains 'R|7') { throw 'network test failed on the guest side.' }
        Send-NetTestLines $server 'N|kicked by the host'; Update-Network 1.0
        if (-not $script:Net.Refused -or $script:Net.Connected) { throw 'network test failed: a kicked guest must stay away.' }
    }
    finally { if ($server) { $server.Dispose() }; Stop-Network; $listener.Stop() }
    $script:GodMode = $keepGod; $script:Difficulty = 1; $script:PlayerDied = $false

    # ---- the dungeon: every seed must give a valid floor, the same one each time, and a recorded run must verify ----
    $sizes = foreach ($seed in 20260918, 20260919, 1, 4711, 99999999) {
        $first = Get-Content -LiteralPath (New-DungeonMap $seed) -Raw
        if ($first -ne (Get-Content -LiteralPath (New-DungeonMap $seed) -Raw)) { throw "dungeon test failed: seed $seed gives two different floors." }
        Initialize-Level (Get-DungeonPath $seed)                   # throws on a door without walls, a missing start ...
        "$($script:Stats.KillTotal) enemies/$($script:Doors.Count) doors"
    }
    $script:GodMode = $false; $script:Difficulty = 0
    $null = Start-Dungeon 20260918
    Reset-Bot
    for ($f = 0; $f -lt 700 -and -not $script:PlayerDied -and -not $script:LevelDone; $f++) { Update-View; $in = Get-BotInput $f; Add-DemoFrame 2.0 $in; Update-World 2.0 $in }
    $kills = $script:Stats.Kills
    $proof = Join-Path $script:SaveDir (Save-DungeonRun $false)
    $valid = Test-DemoFile $proof
    $tampered = Get-Content -LiteralPath $proof -Raw | ConvertFrom-Json -AsHashtable
    $tampered.End.Kills = [int]$tampered.End.Kills + 3            # "I killed three more, honest"
    $fake = Join-Path $OutDir 'dungeon-fake.json'; $tampered | ConvertTo-Json -Depth 4 -Compress | Set-Content -LiteralPath $fake
    $caught = -not (Test-DemoFile $fake)
    $tampered.Game = '0.9.0'                                          # ... and one that an older game recorded is told apart from a doctored one
    $stale = Join-Path $OutDir 'dungeon-stale.json'; $tampered | ConvertTo-Json -Depth 4 -Compress | Set-Content -LiteralPath $stale
    $blamed = -not (Test-DemoFile $stale) -and $script:DemoVerdict -like '*recorded with POLF 3D 0.9.0, this is *'
    $stamped = (Get-Content -LiteralPath $proof -Raw | ConvertFrom-Json -AsHashtable).Game -eq $script:PolfVersion
    Remove-Item -LiteralPath $proof, $fake, $stale -ErrorAction SilentlyContinue
    Write-Step "dungeon test: $($sizes -join ', '); the bot's run ($kills kills) verifies: $valid and names the version: $stamped; a doctored copy is rejected: $caught; an old version's copy is blamed on the version: $blamed"
    if (-not $valid -or -not $caught -or -not $stamped -or -not $blamed) { throw 'dungeon test failed.' }
    Stop-Dungeon; $script:GodMode = $true; $script:Difficulty = 1; $script:PlayerDied = $false; $script:Playback = $null

    # ---- terminal mode: the frame buffer as half-block characters ----
    $termClass = Import-CSharpClass 'src/Terminal.cs' 'PolfTerminal'
    $script:LevelIndex = 0; $script:BonusMap = $null; Start-Level $false $false; Set-TestCamera 20.5 24.5 45; Update-View
    $ansi = [System.Text.StringBuilder]::new()
    $termClass::Ansi($script:FB, $script:ViewW, $script:ViewH, 100, 31, 2, 0, $ansi)
    $text = $ansi.ToString(); $rowsOut = $text.Split("`n").Count - 1; $cells = ($text.ToCharArray() | Where-Object { $_ -eq [char]0x2580 }).Count
    Write-Step "terminal test: $rowsOut rows, $cells half-block cells, $([int]($text.Length / 1024)) KB for one frame"
    if ($rowsOut -ne 31 -or $cells -ne 3100 -or $text -notmatch '\e\[38;2;\d+;\d+;\d+m') { throw 'terminal test failed.' }

    # ---- the mixer: open the sound device, play two sounds over a music loop, close (skipped without a device) ----
    $mixer = Import-CSharpClass 'src/Mixer.cs' 'PolfMixer'
    if ($mixer -and $mixer::Open()) {
        $tone = [byte[]]::new(11025); for ($i = 0; $i -lt $tone.Length; $i++) { $tone[$i] = if (($i % 50) -lt 25) { 131 } else { 125 } }      # a very quiet second of 220 Hz
        $id = $mixer::Load($tone, 0, $tone.Length, 8, 11025)
        $mixer::MusicVolume = 0.02; $mixer::SetMusic($id)
        $mixer::Play($id, 0.05, 0.0, 5); $mixer::Play($id, 0.0, 0.05, 5)
        Start-Sleep -Milliseconds 400
        $seconds = $mixer::Seconds($id)
        $mixer::Close()
        Write-Step "mixer test: device opened, a $([Math]::Round($seconds, 2)) s sample played left, right and as a music loop, device closed"
        if ([Math]::Abs($seconds - 1.0) -gt 0.01) { throw 'mixer test failed.' }
    }
    else { Write-Step 'mixer test: no sound device (skipped)' }

    # ---- music: every style must render, stay within 16 bits and differ from the others ----
    $lengths = foreach ($track in 0, 1, 2, 3, 4, 5, $script:MUSIC_BONUS, $script:MUSIC_ENDING) {
        $wav = Join-Path $OutDir "music-$track.wav"
        New-MusicTrack $track $wav
        $bytes = [System.IO.File]::ReadAllBytes($wav)
        $samples = [int16[]]::new(($bytes.Length - 44) / 2); [Buffer]::BlockCopy($bytes, 44, $samples, 0, $samples.Length * 2)
        $peak = 0; for ($i = 0; $i -lt $samples.Length; $i += 5) { $v = [Math]::Abs([int]$samples[$i]); if ($v -gt $peak) { $peak = $v } }
        if ($peak -lt 4000 -or $peak -gt 32000) { throw "music test failed: track $track peaks at $peak." }
        Remove-Item -LiteralPath $wav
        "$(Get-MusicStyle $track) $([int]($samples.Length / $script:MUSIC_RATE))s"
    }
    Write-Step "music test: $($lengths -join ', ')"

    # ---- the epilogue: it scrolls, it can be hurried and skipped, and it ends on the title screen ----
    $script:LevelIndex = $script:MapFiles.Count - 1; $script:BonusMap = $null; Start-Level $false $false
    Start-Ending
    $none = [int[]]@()
    for ($f = 0; $f -lt 40; $f++) { $script:ModeTics += 70; Update-Ending 70 $none }
    $middle = $script:Ending.Scroll / $script:Ending.Total
    Show-Ending; Save-BackBuffer (Join-Path $OutDir 'screen-ending.png')
    $terminalRows = @(Get-EndingScreen | Where-Object { $_ }).Count
    Update-Ending 1 ([int[]]@(13)); $skipped = $script:Ending.Done
    Update-Ending 200 $none; Show-Ending; Save-BackBuffer (Join-Path $OutDir 'screen-ending-card.png')
    Update-Ending 1 ([int[]]@(13))
    Write-Step "ending test: $($script:EndingLines.Count) lines, $([int]($script:Ending.Total / $script:ENDING_SPEED / 70)) s at reading speed; after 40 s at $([int]($middle * 100)) %, $terminalRows rows in a terminal; Enter skips: $skipped; then mode '$($script:Mode)'"
    if ($middle -lt 0.3 -or $middle -gt 0.7 -or $terminalRows -lt 8 -or -not $skipped -or $script:Mode -ne 'title') { throw 'ending test failed.' }
    foreach ($line in $script:EndingLines) { if ($line[0].Length -gt 84) { throw "ending test failed: the line '$($line[0])' is too long for the screen." } }

    # ---- GIF export: three frames in, three frames out - read back by a decoder that is not ours (GDI+) ----
    $pictures = foreach ($n in 0..2) { $px = [int[]]::new(32 * 20); for ($i = 0; $i -lt $px.Length; $i++) { $px[$i] = (255 -shl 24) -bor (($i * 7 + $n * 90) -band 255) -shl 8 -bor ($n * 100) }; , $px }
    $gifPath = Join-Path $OutDir 'test.gif'
    Export-Gif $gifPath @($pictures) 32 20 2
    $gif = [System.Drawing.Image]::FromFile($gifPath)
    $count = $gif.GetFrameCount([System.Drawing.Imaging.FrameDimension]::new($gif.FrameDimensionsList[0])); $size = "$($gif.Width)x$($gif.Height)"; $gif.Dispose()
    Write-Step "gif test: $count frames of $size, $((Get-Item $gifPath).Length) bytes"
    if ($count -ne 3 -or $size -ne '64x40') { throw 'gif test failed.' }

    # ---- the floor as a test suite ----
    Remove-Item -LiteralPath (Get-AchievementPath) -ErrorAction SilentlyContinue
    $script:LevelIndex = 0; $script:BonusMap = $null; Start-Level $false $false
    $keepCheat = $script:P.Cheated; $script:P.Cheated = $false
    $script:Stats.Tics = 70 * 100; $script:Stats.Secrets = $script:Stats.SecretTotal; $script:Run.Shots = 3
    $first = Invoke-FloorTests; $second = Invoke-FloorTests
    $script:Result = @{ Last = $false; Exact = 100.0; Previous = 0; Kills = 0; Secrets = 100; Treasures = 0; Bonus = 10000; Tests = $first; Transcript = @{ Verdict = 'Completed. No findings. Next maintenance window: the floor above.' } }
    Show-DoneScreen; Save-BackBuffer (Join-Path $OutDir 'screen-tests.png')
    Write-Step "achievement test: passed $($first.Passed), failed $($first.Failed), new the first time: $($first.New -join ','); new the second time: $($second.New.Count); on record: $(Get-AchievementCount)"
    if ($first.Passed -ne 7 -or $first.Failed -ne 3 -or $first.New.Count -ne 7 -or $second.New.Count -ne 0 -or (Get-AchievementCount) -notlike '7 of *' -or 'pacifist' -in $first.New -or 'par' -notin $first.New) { throw 'achievement test failed.' }
    $script:P.Cheated = $keepCheat
    Remove-Item -LiteralPath (Get-AchievementPath) -ErrorAction SilentlyContinue

    # ---- the transcript of a floor ----
    $script:LevelIndex = 0; $script:BonusMap = $null; Start-Level $false $false
    $victim = $script:Actors | Where-Object { $_.Shootable -and -not $_.Def.Inert } | Select-Object -First 1
    Invoke-ActorDamage $victim 999 'bullet'; $null = Invoke-Pickup 'mgun'; $script:Stats.Tics = 4321
    $done = Stop-RunTranscript $true
    $log = Get-Content -LiteralPath $done.File
    Write-Step "transcript test: $($log.Count) lines in $(Split-Path $done.File -Leaf); verdict: $($done.Verdict)"
    if ($log[1] -ne 'PowerShell transcript start' -or -not ($log -match 'Stop-Enemy -Kind') -or -not ($log -match 'picked up: mgun') -or -not $done.Verdict) { throw 'transcript test failed.' }

    # ---- mods: the example must load, its newcomer must get states and sprites and turn up on the floor ----
    # (last of all the tests that play: a mod changes the game's tables for good)
    $guardPoints = $script:EnemyDefs.guard.Points
    $badModRejected = $false
    try { Import-Mod @{ Enemies = @{ guard = @{ Points = 999999 } }; Palettes = @{ missing = @{ Uniform = 'FFFFFF' } } } }
    catch { $badModRejected = $true }
    if (-not $badModRejected -or $script:EnemyDefs.guard.Points -ne $guardPoints) { throw 'mod transaction test failed: a rejected mod changed the game tables.' }
    Write-Step 'mod transaction test: a rejected mod leaves the game tables unchanged'

    Import-Mod (Import-PowerShellDataFile -LiteralPath (Join-Path $PSScriptRoot '../mods/examples/purple-interns.psd1'))
    Initialize-States
    foreach ($k in $script:ModKinds) { Add-SoldierSprites $k }
    $script:LevelIndex = 0; $script:BonusMap = $null; $script:Difficulty = 2; Start-Level $false $false
    $interns = @($script:Actors | Where-Object Kind -eq 'intern'); $guards = @($script:Actors | Where-Object Kind -eq 'guard')
    Set-TestCamera ($interns[0].X + 0.1) ($interns[0].Y + 2.2) 90; $interns[0].Dir = 6
    Show-PlayFrame; Save-BackBuffer (Join-Path $OutDir 'view-mod-intern.png')
    for ($f = 0; $f -lt 60; $f++) { Update-View; Update-World 2.0 $idle }
    Write-Step "mod test: $($interns.Count) interns with $($interns[0].HP) health next to $($guards.Count) guards; the pistol is now called '$($script:Weapons[1].Name)'"
    if (-not $interns.Count -or -not $guards.Count -or $interns[0].HP -ne 12 -or $script:Weapons[1].Name -ne 'Service pistol' -or -not $script:States['intern.chase1']) { throw 'mod test failed.' }
    $script:Difficulty = 1

    # ---- the updater: a release made of files, a newer version, the download checked, backed up, installed - and what is refused ----
    $rel = Join-Path $OutDir 'update'; Remove-Item -LiteralPath $rel -Recurse -Force -ErrorAction SilentlyContinue
    $null = New-Item -ItemType Directory -Path (Join-Path $rel 'new/polf3d/src'), (Join-Path $rel 'old/src') -Force
    $newVersion = '9.9.9'
    $newStart = (Get-Content -LiteralPath (Join-Path $PSScriptRoot '../Start-Polf3D.ps1') -Raw) -replace "PolfVersion = '\d+\.\d+\.\d+'", "PolfVersion = '$newVersion'"
    Set-Content -LiteralPath (Join-Path $rel 'new/polf3d/Start-Polf3D.ps1') -Value $newStart -Encoding utf8
    Set-Content -LiteralPath (Join-Path $rel 'new/polf3d/src/Newcomer.ps1') -Value '# a file the old version did not have' -Encoding utf8
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot '../Play.cmd') -Destination (Join-Path $rel 'new/polf3d/Play.cmd')
    Compress-Archive -Path (Join-Path $rel 'new/polf3d') -DestinationPath (Join-Path $rel 'polf3d.zip') -Force
    $sha = (Get-FileHash -LiteralPath (Join-Path $rel 'polf3d.zip') -Algorithm SHA256).Hash.ToLowerInvariant()
    $release = @{ tag_name = "v$newVersion"; html_url = 'https://example.invalid/release'; body = "**Download polf3d.zip below.**`n`nNew:`n`n- a **newcomer** file, see [the notes](https://example.invalid)`n`nSHA256 of polf3d.zip: ``$sha``"
        assets = @(@{ name = 'polf3d.zip'; browser_download_url = (Join-Path $rel 'polf3d.zip'); download_count = 1 }) }
    $release | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $rel 'latest.json') -Encoding utf8
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot '../Start-Polf3D.ps1'), (Join-Path $PSScriptRoot '../Play.cmd') -Destination (Join-Path $rel 'old')
    $keepSource = $script:UpdateSource; $keepCheck = $script:Settings.UpdateCheck; $keepNoCheck = $script:UpdateCheckOff
    $script:UpdateSource = Join-Path $rel 'latest.json'; $script:Settings.UpdateCheck = $true; $script:UpdateCheckOff = $false
    $script:NewRelease = $null; $script:UpdateState = ''; Remove-Item -LiteralPath (Get-UpdateStampPath) -ErrorAction SilentlyContinue
    for ($i = 0; $i -lt 200 -and $script:UpdateState -eq ''; $i++) { Update-UpdateCheck; Start-Sleep -Milliseconds 50 }
    $found = $script:UpdateState -eq 'available' -and "$($script:NewRelease.Version)" -eq $newVersion -and $script:NewRelease.Sha -eq $sha
    $notes = @(Get-UpdateNotes); $plain = ($notes -join '|') -notmatch '\*\*|SHA256|https://' -and $notes -contains '- a newcomer file, see the notes'
    $stamped = Test-Path -LiteralPath (Get-UpdateStampPath)
    $script:NewRelease = $null; $script:UpdateState = ''; Update-UpdateCheck                              # asked again the same day: the stamp answers, no runspace
    $remembered = $script:UpdateState -eq 'available' -and -not $script:UpdateCheck
    $olderRelease = $release.Clone(); $olderRelease.tag_name = 'v0.1.0'
    $older = $null -eq (ConvertTo-UpdateInfo ($olderRelease | ConvertTo-Json -Depth 4))                # an older release is no update
    Show-TitleScreen; Save-BackBuffer (Join-Path $OutDir 'screen-title-update.png')                  # the title screen with the news
    Show-UpdateScreen; Save-BackBuffer (Join-Path $OutDir 'screen-update.png')
    $old = Join-Path $rel 'old'
    $installed = Install-Update $script:NewRelease $old { param($Text) Write-Step "    update: $Text" }
    $newFile = (Get-Content -LiteralPath (Join-Path $old 'Start-Polf3D.ps1') -Raw) -match "PolfVersion = '9\.9\.9'" -and (Test-Path -LiteralPath (Join-Path $old 'src/Newcomer.ps1'))
    $backup = Join-Path $old "polf3d-backup-$script:PolfVersion.zip"
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [System.IO.Compression.ZipFile]::OpenRead($backup); $kept = @($archive.Entries.FullName); $archive.Dispose()
    $backedUp = $kept -contains 'Start-Polf3D.ps1' -and $kept -contains 'Play.cmd' -and $kept -notcontains 'src/Newcomer.ps1'
    $damaged = $script:NewRelease.Clone(); $damaged.Sha = '0' * 64
    $refused = try { $null = Install-Update $damaged $old; $false } catch { $_.Exception.Message -like '*SHA256*' }
    # a copy that fails half way is undone: a file that cannot be written stops the install, and what was already replaced goes back
    $old2 = Join-Path $rel 'old2'; $null = New-Item -ItemType Directory -Path (Join-Path $old2 'src') -Force
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot '../Start-Polf3D.ps1'), (Join-Path $PSScriptRoot '../Play.cmd') -Destination $old2
    Set-Content -LiteralPath (Join-Path $old2 'src/Newcomer.ps1') -Value '# the old one' -Encoding utf8
    $lock = [System.IO.File]::Open((Join-Path $old2 'src/Newcomer.ps1'), 'Open', 'Read', 'Read')      # readable for the backup, not writable for the install
    $rolledBack = try { $null = Install-Update $script:NewRelease $old2; $false } catch { $_.Exception.Message -like '*the old files are back*' }
    $lock.Dispose()
    $restored = (Get-Content -LiteralPath (Join-Path $old2 'Start-Polf3D.ps1') -Raw) -match "PolfVersion = '$([regex]::Escape($script:PolfVersion))'" -and (Get-Content -LiteralPath (Join-Path $old2 'src/Newcomer.ps1') -Raw) -like '*the old one*'
    $sameStart = (@(ConvertTo-StartArguments ([ordered]@{ Scale = 4; Terminal = [switch]$true; NoSound = [switch]$false; PlayerName = 'Big Boss'; Update = [switch]$true })) -join ' ') -eq '-Scale 4 -Terminal -PlayerName Big Boss'
    $script:UpdateSource = $keepSource; $script:Settings.UpdateCheck = $keepCheck; $script:UpdateCheckOff = $keepNoCheck; $script:NewRelease = $null; $script:UpdateState = ''
    Write-Step "update test: a release of $newVersion is found: $found, its notes read plain: $plain, the answer is kept: $stamped and reused: $remembered; an older release is none: $older; installed: $installed with the new file: $newFile, the old files backed up: $backedUp; a damaged download is refused: $refused; a copy that fails half way is undone: $rolledBack with the old files back: $restored; the start line survives a restart: $sameStart"
    if (-not ($found -and $plain -and $stamped -and $remembered -and $older -and $installed -and $newFile -and $backedUp -and $refused -and $rolledBack -and $restored -and $sameStart)) { throw 'update test failed.' }

    # ---- title screen ----
    $script:HighScores = @()
    Show-TitleScreen; Save-BackBuffer (Join-Path $OutDir 'screen-title.png')
    Write-Step "self-test finished: $OutDir"
}

# =============================================================================================
# Screenshots for the README (Start-Polf3D.ps1 -Screenshots <dir>): headless, staged scenes.
# =============================================================================================
function Save-Shot([string]$Dir, [string]$Name) {
    # staged scenes run in god mode; hide that (and any damage tint) for the picture
    $god = $script:GodMode; $script:GodMode = $false
    $script:DamageFlash = 0.0; $script:P.Health = [Math]::Max($script:P.Health, 87); $script:HudDirty = $true
    Show-PlayFrame
    Save-BackBuffer (Join-Path $Dir "$Name.png")
    $script:GodMode = $god
}

function Export-Screenshots([string]$OutDir) {
    $null = New-Item -ItemType Directory -Path $OutDir -Force
    $script:SaveDir = Join-Path $OutDir '_tmp'
    $script:GodMode = $true
    $script:Difficulty = 3                                        # the full cast: the easier difficulties thin out the floors
    $script:KeyDown = [bool[]]::new(256)
    $script:KeyHit = [System.Collections.Generic.Queue[int]]::new()
    $script:Mode = 'play'
    $script:ShowMiniMap = $true
    $idle = @{ Forward = 0; Strafe = 0; Turn = 0; MouseTurn = 0.0; Run = $false; Fire = $false; Use = $false; Weapon = -1 }
    $fire = $idle.Clone(); $fire.Fire = $true

    # title
    $script:HighScores = @([pscustomobject]@{ Name = 'root'; Score = 184300; Result = 'VICTORY' }, [pscustomobject]@{ Name = 'sysadmin'; Score = 96500; Result = 'killed' }, [pscustomobject]@{ Name = 'intern'; Score = 12400; Result = 'killed' })
    $script:Difficulty = 1; $script:AchievementCount = "37 of $($script:MapFiles.Count * $script:Tests.Count)"; Show-TitleScreen; Save-BackBuffer (Join-Path $OutDir 'title.png'); $script:Difficulty = 3

    # floor 1: the hub hall
    $script:LevelIndex = 0; Start-Level $false $false; $script:Message = $null
    Set-TestCamera 20.5 24.5 45
    Save-Shot $OutDir 'hub'

    # floor 1: a fire fight at the guard room door
    Set-TestCamera 7.5 24.5 90
    $use = $idle.Clone(); $use.Use = $true
    Update-World 1.0 $idle; Update-World 1.0 $use             # release, then press: 'use' is edge triggered
    $script:P.Ammo = 60
    for ($f = 0; $f -lt 600; $f++) {
        Show-PlayFrame; Update-World 2.0 $(if ($f % 40 -lt 6) { $fire } else { $idle })
        $shooter = @($script:Actors | Where-Object { $_.Visible -and $_.State -like '*.shoot2' -and $_.Depth -gt 1.2 -and $_.Depth -lt 5 -and [Math]::Abs($_.ScreenX - 160) -lt 90 })
        if ($f -gt 60 -and $shooter.Count) { break }
    }
    $script:Message = $null; Save-Shot $OutDir 'firefight'

    # floor 1: automap of what has been seen so far, plus a stroll through the hub
    foreach ($c in @(7.5, 30.5, 90), @(8.5, 19.5, 0), @(15.5, 19.5, 0), @(24.5, 19.5, 0), @(24.5, 19.5, 180), @(24.5, 19.5, 90), @(24.5, 19.5, 270), @(24.5, 28.5, 270), @(20.5, 32.5, 0), @(20.5, 32.5, 180), @(20.5, 10.5, 90), @(20.5, 8.5, 0), @(20.5, 8.5, 180), @(33.5, 19.5, 0), @(38.5, 19.5, 90), @(38.5, 19.5, 270)) { Set-TestCamera $c[0] $c[1] $c[2]; Show-PlayFrame }
    Set-TestCamera 24.5 20.5 60
    $script:KeyDown[77] = $true; $script:MapBmp = $null
    Save-Shot $OutDir 'automap'
    $script:KeyDown[77] = $false

    # floor 1: the kennels
    Start-Level $false $false; $script:Message = $null
    Set-TestCamera 20.5 35.5 60
    for ($f = 0; $f -lt 40; $f++) { Show-PlayFrame; Update-World 2.0 $idle }
    Save-Shot $OutDir 'kennels'

    # floor 3: catacombs
    $script:LevelIndex = 2; Start-Level $false $false; $script:Message = $null
    Set-TestCamera 26.5 30.5 135
    Save-Shot $OutDir 'catacombs'

    # floor 4: the ring corridor with a patrol coming
    $script:LevelIndex = 3; Start-Level $false $false; $script:Message = $null
    Set-TestCamera 22.5 7.5 180
    for ($f = 0; $f -lt 25; $f++) { Show-PlayFrame; Update-World 2.0 $idle }
    Save-Shot $OutDir 'lab'

    # floor 4: pipeline cannon versus the war machine
    $p = $script:P
    $p.Owned = (New-OwnedList $true); $p.Ammo = 99; $p.Charges = 3; $p.Weapon = 4; $p.ChosenWeapon = 4
    $mech = $script:Actors | Where-Object Kind -eq 'uber' | Select-Object -First 1
    Set-TestCamera ($mech.X + 0.4) ($mech.Y - 5.5) 270
    $script:InfiniteAmmo = $true                                  # the staging may take a while - the beam must not run dry
    foreach ($barrel in @($script:Actors | Where-Object { $_.Def.Inert })) { $null = $script:Actors.Remove($barrel) }      # they would stand in the picture
    for ($f = 0; $f -lt 900; $f++) {
        Show-PlayFrame; Update-World 2.0 $(if ($f % 30 -lt 15 -and $f -gt 120) { $fire } else { $idle })
        $rockets = @($script:Actors | Where-Object { $_.Kind -eq 'rocket' -and $_.State -eq 'rocket.fly' -and $_.Visible -and $_.Depth -gt 2.6 -and [Math]::Abs($_.ScreenX - $mech.ScreenX) -gt 45 })
        $blasts = @($script:Actors | Where-Object { $_.State -like 'rocket.boom*' -and $_.Visible -and $_.Depth -lt 4 })      # would fill the picture
        $near = @($script:Actors | Where-Object { $_.Kind -eq 'rocket' -and $_.Visible -and $_.Depth -le 2.6 })
        if ($script:BeamFlash -gt 5 -and ($rockets.Count -or $f -gt 600) -and -not $near.Count -and $mech.Shootable -and $mech.Visible -and $mech.Depth -gt 3 -and -not $blasts.Count) { break }
    }
    $script:InfiniteAmmo = $false
    $script:Message = $null; $p.Ammo = 71; Save-Shot $OutDir 'warmachine'

    # floor 5: the great hall
    $script:LevelIndex = 4; Start-Level $false $false; $script:Message = $null
    $p = $script:P; $p.Owned = (New-OwnedList $false); $p.Ammo = 84; $p.Weapon = 3; $p.ChosenWeapon = 3
    Set-TestCamera 23.5 29.5 90
    for ($f = 0; $f -lt 30; $f++) { Show-PlayFrame; Update-World 2.0 $idle }
    Save-Shot $OutDir 'citadel'

    # floor 2, co-op: the partner runs ahead (a network game without a network: nothing is ever sent)
    Initialize-Network 'client' 'coop' 'localhost' 1 4 'You'
    $script:Net.Connected = $true; $script:Net.Slot = 1
    $script:Net.Roster = @(@{ Slot = 0; Name = 'Anna'; X = $null; Y = $null }, @{ Slot = 1; Name = 'You'; X = $null; Y = $null }, @{ Slot = 2; Name = 'Bob'; X = $null; Y = $null })
    $script:LevelIndex = 1; Start-Level $false $false; $script:Message = $null
    $p = $script:P; $p.Owned[2] = $true; $p.Ammo = 48; $p.Weapon = 2; $p.ChosenWeapon = 2
    $foe = $script:Actors | Where-Object { $_.Shootable -and -not $_.Def.Inert -and $_.Kind -notin 'peer', 'dog' } | Select-Object -First 1
    $step = @{ 0 = @(1, 0); 2 = @(0, -1); 4 = @(-1, 0); 6 = @(0, 1) }[[int]$foe.Dir]; if (-not $step) { $step = @(1, 0) }
    $cx = $foe.X + $step[0] * 4; $cy = $foe.Y + $step[1] * 4
    if ($script:Tiles[[int][Math]::Floor($cy) * $script:MapW + [int][Math]::Floor($cx)] -ne 0) { $cx = $foe.X + $step[0] * 2; $cy = $foe.Y + $step[1] * 2 }
    Set-TestCamera $cx $cy 0; Set-TestAim $foe
    foreach ($pl in $script:Net.Players.Values) {
        $side = if ($pl.Slot -eq 0) { 0.5 } else { -0.55 }; $ahead = if ($pl.Slot -eq 0) { 0.45 } else { 0.62 }
        $g = $pl.Ghost
        $g.X = $cx + ($foe.X - $cx) * $ahead - $step[1] * $side; $g.Y = $cy + ($foe.Y - $cy) * $ahead + $step[0] * $side
        $g.NX = $g.X; $g.NY = $g.Y; $g.TX = [int][Math]::Floor($g.X); $g.TY = [int][Math]::Floor($g.Y)
        $g.Dir = ([int]$foe.Dir + 4) % 8; $g.State = "peer$($pl.Slot).w$(2 + $pl.Slot)"; $pl.Health = 82 - 20 * $pl.Slot
    }
    Save-Shot $OutDir 'coop'
    Stop-Network

    # the cast: front views of every enemy, 3x
    $cast = 'guard.s', 'dog.s', 'officer.s', 'elite.s', 'mutant.s', 'sniper.s', 'shield.s', 'engineer.s', 'auditor.s',
            'bug.s', 'bot.s', 'camera.s', 'turret.s', 'boss.s', 'uber.s', 'pilot.s', 'bsod.s'
    $names = 'Guard', 'Dog', 'Officer', 'Elite', 'Mutant', 'Sniper', 'Shield bearer', 'Engineer', 'Auditor',
             'Bug', 'Kamikaze bot', 'Camera', 'Sentry gun', 'Commander', 'War machine', 'Pilot', 'BLUE SCREEN'
    $cell = 160; $perRow = 9; $rowH = 236
    $bmp = [System.Drawing.Bitmap]::new($cell * $perRow, $rowH * [int][Math]::Ceiling($cast.Count / $perRow))
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.Clear([System.Drawing.Color]::FromArgb(255, 10, 16, 32))
    for ($r = 0; $r * $perRow -lt $cast.Count; $r++) { $g.FillRectangle((Get-Brush '6E6E6E'), 0, $r * $rowH + 150, $bmp.Width, 60); $g.FillRectangle((Get-Brush '0A1428'), 0, $r * $rowH + 206, $bmp.Width, 30) }
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::NearestNeighbor
    $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::Half
    $font = [System.Drawing.Font]::new('Consolas', 11, [System.Drawing.FontStyle]::Bold)
    $fmt = [System.Drawing.StringFormat]::new(); $fmt.Alignment = [System.Drawing.StringAlignment]::Center
    for ($i = 0; $i -lt $cast.Count; $i++) {
        $row = [int][Math]::Floor($i / $perRow); $inRow = [Math]::Min($perRow, $cast.Count - $row * $perRow)
        $x = ($i % $perRow) * $cell + [int](($perRow - $inRow) * $cell / 2); $y = $row * $rowH      # a shorter last row is centred
        $px = $script:Spr[$cast[$i]]; if ($px[0] -isnot [int]) { $px = $px[0] }
        $tile = [System.Drawing.Bitmap]::new(64, 64, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
        $bd = $tile.LockBits([System.Drawing.Rectangle]::new(0, 0, 64, 64), 'WriteOnly', $tile.PixelFormat)
        [System.Runtime.InteropServices.Marshal]::Copy([int[]]$px, 0, $bd.Scan0, 4096); $tile.UnlockBits($bd)
        $g.DrawImage($tile, [System.Drawing.Rectangle]::new($x - 16, $y + 8, 192, 192)); $tile.Dispose()
        $g.DrawString($names[$i], $font, [System.Drawing.Brushes]::White, [System.Drawing.RectangleF]::new($x, $y + 212, $cell, 22), $fmt)
    }
    $bmp.Save((Join-Path $OutDir 'cast.png'), [System.Drawing.Imaging.ImageFormat]::Png); $g.Dispose(); $bmp.Dispose()

    # the host's player list (no sockets behind these guests: it is only a picture)
    Initialize-Network 'host' 'duel' '' 27997 4 'Boss'
    foreach ($fake in @(1, 'Anna', '192.168.1.20'), @(2, 'Bob', '192.168.1.23'), @(3, 'Mallory', '203.0.113.7')) {
        $script:Net.Guests.Add(@{ Slot = $fake[0]; Name = $fake[1]; Address = $fake[2]; InLevel = $true; Ready = $true; Out = [System.Text.StringBuilder]::new() })
    }
    $script:Net.Connected = $true; $script:Net.Bans.Clear(); $script:Net.Bans.Add('198.51.100.66')
    $script:LevelIndex = 2; Start-Level $false $false; $script:Message = $null
    $script:Net.Frags = @{ 0 = 4; 1 = 6; 2 = 1; 3 = 0 }; $script:Net.Players[2].Health = 35; $script:Net.Panel.Row = 2
    Set-TestCamera 26.5 30.5 135
    Show-PlayFrame; Show-NetPanel; Save-BackBuffer (Join-Path $OutDir 'players.png')
    $script:Net.Guests.Clear(); Stop-Network

    # floor 1: -WhatIf in the hub - where will they be in two seconds, and who will shoot?
    $script:LevelIndex = 0; $script:BonusMap = $null; Start-Level $false $false; $script:Message = $null
    Set-TestCamera 20.5 24.5 45; $script:P.Privilege = 100.0
    $fire = $idle.Clone(); $fire.Fire = $true
    for ($f = 0; $f -lt 50; $f++) { Show-PlayFrame; Update-World 2.0 $(if ($f -lt 4) { $fire } else { $idle }) }      # a shot: now they are on their way
    $whatIf = $idle.Clone(); $whatIf.Ability = 1
    Update-World 1.0 $whatIf; Update-World 1.0 $idle
    Save-Shot $OutDir 'whatif'
    Stop-WhatIf

    # ... and the console, a few lines in
    $script:P.Privilege = 100.0; $script:Con = $null
    Open-Console
    foreach ($line in 'Get-Enemy | Sort-Object Distance | Select-Object -First 4', 'Get-Enemy | sort Distance | select -First 1 | Stop-Enemy -WhatIf',
        'Get-Enemy | ? State -eq attacking | Suspend-Enemy', "Get-Door | ? Lock -ne '-' | ft Id, Lock, State, Distance", 'Remove-Item C:\ -Recurse -Force') { Invoke-ConsoleLine $line }
    Show-PlayFrame; Show-Console; Save-BackBuffer (Join-Path $OutDir 'console.png')
    Close-Console

    # the face in the status bar, from fresh to dead and in all its moods
    $sheet = [System.Drawing.Bitmap]::new(7 * 124 + 16, 2 * 170 + 8)
    $sg = [System.Drawing.Graphics]::FromImage($sheet); $sg.Clear([System.Drawing.Color]::FromArgb(255, 10, 16, 32))
    $sg.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::NearestNeighbor; $sg.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::Half
    $sg.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAlias
    $label = [System.Drawing.Font]::new('Consolas', 9); $centre = [System.Drawing.StringFormat]::new(); $centre.Alignment = [System.Drawing.StringAlignment]::Center
    $cells = @(@('100-80', 0, 'idle'), @('79-60', 1, 'idle'), @('59-40', 2, 'idle'), @('39-20', 3, 'idle'), @('19-1', 4, 'idle'), @('dead', 5, 'idle'), @('ouch!', 2, 'pain')),
             @(@('new weapon', 0, 'grin'), @('trigger held', 1, 'rage'), @('sneaking', 0, 'sneak'), @('SUDO', 0, 'sudo'), @('god mode', 0, 'god'), @('grin, battered', 3, 'grin'), @('rage at 15', 4, 'rage'))
    for ($row = 0; $row -lt 2; $row++) {
        for ($i = 0; $i -lt 7; $i++) {
            $c = $cells[$row][$i]; $x = 8 + $i * 124; $y = 6 + $row * 170
            $sg.FillRectangle((Get-Brush 'FF101A2C'), $x, $y, 120, 136)
            $sg.DrawImage((Get-FaceBitmap $c[1] $c[2] 0), [System.Drawing.Rectangle]::new($x, $y, 120, 136))
            $sg.DrawString($c[0], $label, (Get-Brush 'FFC0C8D8'), [System.Drawing.RectangleF]::new($x - 2, $y + 142, 124, 18), $centre)
        }
    }
    $sheet.Save((Join-Path $OutDir 'faces.png'), [System.Drawing.Imaging.ImageFormat]::Png); $sg.Dispose(); $sheet.Dispose(); $label.Dispose()

    # a dungeon from a number
    $null = Start-Dungeon 20260918; $script:Recording = $null; $script:Message = $null
    $foe = $script:Actors | Where-Object { $_.Shootable -and -not $_.Def.Inert } | Sort-Object { [Math]::Abs($_.X - $script:P.X) + [Math]::Abs($_.Y - $script:P.Y) } | Select-Object -First 1
    for ($f = 0; $f -lt 6; $f++) { Show-PlayFrame }
    $script:KeyDown[77] = $true; $script:MapBmp = $null
    for ($i = 0; $i -lt $script:Vis.Length; $i++) { $script:Vis[$i] = 1 }      # the whole plan, for the picture
    Save-Shot $OutDir 'dungeon'
    $script:KeyDown[77] = $false
    Stop-Dungeon

    # the same hall the way -Terminal shows it: 150 x 47 character cells, two pixels each, status lines as text
    $script:LevelIndex = 0; $script:BonusMap = $null; Start-Level $false $false; $script:Message = $null
    Set-TestCamera 20.5 24.5 45; Update-View
    $cols = 150; $rows = 47; $cellW = 8; $cellH = 16
    $small = [System.Drawing.Bitmap]::new($cols, $rows * 2, [System.Drawing.Imaging.PixelFormat]::Format32bppRgb)
    $px = [int[]]::new($cols * $rows * 2)
    for ($r = 0; $r -lt $rows * 2; $r++) { $sy = [int][Math]::Floor($r * $script:ViewH / ($rows * 2)); for ($c = 0; $c -lt $cols; $c++) { $px[$r * $cols + $c] = $script:FB[$sy * $script:ViewW + [int][Math]::Floor($c * $script:ViewW / $cols)] -band 0xFFF8F8F8 } }
    $bd = $small.LockBits([System.Drawing.Rectangle]::new(0, 0, $cols, $rows * 2), 'WriteOnly', $small.PixelFormat)
    [System.Runtime.InteropServices.Marshal]::Copy($px, 0, $bd.Scan0, $px.Length); $small.UnlockBits($bd)
    $term = [System.Drawing.Bitmap]::new($cols * $cellW + 32, ($rows + 5) * $cellH + 52)
    $tg = [System.Drawing.Graphics]::FromImage($term)
    $tg.Clear([System.Drawing.Color]::FromArgb(255, 12, 12, 12))
    $tg.FillRectangle((Get-Brush 'FF2B2B2B'), 0, 0, $term.Width, 30); $tg.FillRectangle((Get-Brush 'FF0C0C0C'), 8, 4, 250, 26)
    $tg.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::ClearTypeGridFit
    $ui = [System.Drawing.Font]::new('Segoe UI', 9); $mono = [System.Drawing.Font]::new('Consolas', 10.5)
    $tg.DrawString('PowerShell  -  ./Start-Polf3D.ps1 -Terminal', $ui, (Get-Brush 'FFE0E0E0'), 16, 8)
    $tg.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::NearestNeighbor; $tg.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::Half
    $tg.DrawImage($small, [System.Drawing.Rectangle]::new(16, 38, $cols * $cellW, $rows * $cellH)); $small.Dispose()
    $ty = 38 + $rows * $cellH + 2
    $tg.DrawString("(•_•)", $mono, (Get-Brush 'FFFFFFFF'), 16, $ty); $tg.DrawString("$([char]0x2665) 100 $(Get-TerminalBar 1.0 10)", $mono, (Get-Brush 'FF60FF80'), 72, $ty)
    $tg.DrawString('AMMO 16', $mono, (Get-Brush 'FFFFFFFF'), 250, $ty); $tg.DrawString('PISTOL', $mono, (Get-Brush 'FF40E0FF'), 330, $ty)
    $tg.DrawString("PRIV $(Get-TerminalBar 0.5 8)", $mono, (Get-Brush 'FF8FB0FF'), 400, $ty)
    $tg.DrawString("FLOOR 1  SCORE 000000  LIVES 3   KILLS 0/$($script:Stats.KillTotal)  SECRETS 0/$($script:Stats.SecretTotal)  TREASURE 0/$($script:Stats.TreasureTotal)", $mono, (Get-Brush 'FFA0B4D0'), 16, ($ty + $cellH))
    $tg.DrawString('Floor 1: Shellstein Dungeon', $mono, (Get-Brush 'FFFFE860'), 16, ($ty + 2 * $cellH))
    $term.Save((Join-Path $OutDir 'terminal.png'), [System.Drawing.Imaging.ImageFormat]::Png); $tg.Dispose(); $term.Dispose(); $ui.Dispose(); $mono.Dispose()

    # the second half: a cold aisle of the data centre, and the core of Ring 0
    $script:LevelIndex = 5; $script:BonusMap = $null; Start-Level $false $false; $script:Message = $null
    $script:P.Owned = (New-OwnedList $true); $script:P.Ammo = 64; $script:P.Weapon = 2; $script:P.ChosenWeapon = 2
    Set-TestCamera 13.5 27.5 90
    for ($f = 0; $f -lt 8; $f++) { Show-PlayFrame }
    Save-Shot $OutDir 'datacentre'
    $script:LevelIndex = 9; Start-Level $false $false; $script:Message = $null
    $script:P.Owned = (New-OwnedList $true); $script:P.Ammo = 99; $script:P.Weapon = 4; $script:P.ChosenWeapon = 4
    Set-TestCamera 25.5 16.4 270; $script:P.Light = $true
    for ($f = 0; $f -lt 40; $f++) { Show-PlayFrame }
    $script:Message = $null; Save-Shot $OutDir 'ring0'

    # the onboarding: the console room and what the floor has to say about it
    if (Start-Tutorial) {
        $script:Message = $null
        Set-TestCamera 37.5 13.5 0; Update-World 1.0 $idle; $script:Message = $null
        Save-Shot $OutDir 'tutorial'
        Stop-Tutorial
    }

    # the arena: wave three is on its way in
    if (Start-Horde 4711) {
        $script:Message = $null; $script:P.Owned = (New-OwnedList $true); $script:P.Ammo = 72; $script:P.Weapon = 3; $script:P.ChosenWeapon = 3
        $script:Stats.Wave = 2; $script:Stats.WaveQueue = @(); $script:Stats.WaveTimer = 1.0
        for ($f = 0; $f -lt 260 -and @($script:Actors | Where-Object { $_.Shootable -and -not $_.Def.Inert }).Count -lt 9; $f++) { Update-World 4.0 $idle }
        Set-TestCamera 16.5 17.5 90
        for ($f = 0; $f -lt 30; $f++) { Update-World 2.0 $idle }
        Set-TestCamera 16.5 17.5 90; $script:Message = $null
        Save-Shot $OutDir 'arena'
        Stop-Horde
    }

    # a floor's test report (the epilogue is NOT among the pictures: it has to be earned)
    $script:LevelIndex = 2; Start-Level $false $false; $script:P.Cheated = $false
    $st = $script:Stats; $st.Tics = 70 * 371; $st.Kills = $st.KillTotal; $st.Secrets = $st.SecretTotal; $st.Treasures = $st.TreasureTotal - 2
    $script:Run.Alerts = 9; $script:Run.Shots = 0; $script:Run.MinHealth = 61; $script:P.Score = 48200; $script:P.RunTics = 70 * 1284; $script:P.RunTics = 70 * 1284
    $script:Result = @{ Last = $false; Exact = 371.4; Previous = 0; Kills = 100; Secrets = 100; Treasures = 77; Bonus = 44500; Tests = (Invoke-FloorTests)
        Transcript = @{ Verdict = 'Completed without firing a shot. The catacombs are quieter than they have ever been.' } }
    Show-DoneScreen; Save-BackBuffer (Join-Path $OutDir 'tests.png')

    Export-Banner (Join-Path $OutDir 'banner.png')

    Remove-Item -LiteralPath $script:SaveDir -Recurse -Force -ErrorAction SilentlyContinue
    Write-Step "screenshots written: $OutDir"
}

# The title picture (1280x640, the size GitHub uses for social previews): the war machine opening fire, straight
# from the game's own renderer, with the title set over it.
function Export-Banner([string]$Path) {
    $script:LevelIndex = 3; $script:BonusMap = $null; Start-Level $false $false; $script:Message = $null
    $mech = $script:Actors | Where-Object Kind -eq 'uber' | Select-Object -First 1
    Set-TestCamera ($mech.X + 0.3) ($mech.Y - 3.3) 288            # looking a little past it: the machine stands in the right half
    $mech.State = 'uber.shoot2'; $mech.Dir = 2
    $rocket = [Actor]::new(); $rocket.Kind = 'rocket'; $rocket.Def = $script:MiscDefs.rocket; $rocket.State = 'rocket.fly'; $rocket.Corpse = $true
    $rocket.X = $mech.X + 0.75; $rocket.Y = $mech.Y - 1.5; $rocket.TX = [int][Math]::Floor($rocket.X); $rocket.TY = [int][Math]::Floor($rocket.Y)
    $script:Actors.Add($rocket)
    $fog = $script:FogPerTile; $script:FogPerTile = $fog * 0.45   # studio lighting
    $script:ShowWeapon = $false
    Update-View
    $script:ShowWeapon = $true; $script:FogPerTile = $fog
    $view = [System.Drawing.Bitmap]::new($script:ViewW, $script:ViewH, [System.Drawing.Imaging.PixelFormat]::Format32bppRgb)
    $bd = $view.LockBits([System.Drawing.Rectangle]::new(0, 0, $view.Width, $view.Height), 'WriteOnly', $view.PixelFormat)
    [System.Runtime.InteropServices.Marshal]::Copy($script:FB, 0, $bd.Scan0, $script:FB.Length); $view.UnlockBits($bd)

    $W = 1280; $H = 640
    $bmp = [System.Drawing.Bitmap]::new($W, $H)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::NearestNeighbor
    $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::Half
    $scale = $W / $view.Width; $vh = $view.Height * $scale
    $g.DrawImage($view, [System.Drawing.RectangleF]::new(0, ($H - $vh) / 2 - 20, $W, $vh))
    $view.Dispose()

    # darken the left for the lettering, and the edges all round
    $rect = [System.Drawing.Rectangle]::new(0, 0, $W, $H)
    $shade = [System.Drawing.Drawing2D.LinearGradientBrush]::new([System.Drawing.Point]::new(0, 0), [System.Drawing.Point]::new([int]($W * 0.72), 0),
        [System.Drawing.Color]::FromArgb(235, 6, 10, 24), [System.Drawing.Color]::FromArgb(0, 6, 10, 24))
    $g.FillRectangle($shade, 0, 0, [int]($W * 0.72), $H); $shade.Dispose()
    foreach ($edge in @(0, 0, 90, 270), @(($H - 110), 110, 110, 90)) {
        $r = [System.Drawing.Rectangle]::new(0, $edge[0], $W, $(if ($edge[1]) { $edge[1] } else { $edge[2] }))
        $dark = [System.Drawing.Color]::FromArgb(210, 4, 6, 14); $clear = [System.Drawing.Color]::FromArgb(0, 4, 6, 14)
        $fade = [System.Drawing.Drawing2D.LinearGradientBrush]::new($r, $(if ($edge[3] -eq 270) { $dark } else { $clear }), $(if ($edge[3] -eq 270) { $clear } else { $dark }), [single]90)
        $g.FillRectangle($fade, $r); $fade.Dispose()
    }
    for ($y = 0; $y -lt $H; $y += 4) { $g.FillRectangle((Get-Brush '30000000'), 0, $y, $W, 2) }      # scan lines

    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAlias
    $title = [System.Drawing.Font]::new('Consolas', 138, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
    $mid = [System.Drawing.Font]::new('Consolas', 30, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
    $small = [System.Drawing.Font]::new('Consolas', 21, [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel)
    $x = 58; $y = 150
    for ($i = 12; $i -ge 1; $i--) { $g.DrawString('POLF 3D', $title, (Get-Brush $(if ($i -gt 9) { 'FF050A18' } else { 'FF1C3C9C' })), ($x + $i), ($y + $i)) }      # extruded
    $face = [System.Drawing.Drawing2D.LinearGradientBrush]::new([System.Drawing.Point]::new(0, $y + 20), [System.Drawing.Point]::new(0, $y + 150),
        [System.Drawing.Color]::White, [System.Drawing.Color]::FromArgb(255, 120, 215, 255))
    $g.DrawString('POLF 3D', $title, $face, $x, $y); $face.Dispose()

    # the prompt line: a little terminal window
    $px = $x + 8; $py = $y + 176
    $px = $x + 24
    $g.FillRectangle((Get-Brush 'E0081020'), $px, $py, 470, 52)
    $pen = [System.Drawing.Pen]::new([System.Drawing.Color]::FromArgb(255, 44, 84, 196), [single]3); $g.DrawRectangle($pen, $px, $py, 470, 52); $pen.Dispose()
    $g.DrawString('PS>', $mid, (Get-Brush 'FF60FF80'), ($px + 14), ($py + 9))
    $g.DrawString('./Start-Polf3D.ps1', $mid, (Get-Brush 'FF40E0FF'), ($px + 76), ($py + 9))
    $g.FillRectangle((Get-Brush 'FF40E0FF'), ($px + 386), ($py + 12), 16, 29)

    $g.DrawString('A 90s-style ray casting shooter - written in PowerShell.', $small, (Get-Brush 'FFE8ECF4'), ($px - 3), ($py + 78))
    $g.DrawString('a real PowerShell console   -WhatIf / -Confirm / -Force as powers', $small, (Get-Brush 'FF8FB0FF'), ($px - 3), ($py + 108))      # only what never changes
    $g.FillRectangle((Get-Brush 'FF2C54C4'), 0, 0, $W, 8); $g.FillRectangle((Get-Brush 'FF2C54C4'), 0, ($H - 8), $W, 8)

    $bmp.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
    foreach ($o in $title, $mid, $small, $g, $bmp) { $o.Dispose() }
}

# Maintenance (-BalanceTest <floor>): the demo bot plays the floor a few times on every difficulty. The bot never
# takes cover, never retreats and never goes looking for supplies - a human should do clearly better than this.
function Invoke-BalanceTest([int]$Floor, [int]$Runs = 6, [int]$Seconds = 120) {
    $script:KeyDown = [bool[]]::new(256); $script:KeyHit = [System.Collections.Generic.Queue[int]]::new(); $script:Mode = 'play'
    $script:SaveDir = Join-Path $PSScriptRoot '../selftest/_balance'
    $duelsOnly = $Floor -lt 0; $Floor = [Math]::Abs($Floor)          # a negative floor number: just the boss duels
    for ($d = 0; $d -lt 4 -and -not $duelsOnly; $d++) {
        $alive = 0.0; $kills = 0; $deaths = 0; $dry = 0; $frames = 0; $left = 0; $killers = @()
        for ($run = 0; $run -lt $Runs; $run++) {
            $script:GodMode = $false; $script:Difficulty = $d; $script:LevelIndex = $Floor - 1; $script:BonusMap = $null
            $script:NextSeed = 1000 + $run
            Start-Level $false $false
            Reset-Bot
            # nobody arrives on a later floor with just a pistol: a modest kit of what the floors before offer
            $p = $script:P
            if ($Floor -ge 2) { $p.Owned[2] = $true; $p.Weapon = 2; $p.ChosenWeapon = 2; $p.Ammo = 40 }
            if ($Floor -ge 3) { $p.Owned[3] = $true; $p.Weapon = 3; $p.ChosenWeapon = 3; $p.Ammo = 60 }
            for ($f = 0; $f -lt $Seconds * 35 -and -not $script:PlayerDied -and -not $script:LevelDone; $f++) {
                Update-View
                Update-World 2.0 (Get-BotInput $f)
                if ($script:P.Ammo -le 0) { $dry++ }
            }
            $frames += $f; $alive += $f / 35.0; $kills += $script:Stats.Kills; $left += $script:P.Health
            if ($script:PlayerDied) { $deaths++; $killers += "$(if ($script:Killer) { $script:Killer.Kind } else { 'trap' })$(if ($script:P.Ammo -le 0) { ' (no ammo)' })" }
        }
        Write-Step ('{0,-30} died {1}/{2}   alive {3,5:0.0}s   kills {4,4:0.0}   health left {5,3:0}   out of ammo {6,3:0}% of the time   killed by: {7}' -f
            $script:Difficulties[$d].Name, $deaths, $Runs, ($alive / $Runs), ($kills / $Runs), ($left / $Runs), (100.0 * $dry / [Math]::Max(1, $frames)), ($killers -join ', '))
    }
    # the boss duels: full health, the guns one has by then, four tiles in front of the boss - and no cover at all
    for ($d = 0; $d -lt 4; $d++) {
        $script:Difficulty = $d; $script:LevelIndex = $Floor - 1; $script:NextSeed = 77; Start-Level $false $false
        $bosses = @($script:Actors | Where-Object { $_.Kind -in 'boss', 'uber', 'bsod' } | ForEach-Object { "$($_.TX),$($_.TY)" })
        foreach ($spot in $bosses) {
            $won = 0; $left = 0; $time = 0.0
            for ($run = 0; $run -lt $Runs; $run++) {
                $script:GodMode = $false; $script:NextSeed = 2000 + $run; Start-Level $false $false; Reset-Bot
                $boss = $script:Actors | Where-Object { "$($_.TX),$($_.TY)" -eq $spot -and $_.Kind -in 'boss', 'uber', 'bsod' } | Select-Object -First 1
                $kind = $boss.Kind
                # everybody else stays out of it
                foreach ($other in @($script:Actors)) { if ($other -ne $boss -and -not $other.Def.Inert) { $script:ActorAt[$other.TY * $script:MapW + $other.TX] = $null; $null = $script:Actors.Remove($other) } }
                $px = $boss.TX; $py = $boss.TY; $best = -1
                foreach ($dir in @(1, 0), @(-1, 0), @(0, 1), @(0, -1)) {      # whichever direction has room for it
                    $tx = $boss.TX; $ty = $boss.TY
                    for ($i = 0; $i -lt 4; $i++) { $idx = ($ty + $dir[1]) * $script:MapW + $tx + $dir[0]; if ($script:Tiles[$idx] -ne 0 -or $script:StaticBlock[$idx]) { break }; $tx += $dir[0]; $ty += $dir[1] }
                    if ($i -gt $best) { $best = $i; $px = $tx; $py = $ty }
                }
                Set-TestCamera ($px + 0.5) ($py + 0.5) 0; Set-TestAim $boss
                $p = $script:P; $gun = if ($Floor -ge 3) { 3 } else { 2 }
                $p.Owned[2] = $true; $p.Owned[$gun] = $true; $p.Weapon = $gun; $p.ChosenWeapon = $gun; $p.Ammo = 99
                for ($f = 0; $f -lt 60 * 35 -and -not $script:PlayerDied; $f++) {
                    Update-View; Update-World 2.0 (Get-BotInput $f)
                    if (-not @($script:Actors | Where-Object { $_.Shootable -and -not $_.Def.Inert }).Count -and $f -gt 35) { break }
                }
                if (-not $script:PlayerDied) { $won++; $left += $script:P.Health }
                elseif ($env:POLF_DEBUG) { Write-Step "    lost: started $([Math]::Abs($px - $boss.TX) + [Math]::Abs($py - $boss.TY)) tiles away, killed by $(if ($script:Killer) { $script:Killer.Kind } else { 'a blast or trap' }) after $([int]($f / 35.0 * 10) / 10)s, boss HP $($boss.HP)" }
                $time += $f / 35.0
            }
            Write-Step ('  duel with the {0,-5} on {1,-30} won {2}/{3}   health left after a win {4,3:0}   {5,4:0.0}s' -f $kind, $script:Difficulties[$d].Name, $won, $Runs, ($left / [Math]::Max(1, $won)), ($time / $Runs))
        }
    }
    Remove-Item -LiteralPath $script:SaveDir -Recurse -Force -ErrorAction SilentlyContinue
    Write-Step "balance test of floor $Floor finished"
}
