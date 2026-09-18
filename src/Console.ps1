# POLF 3D - Copyright (c) 2026 oNdsen. Licensed under the MIT License, see LICENSE.

# Console.ps1 - a PowerShell console inside the game (T or Tab, or "use" a terminal in the level).
#
# It is a REAL PowerShell: pipelines, Where-Object, Sort-Object, script blocks - running in a second
# runspace that has been stripped to the bone. The session state is created empty (no providers, so
# no file system; no external programs), a dozen harmless cmdlets are added back, the language mode is
# ConstrainedLanguage (no .NET calls), and every line gets two seconds before it is stopped.
#
# The game's cmdlets live in that sandbox and cannot touch the game at all: Get-Enemy & co. return
# copies made when the line is run, and Stop-Enemy & co. merely OUTPUT a request. The game picks those
# requests out of the pipeline's output, checks the price in privilege and carries them out.

$script:Con = $null

$script:ConsoleHelp = @'
LOOK          Get-Enemy [-Kind guard]   Get-Door   Get-Loot [-Name clip*]   Get-Trap   Get-Player   Get-Secret (20)
READ          At a terminal or server rack:  Get-ChildItem (ls, dir)   Get-Content <file> (cat, type)
              What the files give away:      Unlock-Door -Code <number>      Use-Token <word>
ACT           Stop-Enemy (10 + half his health)     Suspend-Enemy (12, eight seconds)
              Open-Door (8, locked ones 25)   Close-Door (5)   Lock-Door (15, jams it for twenty seconds)
              Disable-Trap (10)
              Every one of them takes -Id or objects from the pipeline, and -WhatIf tells you the price first.
PIPE          Where-Object (?)  Sort-Object (sort)  Select-Object (select)  ForEach-Object (%)  Measure-Object
              Group-Object  Format-Table (ft)  Format-List (fl)  Get-Member (gm)  Get-Random
TRY           Get-Enemy | Sort-Object Distance | Select-Object -First 1 | Stop-Enemy -WhatIf
              Get-Door | Where-Object Lock -ne '-' | Open-Door
              Get-Enemy | ? State -eq 'attacking' | Suspend-Enemy
LEAVE         exit, Esc, T or Tab.   cls clears the screen.   Numbers in brackets: the price in privilege.
'@

