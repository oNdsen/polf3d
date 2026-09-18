# POLF 3D - Copyright (c) 2026 oNdsen. Licensed under the MIT License, see LICENSE.

# Settings.ps1 - what a player wants to set once and keep: mouse sensitivity, volumes, a few display
# options and the keys. Kept in saves/settings.json; O on the title screen or in the pause menu opens
# the menu. Parameters given on the command line win over the file for that start.

$script:BindDefaults = [ordered]@{
    Forward = 87; Back = 83; StrafeLeft = 65; StrafeRight = 68; TurnLeft = 37; TurnRight = 39
    Run = 16; Sneak = 67; Fire = 17; Use = 32; Map = 77; Console = 84
    WhatIf = 90; Confirm = 88; Verbose = 86; Force = 70; Undo = 82
    Macro1 = 71; Macro2 = 72; Macro3 = 66; Macro4 = 89; Light = 76
}
$script:BindLabels = @{
    Forward = 'forward'; Back = 'back'; StrafeLeft = 'strafe left'; StrafeRight = 'strafe right'; TurnLeft = 'turn left'; TurnRight = 'turn right'
    Run = 'run'; Sneak = 'sneak'; Fire = 'fire'; Use = 'use'; Map = 'automap (hold)'; Console = 'console'
    WhatIf = '-WhatIf'; Confirm = '-Confirm'; Verbose = '-Verbose'; Force = '-Force'; Undo = 'Undo'
    Light = 'flashlight'; Macro1 = 'console hotkey 1'; Macro2 = 'console hotkey 2'; Macro3 = 'console hotkey 3'; Macro4 = 'console hotkey 4'
}
# what every row of the menu is for - shown to the right of its value
$script:OptionHelp = @{
    Mouse = 'how far the view turns when the mouse moves (mouse look: F2)'
    Sfx = 'shots, doors, explosions and what the enemies shout'
    Music = 'the title anthem and the floors'' music (on and off: F4)'
    MiniMap = 'the radar in the corner: walls you have seen, alerted enemies (N)'
    Fps = 'frames per second in the corner (F3)'
    FlatFloors = 'plain floors and ceilings are faster on a slow machine'
    Forward = 'walk forward (arrow up always works too)'
    Back = 'walk backwards (arrow down always works too)'
    StrafeLeft = 'step to the left without turning'
    StrafeRight = 'step to the right without turning'
    TurnLeft = 'turn left (the mouse turns too)'
    TurnRight = 'turn right (the mouse turns too)'
    Run = 'hold: faster and harder to hit, but heard from further away'
    Sneak = 'hold: slow and silent, enemies notice you much later'
    Fire = 'fire the weapon in hand (also J and the left mouse button)'
    Use = 'doors, levers, lift switch, secret walls, terminals (also E, right button)'
    Map = 'hold: the plan of what you have explored so far'
    Console = 'the PowerShell console - the world stands still while you type (also Tab)'
    WhatIf = '25 privilege: time stops and everybody''s next two seconds show as ghosts'
    Confirm = '30 privilege: the world runs at a third of its speed for five seconds'
    Verbose = '15 privilege: ten seconds of seeing everybody nearby through walls'
    Force = '35 privilege: kicks in the door or the cracked wall in front of you'
    Undo = '60 privilege: the last five seconds never happened'
    Light = 'in dark rooms: you see further - and everybody sees you'
    Macro1 = 'runs the command line you put on it in the console: Set-Hotkey 1 ''...'''
    Macro2 = 'the second console hotkey: Set-Hotkey 2 ''...'''
    Macro3 = 'the third console hotkey: Set-Hotkey 3 ''...'''
    Macro4 = 'the fourth console hotkey: Set-Hotkey 4 ''...'''
    Reset = 'all settings and all keys as they were on the first day'
}

# keys that mean something in every mode and must not be given away
$script:BindReserved = 13, 27, 112, 113, 114, 115, 116, 117, 118, 119, 120, 122, 123, 49, 50, 51, 52, 53, 54, 55, 56, 57

$script:Settings = @{ Mouse = 0.12; Sfx = 0.7; Music = 0.45; MiniMap = $true; Fps = $false; FlatFloors = $false; Scale = 3 }
$script:Bind = @{}
foreach ($k in $script:BindDefaults.Keys) { $script:Bind[$k] = $script:BindDefaults[$k] }
$script:Options = @{ Row = 0; Return = 'title'; Waiting = $false }

function Get-SettingsPath { Join-Path $script:SaveDir 'settings.json' }

function Import-Settings {
    $path = Get-SettingsPath
    if (-not (Test-Path -LiteralPath $path)) { return }
    try {
        $saved = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json -AsHashtable
        foreach ($k in @($script:Settings.Keys)) { if ($saved.ContainsKey($k) -and $null -ne $saved[$k]) { $script:Settings[$k] = $saved[$k] } }
        if ($saved.Keys -contains 'Bind') { foreach ($k in @($script:Bind.Keys)) { $v = [int]$saved.Bind[$k]; if ($v -gt 0 -and $v -lt 256) { $script:Bind[$k] = $v } } }
        $script:Settings.Mouse = [Math]::Max(0.02, [Math]::Min(0.5, [double]$script:Settings.Mouse))
        $script:Settings.Scale = [Math]::Max(2, [Math]::Min(5, [int]$script:Settings.Scale))
    }
    catch { Write-Warning "saves/settings.json could not be read: $($_.Exception.Message)" }
}

