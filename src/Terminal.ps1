# POLF 3D - Copyright (c) 2026 oNdsen. Licensed under the MIT License, see LICENSE.

# Terminal.ps1 - the game without a window (-Terminal): the view is drawn into the terminal with
# half-block characters and 24 bit colours, status bar and menus are plain text. Needs a terminal
# that understands ANSI sequences (Windows Terminal does) - the bigger its window, the finer the picture.
#
# The main loop in Game.ps1 stays the same; it calls Read-TerminalKeys instead of pumping window
# messages and Show-TerminalFrame instead of blitting. Keyboard: a console reports key presses but no
# releases, so by default Windows is asked directly which keys are down. Over SSH that would be the
# wrong keyboard - there (or with -TerminalKeys) the key presses of the terminal are used and a key
# counts as held for a moment after each repeat; fire is J then, because Ctrl alone never arrives.

$script:TerminalMode = $false

function Initialize-Terminal([bool]$KeysOnly) {
    $script:TerminalMode = $true
    $class = Import-CSharpClass 'src/Terminal.cs' 'PolfTerminal'
    if (-not $class) { throw 'Terminal mode needs src/Terminal.cs to compile.' }
    $remote = [bool]($env:SSH_CONNECTION -or $env:SSH_CLIENT)
    $script:Term = @{
        Class = $class; Sb = [System.Text.StringBuilder]::new(400000)
        Async = -not $KeysOnly -and -not $remote
        Held = @{}; LastMode = ''; LastSize = ''; LastFrame = 0.0; Frames = 0
        Codes = @(@($script:VK.Values | Where-Object { $_ -gt 2 }) + (49..57) + 9, 8, 33, 34 | Sort-Object -Unique)
    }
    $script:KeyDown = [bool[]]::new(256)
    $script:KeyHit = [System.Collections.Generic.Queue[int]]::new()
    try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8; [Console]::CursorVisible = $false } catch { }
    [Console]::Out.Write("`e[2J`e[H")
}

function Stop-Terminal {
    if (-not $script:TerminalMode) { return }
    [Console]::Out.Write("`e[0m`e[2J`e[H")
    try { [Console]::CursorVisible = $true; while ([Console]::KeyAvailable) { $null = [Console]::ReadKey($true) } } catch { }
}

function Read-TerminalKeys {
    $t = $script:Term; $down = $script:KeyDown
    if ($t.Async) {
        foreach ($vk in $t.Codes) {
            $is = $t.Class::IsDown($vk)
            if ($is -and -not $down[$vk]) { $script:KeyHit.Enqueue($vk) }
            $down[$vk] = $is
        }
        try { while ([Console]::KeyAvailable) { $null = [Console]::ReadKey($true) } } catch { }      # nothing may pile up in the input buffer
        return
    }
    $now = $script:Clock.Elapsed.TotalSeconds
    try {
        while ([Console]::KeyAvailable) {
            $k = [Console]::ReadKey($true)
            $vk = [int]$k.Key
            if ($vk -le 0 -or $vk -gt 255) { continue }
            if (-not $down[$vk]) { $script:KeyHit.Enqueue($vk) }
            $down[$vk] = $true; $t.Held[$vk] = $now + 0.35
            if ($k.Modifiers -band [ConsoleModifiers]::Shift) { $down[16] = $true; $t.Held[16] = $now + 0.35 }
        }
    }
    catch { }
    foreach ($vk in @($t.Held.Keys)) { if ($now -gt $t.Held[$vk]) { $down[$vk] = $false; $t.Held.Remove($vk) } }
}

function Get-TerminalBar([double]$Fraction, [int]$Width) {
    $full = [int][Math]::Round([Math]::Max(0.0, [Math]::Min(1.0, $Fraction)) * $Width)
    ([string][char]0x2588) * $full + ([string][char]0x2591) * ($Width - $full)
}