function Initialize-Console {
    $iss = [System.Management.Automation.Runspaces.InitialSessionState]::Create()
    $iss.LanguageMode = [System.Management.Automation.PSLanguageMode]::ConstrainedLanguage
    $cmdlets = [ordered]@{
        'Where-Object' = [Microsoft.PowerShell.Commands.WhereObjectCommand]; 'ForEach-Object' = [Microsoft.PowerShell.Commands.ForEachObjectCommand]
        'Select-Object' = [Microsoft.PowerShell.Commands.SelectObjectCommand]; 'Sort-Object' = [Microsoft.PowerShell.Commands.SortObjectCommand]
        'Measure-Object' = [Microsoft.PowerShell.Commands.MeasureObjectCommand]; 'Group-Object' = [Microsoft.PowerShell.Commands.GroupObjectCommand]
        'Format-Table' = [Microsoft.PowerShell.Commands.FormatTableCommand]; 'Format-List' = [Microsoft.PowerShell.Commands.FormatListCommand]
        'Out-String' = [Microsoft.PowerShell.Commands.OutStringCommand]; 'Get-Member' = [Microsoft.PowerShell.Commands.GetMemberCommand]
        'Write-Output' = [Microsoft.PowerShell.Commands.WriteOutputCommand]; 'Get-Random' = [Microsoft.PowerShell.Commands.GetRandomCommand]
    }
    foreach ($c in $cmdlets.GetEnumerator()) { $iss.Commands.Add([System.Management.Automation.Runspaces.SessionStateCmdletEntry]::new($c.Key, $c.Value, $null)) }

    $functions = [ordered]@{
        'Get-Enemy'   = 'param([string]$Kind = "*") $PolfEnemies | Where-Object Kind -like $Kind'
        'Get-Door'    = '$PolfDoors'
        'Get-Loot'    = 'param([string]$Name = "*") $PolfLoot | Where-Object Name -like $Name'
        'Get-Trap'    = '$PolfTraps'
        'Get-Player'  = '$PolfPlayer'
        'Get-Secret'  = '[pscustomobject]@{ PolfAction = "Get-Secret"; Id = 0; WhatIf = $false }'
        'Get-Help'    = '$PolfHelp'
        'Get-Command' = '$PolfCommands'
        'whoami'      = '"shellstein\intruder"'
        'sudo'        = '"sudo: you are already root of your own misfortune."'
        'Remove-Item' = '"Remove-Item: nice try. This console is a sandbox - the only thing you can delete from here is the opposition."'
        'Invoke-WebRequest' = '"Invoke-WebRequest: no route to host. The only network down here wants you dead."'
        'Get-ChildItem' = 'if ($PolfFiles) { $PolfFiles } else { "No file system here. Log on at a terminal or a server rack in the building: walk up to it and press use." }'
        'Get-Content' = 'param([Parameter(Position = 0)][string]$Path = "*") $hit = $PolfFiles | Where-Object Name -like $Path | Select-Object -First 1; if ($hit) { $PolfFileText[$hit.Name] } elseif ($PolfFiles) { throw "Cannot find path ''$Path'' because it does not exist." } else { throw "No file system here. Log on at a terminal first." }'
        'Unlock-Door' = 'param([Parameter(Position = 0)][string]$Code) [pscustomobject]@{ PolfAction = "Use-Code"; Id = 0; WhatIf = $false; Value = $Code }'
        'Use-Token' = 'param([Parameter(Position = 0)][string]$Token) [pscustomobject]@{ PolfAction = "Use-Code"; Id = 0; WhatIf = $false; Value = $Token }'
        'Get-Process' = '$PolfEnemies | Select-Object Id, @{ n = "ProcessName"; e = { $_.Kind } }, @{ n = "WS(HP)"; e = { $_.Health } }, State'
    }
    # the acting cmdlets all look the same: ids in, requests out
    foreach ($act in @('Stop-Enemy', 'Enemy'), @('Suspend-Enemy', 'Enemy'), @('Open-Door', 'Door'), @('Close-Door', 'Door'), @('Lock-Door', 'Door'), @('Disable-Trap', 'Trap')) {
        $functions[$act[0]] = @"
[CmdletBinding()] param([Parameter(ValueFromPipeline)]`$InputObject, [int[]]`$Id, [switch]`$WhatIf)
process {
    if (`$null -ne `$InputObject -and `$InputObject.Type -ne '$($act[1])') { throw "$($act[0]): that is no $($act[1].ToLower()) (it is a `$(`$InputObject.Type)). Try Get-$($act[1]) | $($act[0])" }
    foreach (`$i in @(`$Id) + @(`$InputObject.Id)) { if (`$null -ne `$i) { [pscustomobject]@{ PolfAction = '$($act[0])'; Id = [int]`$i; WhatIf = [bool]`$WhatIf } } }
}
"@
    }
    foreach ($f in $functions.GetEnumerator()) { $iss.Commands.Add([System.Management.Automation.Runspaces.SessionStateFunctionEntry]::new($f.Key, $f.Value)) }
    foreach ($a in @('?', 'Where-Object'), @('where', 'Where-Object'), @('%', 'ForEach-Object'), @('foreach', 'ForEach-Object'), @('select', 'Select-Object'), @('sort', 'Sort-Object'),
        @('measure', 'Measure-Object'), @('group', 'Group-Object'), @('ft', 'Format-Table'), @('fl', 'Format-List'), @('gm', 'Get-Member'), @('echo', 'Write-Output'),
        @('help', 'Get-Help'), @('man', 'Get-Help'), @('gcm', 'Get-Command'), @('kill', 'Stop-Enemy'), @('spps', 'Stop-Enemy'), @('ps', 'Get-Process'), @('gps', 'Get-Process'),
        @('ls', 'Get-ChildItem'), @('dir', 'Get-ChildItem'), @('gci', 'Get-ChildItem'), @('cat', 'Get-Content'), @('type', 'Get-Content'), @('gc', 'Get-Content'), @('more', 'Get-Content'), @('rm', 'Remove-Item'), @('del', 'Remove-Item'), @('iwr', 'Invoke-WebRequest'), @('curl', 'Invoke-WebRequest')) {
        $iss.Commands.Add([System.Management.Automation.Runspaces.SessionStateAliasEntry]::new($a[0], $a[1]))
    }
    $rs = [runspacefactory]::CreateRunspace($iss); $rs.Open()
    $rs.SessionStateProxy.SetVariable('PolfHelp', $script:ConsoleHelp)
    $rs.SessionStateProxy.SetVariable('PolfCommands', @(@($functions.Keys) + @($cmdlets.Keys) | Sort-Object))
    $script:Con = @{
        Runspace = $rs; Lines = [System.Collections.Generic.List[object]]::new(); Input = ''; History = [System.Collections.Generic.List[string]]::new(); HistoryAt = 0
        Scroll = 0; Opened = 0.0
    }
    $script:CharQueue = [System.Collections.Generic.Queue[char]]::new()
}

function Write-ConsoleLine([string]$Text, [string]$Color = 'EEEDF0') {
    foreach ($line in ($Text -replace "`r", '').Split("`n")) { $script:Con.Lines.Add(@($line, $Color)) }
    while ($script:Con.Lines.Count -gt 300) { $script:Con.Lines.RemoveAt(0) }
    $script:Con.Scroll = 0
}

function Get-Bearing([double]$X, [double]$Y) {
    $dx = $X - $script:P.X; $dy = $script:P.Y - $Y                # north is up
    if ([Math]::Abs($dx) + [Math]::Abs($dy) -lt 0.8) { return 'here' }
    ('E', 'NE', 'N', 'NW', 'W', 'SW', 'S', 'SE')[[int][Math]::Round(([Math]::Atan2($dy, $dx) * 180 / [Math]::PI + 360) % 360 / 45) % 8]
}

function Get-Range([double]$X, [double]$Y) { [Math]::Round([Math]::Sqrt(($X - $script:P.X) * ($X - $script:P.X) + ($Y - $script:P.Y) * ($Y - $script:P.Y)), 1) }

# What the sandbox gets to see: copies, made afresh for every line.
function Update-ConsoleData {
    $proxy = $script:Con.Runspace.SessionStateProxy; $p = $script:P
    $enemies = foreach ($a in $script:Actors) {
        if (-not $a.Shootable -or $a.Def.Inert -or $a.Kind -in 'peer', 'whatif') { continue }
        $state = if ($a.Stun -gt 0) { 'suspended' } elseif ($a.AttackMode) { 'attacking' } elseif ($a.React -gt 0) { 'alerted' } elseif ($a.State -like '*.path*') { 'patrolling' } else { 'unaware' }
        [pscustomobject]@{ Type = 'Enemy'; Id = $a.NetId; Kind = $a.Kind; Health = $a.HP; State = $state; Distance = (Get-Range $a.X $a.Y); Bearing = (Get-Bearing $a.X $a.Y) }
    }
    $doors = for ($i = 0; $i -lt $script:Doors.Count; $i++) {
        $d = $script:Doors[$i]
        $lock = switch ($d.Lock) { 1 { 'gold' } 2 { 'silver' } 3 { 'lift' } 4 { "lever $($d.Channel)" } default { '-' } }
        if ($d.Lock -in 1, 2, 4 -and $d.Unlocked) { $lock = '-' }
        [pscustomobject]@{ Type = 'Door'; Id = $i; Lock = $lock; State = $(if ($d.Jam -gt 0) { 'jammed' } else { $d.Action }); Distance = (Get-Range ($d.X + 0.5) ($d.Y + 0.5)); Bearing = (Get-Bearing ($d.X + 0.5) ($d.Y + 0.5)) }
    }
    $loot = for ($i = 0; $i -lt $script:Items.Count; $i++) {
        $s = $script:Items[$i]
        if (-not $s.Removed) { [pscustomobject]@{ Type = 'Loot'; Id = $i; Name = $s.Item; Distance = (Get-Range ($s.X + 0.5) ($s.Y + 0.5)); Bearing = (Get-Bearing ($s.X + 0.5) ($s.Y + 0.5)) } }
    }
    $traps = for ($i = 0; $i -lt $script:Traps.Count; $i++) {
        $t = $script:Traps[$i]
        [pscustomobject]@{ Type = 'Trap'; Id = $i; Kind = $t.Kind; Disabled = [bool]$t.Disabled; Distance = (Get-Range ($t.X + 0.5) ($t.Y + 0.5)); Bearing = (Get-Bearing ($t.X + 0.5) ($t.Y + 0.5)) }
    }
    $st = $script:Stats
    $player = [pscustomobject]@{ Type = 'Player'; Health = $p.Health; Ammo = $p.Ammo; Privilege = [int]$p.Privilege; Floor = $script:LevelName
        Kills = "$($st.Kills)/$($st.KillTotal)"; Secrets = "$($st.Secrets)/$($st.SecretTotal)"; Treasure = "$($st.Treasures)/$($st.TreasureTotal)" }
    # the files of this floor - but only at one of the building's own terminals
    $files = @(); $texts = @{}
    $floor = Get-StoryFloor
    if ($script:Con.AtTerminal -and $floor) {
        $files = foreach ($name in $floor.Files.Keys) { $texts[$name] = "$($floor.Files[$name])".TrimEnd(); [pscustomobject]@{ Type = 'File'; Mode = '-a---'; Length = $texts[$name].Length; Name = $name } }
    }
    $proxy.SetVariable('PolfFiles', @($files)); $proxy.SetVariable('PolfFileText', $texts)
    $proxy.SetVariable('PolfEnemies', @($enemies | Sort-Object Distance)); $proxy.SetVariable('PolfDoors', @($doors | Sort-Object Distance))
    $proxy.SetVariable('PolfLoot', @($loot | Sort-Object Distance)); $proxy.SetVariable('PolfTraps', @($traps | Sort-Object Distance)); $proxy.SetVariable('PolfPlayer', $player)
}

# Runs one line in the sandbox. Returns @{ Output = objects; Errors = strings }.
function Invoke-SandboxScript([string]$Text) {
    $ps = [powershell]::Create(); $ps.Runspace = $script:Con.Runspace
    try {
        $null = $ps.AddScript($Text)
        $async = $ps.BeginInvoke()
        if (-not $async.AsyncWaitHandle.WaitOne(2000)) { $ps.Stop(); return @{ Output = @(); Errors = @('The pipeline has been stopped: two seconds is all a line gets down here.') } }
        $out = @(); $errors = @()
        try { $out = @($ps.EndInvoke($async)) } catch { $e = $_.Exception; while ($e.InnerException) { $e = $e.InnerException }; $errors += $e.Message }
        foreach ($err in $ps.Streams.Error) { $errors += ($err.ToString() -split "`n")[0] }
        @{ Output = $out; Errors = $errors }
    }
    finally { $ps.Dispose() }
}

# The price of a request, or a string explaining why it cannot be done.
function Get-ConsoleActionCost([string]$Name, $Target) {
    switch ($Name) {
        'Stop-Enemy'    { if ($Target.Kind -in 'boss', 'uber', 'pilot') { "Access is denied: the $($Target.Kind) runs as SYSTEM" } else { 10 + [int][Math]::Ceiling($Target.HP / 2.0) } }
        'Suspend-Enemy' { if ($Target.Kind -in 'boss', 'uber', 'pilot') { 30 } else { 12 } }
        'Open-Door'     { if ($Target.Lock -in 1, 2, 4 -and -not $Target.Unlocked) { 25 } else { 8 } }
        'Close-Door'    { 5 }
        'Lock-Door'     { 15 }
        'Disable-Trap'  { 10 }
        'Get-Secret'    { 20 }
    }
}

function Invoke-ConsoleAction($Action) {
    $name = [string]$Action.PolfAction; $id = [int]$Action.Id; $p = $script:P
    if ($name -eq 'Use-Code') {
        $answer = Invoke-StoryCode ([string]$Action.Value)
        if ($answer) { Write-ConsoleLine $answer '60FF80'; Start-Sfx 'key' } else { Write-ConsoleLine "'$($Action.Value)' means nothing on this floor." 'F14C4C'; Start-Sfx 'noway' }
        return $true
    }
    $target = switch -Wildcard ($name) {
        '*-Enemy' { $script:Actors | Where-Object { $_.NetId -eq $id -and $_.Shootable -and -not $_.Def.Inert } | Select-Object -First 1 }
        '*-Door'  { if ($id -ge 0 -and $id -lt $script:Doors.Count) { $script:Doors[$id] } }
        '*-Trap'  { if ($id -ge 0 -and $id -lt $script:Traps.Count) { $script:Traps[$id] } }
        default   { $true }
    }
    if (-not $target) { Write-ConsoleLine "${name}: cannot find anything with Id $id." 'F14C4C'; return $true }
    $label = if ($name -like '*-Enemy') { "$($target.Kind) #$id" } elseif ($name -like '*-Door') { "door #$id" } elseif ($name -like '*-Trap') { "$($target.Kind) #$id" } else { 'this floor' }
    $cost = Get-ConsoleActionCost $name $target
    if ($cost -is [string]) { Write-ConsoleLine "${name}: $cost." 'F14C4C'; return $true }
    if ($Action.WhatIf) { Write-ConsoleLine "What if: Performing the operation `"$name`" on target `"$label`". It would cost $cost privilege." ; return $true }
    if ($p.Privilege -lt $cost -and -not $script:InfiniteAmmo) { Write-ConsoleLine "${name}: Access is denied - $label costs $cost privilege, you have $([int]$p.Privilege)." 'F14C4C'; return $false }
    switch ($name) {
        'Stop-Enemy'    { $script:KillCause = 'console'; Stop-Actor $target; $script:KillCause = $null; $done = 'terminated' }
        'Suspend-Enemy' { $target.Stun = 560.0; $done = 'suspended for eight seconds' }
        'Open-Door'     { if ($target.Lock -in 1, 2, 4) { $target.Unlocked = $true; if ($target.Lock -ne 4) { $target.Lock = 0; $target.TexId = $script:TEX_DOOR } }; $target.Jam = 0.0; Open-Door $id; $done = 'opening' }
        'Close-Door'    { Close-Door $id; $done = if ($target.Action -in 'closing', 'closed') { 'closing' } else { 'somebody is standing in it' } }
        'Lock-Door'     { Close-Door $id; $target.Jam = 1400.0; $done = 'jammed for twenty seconds (your own "use" frees it)' }
        'Disable-Trap'  { $target.Disabled = $true; $done = 'disabled' }
        'Get-Secret'    {
            $w = $script:MapW; $found = 0
            for ($i = 0; $i -lt $script:Tiles.Length; $i++) {
                $kind = if ($script:PushTex[$i] -ne 0) { 'a wall that can be pushed' } elseif ($script:Breakable[$i]) { 'a cracked wall (explosives, or -Force)' } else { continue }
                $x = $i % $w + 0.5; $y = [Math]::Floor($i / $w) + 0.5
                Write-ConsoleLine ("  {0,-40} {1,5} tiles {2}" -f $kind, (Get-Range $x $y), (Get-Bearing $x $y)) 'F9F1A5'; $found++
            }
            $done = "$found left on this floor"
        }
    }
    if (-not $script:InfiniteAmmo) { Add-Privilege (- $cost) }
    Write-ConsoleLine "${name}: $label - $done.  (-$cost privilege, $([int]$p.Privilege) left)" '60FF80'
    $true
}

function Invoke-ConsoleLine([string]$Text) {
    $con = $script:Con
    Write-ConsoleLine "$(Get-ConsolePrompt)$Text" 'F9F1A5'
    $Text = $Text.Trim()
    if (-not $Text) { return }
    if ($con.History.Count -eq 0 -or $con.History[$con.History.Count - 1] -ne $Text) { $con.History.Add($Text) }
    $con.HistoryAt = $con.History.Count
    if ($Text -match '^(exit|quit|logout)$') { Close-Console; return }
    if ($Text -match '^(cls|clear|Clear-Host)$') { $con.Lines.Clear(); return }

    Add-TranscriptLine "PS> $Text"
    Update-ConsoleData
    $result = Invoke-SandboxScript $Text
    $show = [System.Collections.Generic.List[object]]::new()
    $go = $true
    foreach ($o in $result.Output) {
        if ($null -eq $o) { continue }
        if ($o.PSObject.Properties['PolfAction']) { if ($go) { $go = Invoke-ConsoleAction $o } } else { $show.Add($o) }
    }
    if ($show.Count) {
        # the game's own objects get a tidy table; everything else is shown the way PowerShell shows it
        $proxy = $con.Runspace.SessionStateProxy; $proxy.SetVariable('PolfOut', $show.ToArray())
        $type = @($show | ForEach-Object { if ($_ -is [psobject] -and $_.PSObject.Properties['Type']) { $_.Type } else { '' } } | Select-Object -Unique)
        $script = if ($type.Count -eq 1 -and $type[0] -and $type[0] -ne 'Player') { '$PolfOut | Format-Table -AutoSize -Property ($PolfOut[0].PSObject.Properties.Name | Where-Object { $_ -ne "Type" }) | Out-String -Width 116' }
                  elseif ($type.Count -eq 1 -and $type[0] -eq 'Player') { '$PolfOut | Select-Object * -ExcludeProperty Type | Format-List | Out-String -Width 116' }
                  else { '$PolfOut | Out-String -Width 116' }
        $text = (Invoke-SandboxScript $script).Output -join "`n"
        Write-ConsoleLine $text.Trim("`r", "`n")
    }
    foreach ($e in $result.Errors) { Write-ConsoleLine $e 'F14C4C' }
}

function Get-ConsolePrompt { "PS Shellstein:\$(if ($script:BonusMap) { 'Treasury' } else { "Floor$($script:LevelIndex + 1)" })> " }

# ---------------------------------------------------------------------------------------------
# Opening, closing, typing, drawing
# ---------------------------------------------------------------------------------------------
# $TerminalIndex: the tile of the terminal it was opened at (-1: the player's own console).
function Open-Console([int]$TerminalIndex = -1) {
    if ($script:NetLive) { Show-Message 'No console in a shared world: it would have to stand still'; return }
    if ($script:Recording -or $script:Playback) { Show-Message $(if ($script:DungeonSeed) { 'No console in the dungeon: every run must be replayable' } else { 'No console while a demo is running' }); return }
    if (-not $script:Con) { Initialize-Console }
    Stop-WhatIf
    $con = $script:Con
    if ($con.Lines.Count -eq 0) {
        Write-ConsoleLine 'POLF PowerShell (sandboxed)' 'FFFFFF'
        Write-ConsoleLine 'The world stands still while you type. Get-Help shows what can be done, exit leaves.' 'A0A8B8'
        Write-ConsoleLine ''
    }
    if ($TerminalIndex -ge 0 -and -not $script:TerminalUsed[$TerminalIndex]) {
        $script:TerminalUsed[$TerminalIndex] = $true
        Add-Privilege 30
        Write-ConsoleLine "Logged on at a terminal of the house: +30 privilege ($([int]$script:P.Privilege) now)." '60FF80'
    }
    $con.AtTerminal = $TerminalIndex -ge 0
    if ($con.AtTerminal) { Write-ConsoleLine "This terminal has files: Get-ChildItem lists them, Get-Content <name> reads one." 'A0A8B8' }
    $con.Input = ''; $con.Scroll = 0; $con.Opened = $script:Clock.Elapsed.TotalSeconds
    $script:CharQueue.Clear()
    Set-Mode 'console'
}

function Close-Console {
    Set-Mode 'play'
    $script:HudDirty = $true
    $script:P.UseHeld = $true; $script:P.FireHeld = $true
}

# $Keys: the key codes pressed this frame. Characters come from the form's KeyPress event.
function Update-Console([int[]]$Keys) {
    $con = $script:Con
    $justOpened = $script:Clock.Elapsed.TotalSeconds - $con.Opened -lt 0.15
    foreach ($k in $Keys) {
        switch ($k) {
            27 { Close-Console; return }                                                             # Esc
            9  { if (-not $justOpened) { Close-Console; return } }                                  # Tab
            13 { $line = $con.Input; $con.Input = ''; $script:CharQueue.Clear(); Invoke-ConsoleLine $line; if ($script:Mode -ne 'console') { return } }
            8  { if ($con.Input.Length) { $con.Input = $con.Input.Substring(0, $con.Input.Length - 1) } }
            38 { if ($con.HistoryAt -gt 0) { $con.HistoryAt--; $con.Input = $con.History[$con.HistoryAt] } }
            40 { if ($con.HistoryAt -lt $con.History.Count - 1) { $con.HistoryAt++; $con.Input = $con.History[$con.HistoryAt] } else { $con.HistoryAt = $con.History.Count; $con.Input = '' } }
            33 { $con.Scroll = [Math]::Min([Math]::Max(0, $con.Lines.Count - 5), $con.Scroll + 10) }                                # PgUp
            34 { $con.Scroll = [Math]::Max(0, $con.Scroll - 10) }
        }
    }
    while ($script:CharQueue.Count) {
        $c = $script:CharQueue.Dequeue()
        if ($justOpened -or [int]$c -lt 32 -or [int]$c -eq 127) { continue }                          # the key that opened it, control characters
        if ($con.Input.Length -lt 110) { $con.Input += $c }
    }
}

function Show-Console {
    $con = $script:Con; $g = $script:BackG; $s = $script:Scale
    $height = 150; $lineH = 5.6; $rows = [int](($height - 14) / $lineH)
    Write-HudBar 'EC012456' 0 0 320 $height
    Write-HudBar 'FF40E0FF' 0 $height 320 0.7
    $font = $script:Fonts.Term
    $last = $con.Lines.Count - 1 - $con.Scroll
    $first = [Math]::Max(0, $last - $rows + 1)
    $y = 3.0
    for ($i = $first; $i -le $last; $i++) {
        $line = $con.Lines[$i]
        $g.DrawString($line[0], $font, (Get-Brush $line[1]), [single](3 * $s), [single]($y * $s))
        $y += $lineH
    }
    $cursor = if ([int]($script:Clock.Elapsed.TotalSeconds * 2.5) % 2 -eq 0) { '_' } else { '' }
    $g.DrawString("$(Get-ConsolePrompt)$($con.Input)$cursor", $font, (Get-Brush 'FFFFFF'), [single](3 * $s), [single](($height - 8) * $s))
    $note = "privilege $([int]$script:P.Privilege)$(if ($con.Scroll) { "   (scrolled back $($con.Scroll) lines - PgDn)" })"
    $g.DrawString($note, $font, (Get-Brush '8FB0FF'), [single](250 * $s), [single](3 * $s))
}