function Export-Settings {
    try {
        $null = New-Item -ItemType Directory -Path $script:SaveDir -Force
        $out = [ordered]@{}
        foreach ($k in ($script:Settings.Keys | Sort-Object)) { $out[$k] = $script:Settings[$k] }
        $out.Bind = [ordered]@{}; foreach ($k in $script:BindDefaults.Keys) { $out.Bind[$k] = $script:Bind[$k] }
        $out | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath (Get-SettingsPath) -Encoding utf8
    }
    catch { }
}

# Puts the settings into effect (those that can change while the game runs).
function Update-Settings {
    $s = $script:Settings
    if ($script:Mixer) { $script:Mixer::SfxVolume = [single]$s.Sfx; $script:Mixer::MusicVolume = [single]$s.Music }
    $script:ShowMiniMap = [bool]$s.MiniMap; $script:ShowFps = [bool]$s.Fps
    if ([bool]$s.FlatFloors -ne [bool]$script:FlatFloors) { $script:FlatFloors = [bool]$s.FlatFloors; if ($script:Tiles) { Set-Background } }
}

function Get-KeyName([int]$Code) {
    switch ($Code) { 16 { 'Shift' } 17 { 'Ctrl' } 18 { 'Alt' } 32 { 'Space' } 37 { 'Left' } 38 { 'Up' } 39 { 'Right' } 40 { 'Down' } 9 { 'Tab' } 1 { 'Mouse 1' } 2 { 'Mouse 2' }
        default { if (($Code -ge 48 -and $Code -le 57) -or ($Code -ge 65 -and $Code -le 90)) { [string][char]$Code } else { "$([System.Windows.Forms.Keys]$Code)" } } }
}

# The rows of the menu: @{ Text; Kind = slider|toggle|key|action; Key }
function Get-OptionRows {
    $s = $script:Settings
    $bar = { param($v, $max) ([string][char]0x2588) * [int][Math]::Round(12 * $v / $max) + ([string][char]0x2591) * (12 - [int][Math]::Round(12 * $v / $max)) }
    $rows = [System.Collections.Generic.List[hashtable]]::new()
    $rows.Add(@{ Kind = 'slider'; Key = 'Mouse'; Step = 0.02; Min = 0.02; Max = 0.5; Text = ('{0,-22} {1}  {2:0.00}' -f 'Mouse sensitivity', (& $bar $s.Mouse 0.5), $s.Mouse) })
    $rows.Add(@{ Kind = 'slider'; Key = 'Sfx'; Step = 0.05; Min = 0.0; Max = 1.0; Text = ('{0,-22} {1}  {2,3:0} %' -f 'Effects and voices', (& $bar $s.Sfx 1.0), ($s.Sfx * 100)) })
    $rows.Add(@{ Kind = 'slider'; Key = 'Music'; Step = 0.05; Min = 0.0; Max = 1.0; Text = ('{0,-22} {1}  {2,3:0} %' -f 'Music', (& $bar $s.Music 1.0), ($s.Music * 100)) })
    $rows.Add(@{ Kind = 'toggle'; Key = 'MiniMap'; Text = ('{0,-22} {1}' -f 'Radar', $(if ($s.MiniMap) { 'on' } else { 'off' })) })
    $rows.Add(@{ Kind = 'toggle'; Key = 'Fps'; Text = ('{0,-22} {1}' -f 'Frames per second', $(if ($s.Fps) { 'shown' } else { 'hidden' })) })
    $rows.Add(@{ Kind = 'toggle'; Key = 'FlatFloors'; Text = ('{0,-22} {1}' -f 'Floors and ceilings', $(if ($s.FlatFloors) { 'plain (faster)' } else { 'textured' })) })
    $rows.Add(@{ Kind = 'slider'; Key = 'Scale'; Step = 1; Min = 2; Max = 5; Text = ('{0,-22} {1} x 320x240   (from the next start)' -f 'Window size', $s.Scale) })
    foreach ($k in $script:BindDefaults.Keys) { $rows.Add(@{ Kind = 'key'; Key = $k; Text = ('{0,-22} {1}' -f "Key: $($script:BindLabels[$k])", (Get-KeyName $script:Bind[$k])) }) }
    $rows.Add(@{ Kind = 'action'; Key = 'Reset'; Text = 'Reset everything to the defaults' })
    $rows
}

function Open-Options {
    $script:Options.Return = $script:Mode; $script:Options.Waiting = $false
    Set-Mode 'options'
}