function Get-TerminalFace {
    $f = (Get-FaceKey).Split('|')
    if ($f[0] -eq '5') { return '(x_x)' }
    switch ($f[1]) {
        'pain'  { '(>_<)' } 'grin' { '(^_^)' } 'rage' { '(ò_ó)' } 'sneak' { '(-_-)' } 'sudo' { '(⌐■_■)' } 'god' { '(◉_◉)' }
        default { if ([int]$f[0] -ge 4) { '(×_•;)' } elseif ([int]$f[0] -ge 2) { '(•_•;)' } else { '(•_•)' } }
    }
}

# The text screens: title, load, game over, floor completed.
function Get-TerminalScreen([string]$Mode) {
    $c = "`e[38;2;64;224;255m"; $y = "`e[38;2;255;232;96m"; $w = "`e[97m"; $d = "`e[38;2;112;128;160m"; $r = "`e[0m"
    $lines = [System.Collections.Generic.List[string]]::new()
    switch ($Mode) {
        'title' {
            foreach ($l in '  ____   ___  _     _____   _____ ____      __', ' |  _ \ / _ \| |   |  ___| |___ /|  _ \    \ \', ' | |_) | | | | |   | |_      |_ \| | | |    \ \', ' |  __/| |_| | |___|  _|    ___) | |_| |    / /  _____', ' |_|    \___/|_____|_|     |____/|____/    /_/  |_____|') { $lines.Add("$w$l$r") }
            $lines.Add("$c   a ray casting shooter in PowerShell - terminal edition$r"); $lines.Add('')
            $lines.Add("$d   DIFFICULTY  (arrow keys, Enter = start)$r")
            for ($i = 0; $i -lt 4; $i++) { $lines.Add($(if ($i -eq $script:Difficulty) { "$w > $($i + 1)  $($script:Difficulties[$i].Name)$r" } else { "$d   $($i + 1)  $($script:Difficulties[$i].Name)$r" })) }
            $lines.Add('')
            if ($script:Net) { $lines.Add("$c   $(Get-NetStatus)$r") }
            if (-not $script:Net) { $lines.Add("$c   G = today's dungeon #$(Get-DailySeed)$r") }
            $lines.Add("$y   $(if ($script:HasSaves -and -not $script:Net) { 'L = load a saved game     ' })T = speedrun clock $(if ($script:Speedrun) { 'ON' } else { 'off' })     Esc = quit$r"); $lines.Add('')
            $lines.Add("$d   W/S move   A/D strafe   arrows turn   Shift run   C sneak   Ctrl or J fire   Space/E use   1-9 weapon$r")
            $lines.Add("$d   Z -WhatIf  X -Confirm  V -Verbose  F -Force  R Undo   T console   P pause   F4 music   F5/F9 save/load$r"); $lines.Add('')
            $lines.Add("$d   HIGH SCORES$r")
            foreach ($h in @($script:HighScores | Select-Object -First 5)) { $lines.Add(('   {0,-12} {1,7}  {2}' -f $h.Name, $h.Score, $h.Result)) }
            $lines.Add(''); $lines.Add("$d   POLF 3D  $($script:Copyright)$r")
        }
        'load' {
            $lines.Add("$w   LOAD GAME$r"); $lines.Add('')
            for ($i = 0; $i -lt $script:SaveList.Count; $i++) { $lines.Add("   $($i + 1)   $($script:SaveList[$i].Text)") }
            $lines.Add(''); $lines.Add("$y   press the number of a saved game     Esc = back$r")
        }
        'gameover' { $lines.Add(''); $lines.Add("`e[38;2;255;64;48m   G A M E   O V E R$r"); $lines.Add(''); $lines.Add("   Score: $($script:P.Score)"); $lines.Add(''); $lines.Add("$y   Enter = main menu$r") }
        'done' {
            $res = $script:Result
            $lines.Add("$w   $(if ($res.Last) { 'SHELLSTEIN HAS FALLEN!' } elseif ($script:BonusMap) { 'SECRET FLOOR COMPLETED!' } else { "FLOOR $($script:LevelIndex + 1) COMPLETED!" })$r"); $lines.Add('')
            foreach ($row in @('Time', (Format-Time $res.Exact -Tenths)), @('Par', (Format-Time $script:ParSeconds)), @('Kills', "$($res.Kills) %"), @('Secrets', "$($res.Secrets) %"), @('Treasures', "$($res.Treasures) %"), @('Bonus', "$($res.Bonus)"), @('Score', "$($script:P.Score)")) {
                $lines.Add(("   $d{0,-12}$r {1}" -f $row[0], $row[1]))
            }
            if ($res.Transcript) { $lines.Add(''); $lines.Add("$d   `"$($res.Transcript.Verdict)`"$r") }
            $lines.Add(''); $lines.Add("$y   $(if ($res.Last) { 'All floors completed - thanks for playing!   Enter = main menu' } elseif ($res.ToBonus) { 'This lift goes somewhere it should not ...   Enter = find out' } else { 'Enter = take the lift to the next floor' })$r")
        }
    }
    $lines
}

# Called by the main loop where the window version blits its back buffer.
function Show-TerminalFrame {
    $t = $script:Term; $sb = $t.Sb; $mode = $script:Mode
    $now = $script:Clock.Elapsed.TotalSeconds
    $wait = 0.033 - ($now - $t.LastFrame)
    if ($wait -gt 0.002) { [System.Threading.Thread]::Sleep([int]($wait * 1000)) }
    $t.LastFrame = $script:Clock.Elapsed.TotalSeconds; $t.Frames++

    $cw = 120; $ch = 40
    try { $cw = [Console]::WindowWidth; $ch = [Console]::WindowHeight } catch { }
    $null = $sb.Clear()
    if ($mode -ne $t.LastMode -or "$cw,$ch" -ne $t.LastSize) { $null = $sb.Append("`e[0m`e[2J"); $t.LastMode = $mode; $t.LastSize = "$cw,$ch" }
    $null = $sb.Append("`e[H")

    if ($mode -in 'play', 'paused', 'dying', 'demo') {
        $rows = [Math]::Max(8, $ch - 6)
        $cols = [Math]::Min($cw - 1, [int]($rows * 3.2))
        $rows = [Math]::Min($rows, [int]($cols / 3.2))
        $indent = [Math]::Max(0, [int](($cw - $cols) / 2))
        $tint = 0
        if ($mode -eq 'dying') { $tint = ([int][Math]::Min(230, [Math]::Max(0, ($script:ModeTics - 40) * 3)) -shl 24) -bor 0xA00000 }
        elseif ($script:DamageFlash -gt 0) { $tint = ([int][Math]::Min(150, 30 + $script:DamageFlash * 5) -shl 24) -bor 0xD00000 }
        elseif ($script:BonusFlash -gt 0) { $tint = ([int][Math]::Min(70, $script:BonusFlash * 4) -shl 24) -bor 0xFFF8C0 }
        elseif ($script:WhatIfTics -gt 0) { $tint = (50 -shl 24) -bor 0x40E0FF }
        elseif ($script:ConfirmTics -gt 0) { $tint = (36 -shl 24) -bor 0xF9F1A5 }
        elseif ($script:ForceFlash -gt 0 -or $script:MuzzleFlash -gt 0) { $tint = (40 -shl 24) -bor 0xFFE8A0 }
        $t.Class::Ansi($script:FB, $script:ViewW, $script:ViewH, $cols, $rows, $indent, $tint, $sb)

        $p = $script:P; $st = $script:Stats; $res = Get-WeaponResource
        $pad = ' ' * $indent
        $hpColor = if ($p.Health -le 25) { "`e[38;2;255;80;64m" } elseif ($p.Health -le 50) { "`e[38;2;255;192;64m" } else { "`e[38;2;96;255;128m" }
        $keys = "$(if ($p.KeyGold) { "`e[38;2;232;192;32mgold " })$(if ($p.KeySilver) { "`e[38;2;208;216;224msilver " })"
        $null = $sb.Append("$pad`e[97m$(Get-TerminalFace) $hpColor$([char]0x2665) $($p.Health.ToString().PadLeft(3)) $(Get-TerminalBar ($p.Health / 100.0) 10)`e[97m  $($res.Label) $($res.Text)  `e[38;2;64;224;255m$($script:Weapons[$p.Weapon].Name.ToUpper())`e[97m  $keys`e[38;2;143;176;255mPRIV $(Get-TerminalBar ($p.Privilege / 100.0) 8)`e[0m`e[K`n")
        $floor = if ($script:BonusMap) { 'BONUS' } else { "FLOOR $($script:LevelIndex + 1)" }
        $null = $sb.Append("$pad`e[38;2;160;180;208m$floor  SCORE $('{0:000000}' -f $p.Score)  LIVES $($p.Lives)   KILLS $($st.Kills)/$($st.KillTotal)  SECRETS $($st.Secrets)/$($st.SecretTotal)  TREASURE $($st.Treasures)/$($st.TreasureTotal)$(if ($script:ShowFps) { "   $([int]$script:Fps) fps" })`e[0m`e[K`n")
        $bossLine = ''
        foreach ($a in $script:Actors) { if ($a.Shootable -and $a.AttackMode -and $script:BossNames.ContainsKey($a.Kind)) { $bossLine = "$($script:BossNames[$a.Kind])  $(Get-TerminalBar ($a.HP / [double]$a.Def.HP[$script:Difficulty]) 20)"; break } }
        $msg = if ($mode -eq 'paused') { 'PAUSE   Esc/P = resume   1-3 = save to slot   L = load   Q = main menu' } elseif ($mode -eq 'demo') { 'DEMO - press any key' }
               elseif ($script:Message -and $now -lt $script:MessageUntil) { $script:Message } elseif ($bossLine) { $bossLine } else { '' }
        $null = $sb.Append("$pad`e[38;2;255;232;96m$msg`e[0m`e[K`n")
        $cheats = @(if ($script:GodMode) { 'GOD' }; if ($script:InfiniteAmmo) { 'AMMO' }; if ($script:OneHitKill) { '1-HIT' }; if ($p.Sneaking) { 'SNEAKING' }; if ($p.SudoTics -gt 0) { "SUDO $([Math]::Ceiling($p.SudoTics / 70))s" }) -join '  '
        $null = $sb.Append("$pad`e[38;2;255;96;255m$cheats`e[0m`e[K`n`e[J")
    }
    else {
        foreach ($line in (Get-TerminalScreen $mode)) { $null = $sb.Append($line).Append("`e[K`n") }
        $null = $sb.Append("`e[J")
    }
    [Console]::Out.Write($sb.ToString())
}

# The console needs no drawing here: it is a console. The world waits while lines are read.
function Invoke-TerminalConsole {
    $con = $script:Con
    [Console]::Out.Write("`e[0m`e[2J`e[H")
    foreach ($line in @($con.Lines | Select-Object -Last 12)) { [Console]::Out.WriteLine($line[0]) }
    try { [Console]::CursorVisible = $true } catch { }
    while ($script:Mode -eq 'console') {
        try { while ([Console]::KeyAvailable) { $null = [Console]::ReadKey($true) } } catch { }
        [Console]::Out.Write("`e[38;2;249;241;165m$(Get-ConsolePrompt)`e[0m")
        $text = [Console]::ReadLine()
        if ([string]::IsNullOrWhiteSpace($text)) { Close-Console; break }
        $from = $con.Lines.Count + 1                               # skip the echo of the line itself
        Invoke-ConsoleLine $text
        for ($i = $from; $i -lt $con.Lines.Count; $i++) {
            $rgb = $con.Lines[$i][1]
            [Console]::Out.WriteLine("`e[38;2;$([Convert]::ToInt32($rgb.Substring(0, 2), 16));$([Convert]::ToInt32($rgb.Substring(2, 2), 16));$([Convert]::ToInt32($rgb.Substring(4, 2), 16))m$($con.Lines[$i][0])`e[0m")
        }
    }
    try { [Console]::CursorVisible = $false } catch { }
    [Array]::Clear($script:KeyDown, 0, 256); $script:KeyHit.Clear()
    $script:Term.LastMode = ''
}