function Update-Options([int[]]$Keys) {
    $o = $script:Options; $s = $script:Settings; $vk = $script:VK
    $rows = @(Get-OptionRows)
    foreach ($k in $Keys) {
        $row = $rows[$o.Row]
        if ($o.Waiting) {
            # the next key pressed becomes the key for this action
            $o.Waiting = $false
            if ($k -eq $vk.Esc) { continue }
            if ($k -in $script:BindReserved) { $o.Note = "$(Get-KeyName $k) is taken by the game itself"; continue }
            foreach ($other in @($script:Bind.Keys)) { if ($script:Bind[$other] -eq $k -and $other -ne $row.Key) { $script:Bind[$other] = $script:Bind[$row.Key] } }      # swap
            $script:Bind[$row.Key] = $k; $o.Note = ''
            continue
        }
        if ($k -eq $vk.Esc) { Export-Settings; Update-Settings; Set-Mode $o.Return; $script:HudDirty = $true; return }
        elseif ($k -eq $vk.Up) { $o.Row = ($o.Row + $rows.Count - 1) % $rows.Count }
        elseif ($k -eq $vk.Down) { $o.Row = ($o.Row + 1) % $rows.Count }
        elseif ($row.Kind -eq 'slider' -and $k -in $vk.Left, $vk.Right) {
            $dir = if ($k -eq $vk.Left) { -1 } else { 1 }
            $s[$row.Key] = [Math]::Round([Math]::Max($row.Min, [Math]::Min($row.Max, $s[$row.Key] + $dir * $row.Step)), 2)
            if ($row.Key -eq 'Scale') { $s.Scale = [int]$s.Scale }
            Update-Settings
            if ($row.Key -eq 'Sfx') { Start-Sfx 'pickup' }
        }
        elseif ($row.Kind -eq 'toggle' -and $k -in $vk.Left, $vk.Right, $vk.Enter) { $s[$row.Key] = -not $s[$row.Key]; Update-Settings }
        elseif ($row.Kind -eq 'key' -and $k -eq $vk.Enter) { $o.Waiting = $true; $o.Note = '' }
        elseif ($row.Kind -eq 'action' -and $k -eq $vk.Enter) {
            foreach ($b in $script:BindDefaults.Keys) { $script:Bind[$b] = $script:BindDefaults[$b] }
            $s.Mouse = 0.12; $s.Sfx = 0.7; $s.Music = 0.45; $s.MiniMap = $true; $s.Fps = $false; $s.FlatFloors = $false; $s.Scale = 3
            Update-Settings; $o.Note = 'Back to the defaults.'
        }
    }
}

# The menu as lines of text: @(text, colour, selected, what it is for) - for the window and for the terminal alike.
function Get-OptionLines {
    $o = $script:Options
    $lines = [System.Collections.Generic.List[object]]::new()
    $lines.Add(@('OPTIONS', 'FFFFFF', $false)); $lines.Add(@('', 'FFFFFF', $false))
    $rows = @(Get-OptionRows)
    for ($i = 0; $i -lt $rows.Count; $i++) {
        $text = $rows[$i].Text
        if ($i -eq $o.Row -and $o.Waiting) { $text = ('{0,-22} press the new key ...  (Esc = leave it)' -f "Key: $($script:BindLabels[$rows[$i].Key])") }
        $help = if ($i -eq $o.Row -and $o.Waiting) { '' } else { "$($script:OptionHelp[$rows[$i].Key])" }
        $lines.Add(@("  $text", $(if ($rows[$i].Kind -eq 'key') { 'C0C8D8' } else { 'FFFFFF' }), ($i -eq $o.Row), $help))
        if ($i -eq 6 -or $i -eq $rows.Count - 2) { $lines.Add(@('', 'FFFFFF', $false)) }
    }
    $lines.Add(@('', 'FFFFFF', $false))
    $lines.Add(@('Up/Down select     Left/Right change     Enter: toggle, or choose a new key     Esc: save and go back', 'FFE860', $false))
    $lines.Add(@('Fixed: arrows up/down also move, mouse buttons fire and use, J fires, E uses, 1-9 weapons, F-keys.', '7080A0', $false))
    if ($o.Note) { $lines.Add(@($o.Note, 'FF8070', $false)) }
    $lines
}

function Show-Options {
    $g = $script:BackG; $sc = $script:Scale
    Write-HudBar 'FF0A1020' 0 0 320 240
    Write-HudBar 'FF2C54C4' 0 0 320 1.5
    $y = 6.0
    foreach ($line in (Get-OptionLines)) {
        if ($line[2]) { Write-HudBar 'FF2C54C4' 4 ($y - 0.5) 312 6.4 }
        $g.DrawString($line[0], $script:Fonts.Term, (Get-Brush $line[1]), [single](8 * $sc), [single]($y * $sc))
        if ($line.Count -gt 3 -and $line[3]) { $g.DrawString($line[3], $script:Fonts.Term, (Get-Brush $(if ($line[2]) { 'FFFFFF' } else { '7080A0' })), [single](126 * $sc), [single]($y * $sc)) }
        $y += 5.9
    }
}
