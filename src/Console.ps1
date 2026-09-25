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
#
# Like every PowerShell it has a profile: saves/profile.ps1 is run - inside the sandbox, like everything
# else - whenever the console starts. Functions, aliases and the four hotkeys (Set-Hotkey) live there;
# a hotkey runs its command line in the middle of the game without opening the console.

$script:Con = $null
$script:Hotkeys = @{}                          # slot 1-4 -> command line

$script:ConsoleHelp = @'
LOOK          Get-Enemy [-Kind guard]   Get-Door   Get-Loot [-Name clip*]   Get-Trap   Get-Player   Get-Secret (20)
READ          At a terminal or server rack:  Get-ChildItem (ls, dir)   Get-Content <file> (cat, type)
              What the files give away:      Unlock-Door -Code <number>      Use-Token <word>
ACT           Stop-Enemy (10 + half his health)     Suspend-Enemy (12, eight seconds)
              Open-Door (8, locked ones 25)   Close-Door (5)   Lock-Door (15, jams it for twenty seconds)
              ... or the way you would have guessed:  Get-Door | Set-Door -Open $true     Get-Process | Stop-Process
              Disable-Trap (10)     Set-Turret -Owner Me (25: a sentry gun changes sides)     Get-Enemy -Kind camera | Stop-Enemy
              Get-ExecutionPolicy     Set-ExecutionPolicy Restricted (15 for every step down)
              Every one of them takes -Id or objects from the pipeline, and -WhatIf tells you the price first.
MODULES       Get-Module shows what you have installed between the floors.   Update-Module polf3d: is there a newer game?
REMOTE        Invoke-Command sets off the mines you have put down (so does the mine key)
JOBS          Start-Job (30): a drone collects what lies around in the rooms open to you - six things or thirty seconds
              Get-Job shows how it is doing, Receive-Job drops its load at your feet, Stop-Job calls it back
PROFILE       function kn { Get-Enemy | select -First 1 | Stop-Enemy }      Set-Alias ge Get-Enemy
              Set-Hotkey 1 'kn'   runs it from the game with a key (Get-Hotkey shows the four keys)
              Save-Profile keeps what you defined:   Get-Content $PROFILE   Clear-Content $PROFILE
PIPE          Where-Object (?)  Sort-Object (sort)  Select-Object (select)  ForEach-Object (%)  Measure-Object
              Group-Object  Format-Table (ft)  Format-List (fl)  Get-Member (gm)  Get-Random
TRY           Get-Enemy | Sort-Object Distance | Select-Object -First 1 | Stop-Enemy -WhatIf
              Get-Door | Where-Object Lock -ne '-' | Open-Door
              Get-Enemy | ? State -eq 'attacking' | Suspend-Enemy
KEYS          Tab completes commands, parameters, kinds, properties and file names (again: the next one).
              Up/Down: history.   PgUp/PgDn: scroll.   exit or Esc leaves.   cls clears the screen.
              Numbers in brackets: the price in privilege.
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
        'Set-Alias' = [Microsoft.PowerShell.Commands.SetAliasCommand]
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
        'Set-Hotkey' = 'param([Parameter(Position = 0)][int]$Key, [Parameter(Position = 1)][string]$Command) [pscustomobject]@{ PolfAction = "Set-Hotkey"; Id = $Key; WhatIf = $false; Value = $Command }'
        'Get-Hotkey' = '$PolfHotkeys'
        'Get-ExecutionPolicy' = '$PolfPolicy'
        'Invoke-Command' = '[pscustomobject]@{ PolfAction = "Invoke-Mine"; Id = 0; WhatIf = $false }'
        'Get-Module' = 'if ($PolfModules) { $PolfModules } else { "No modules installed. The lift offers three after every floor." }'
        'Install-Module' = '"Install-Module: the repository can only be reached from the lift - between two floors."'
        'Get-Job' = 'if ($PolfJobs) { $PolfJobs } else { "No jobs. Start-Job sends out a drone." }'
        'Start-Job' = 'param([string]$Name, [Parameter(Position = 0)]$ScriptBlock) [pscustomobject]@{ PolfAction = "Start-Job"; Id = 0; WhatIf = $false }'
        'Receive-Job' = 'param([Parameter(Position = 0)]$Id, [string]$Name, [switch]$Keep, [switch]$Wait) [pscustomobject]@{ PolfAction = "Receive-Job"; Id = 0; WhatIf = $false }'
        'Stop-Job' = 'param([Parameter(Position = 0)]$Id, [string]$Name) [pscustomobject]@{ PolfAction = "Stop-Job"; Id = 0; WhatIf = $false }'
        'Wait-Job' = '"Wait-Job: there is no time to wait down here. Get-Job tells you how far it is."'
        'Set-ExecutionPolicy' = 'param([Parameter(Position = 0)][string]$ExecutionPolicy, [string]$Scope, [switch]$Force) [pscustomobject]@{ PolfAction = "Set-Policy"; Id = 0; WhatIf = $false; Value = $ExecutionPolicy }'
        'Save-Profile' = '[pscustomobject]@{ PolfAction = "Save-Profile"; Id = 0; WhatIf = $false }'
        'Update-Module' = 'param([Parameter(Position = 0)][string]$Name) [pscustomobject]@{ PolfAction = "Update-Game"; Id = 0; WhatIf = $false; Value = $Name }'
        'Clear-Content' = 'param([Parameter(Position = 0)][string]$Path) if ($Path -eq $PROFILE) { [pscustomobject]@{ PolfAction = "Clear-Profile"; Id = 0; WhatIf = $false } } else { throw "Clear-Content: the only thing that can be cleared from here is `$PROFILE." }'
        'Get-Content' = 'param([Parameter(Position = 0)][string]$Path = "*") if ($Path -eq $PROFILE) { if ($PolfProfile) { return $PolfProfile } else { return "`$PROFILE is empty. Define a function, then Save-Profile." } }; $hit = $PolfFiles | Where-Object Name -like $Path | Select-Object -First 1; if ($hit) { $PolfFileText[$hit.Name] } elseif ($PolfFiles) { throw "Cannot find path ''$Path'' because it does not exist." } else { throw "No file system here. Log on at a terminal first." }'
        'Unlock-Door' = 'param([Parameter(Position = 0)][string]$Code) [pscustomobject]@{ PolfAction = "Use-Code"; Id = 0; WhatIf = $false; Value = $Code }'
        'Use-Token' = 'param([Parameter(Position = 0)][string]$Token) [pscustomobject]@{ PolfAction = "Use-Code"; Id = 0; WhatIf = $false; Value = $Token }'
        'Get-Process' = '$PolfEnemies | Select-Object Type, Id, @{ n = "ProcessName"; e = { $_.Kind } }, @{ n = "WS(HP)"; e = { $_.Health } }, State'
        # what people type by instinct: Get-Door | Set-Door -Open $true. It hands out the same requests as Open-Door & co.
        'Set-Door' = @'
[CmdletBinding()] param([Parameter(ValueFromPipeline)]$InputObject, [int[]]$Id, [Nullable[bool]]$Open, [Nullable[bool]]$Locked, [switch]$WhatIf)
process {
    if ($null -ne $InputObject -and $InputObject.Type -ne 'Door') { throw "Set-Door: that is no door (it is a $($InputObject.Type)). Try Get-Door | Set-Door -Open `$true" }
    if ($null -eq $Open -and $null -eq $Locked) { throw 'Set-Door: say what you want - -Open $true, -Open $false or -Locked $true' }
    $verb = if ($Locked) { 'Lock-Door' } elseif ($Open -eq $false) { 'Close-Door' } else { 'Open-Door' }
    foreach ($i in @($Id) + @($InputObject.Id)) { if ($null -ne $i) { [pscustomobject]@{ PolfAction = $verb; Id = [int]$i; WhatIf = [bool]$WhatIf } } }
}
'@
    }
    # the acting cmdlets all look the same: ids in, requests out
    foreach ($act in @('Stop-Enemy', 'Enemy'), @('Suspend-Enemy', 'Enemy'), @('Open-Door', 'Door'), @('Close-Door', 'Door'), @('Lock-Door', 'Door'), @('Disable-Trap', 'Trap'), @('Set-Turret', 'Enemy')) {
        $functions[$act[0]] = @"
[CmdletBinding()] param([Parameter(ValueFromPipeline)]`$InputObject, [int[]]`$Id, [switch]`$WhatIf)
process {
    if (`$null -ne `$InputObject -and `$InputObject.Type -ne '$($act[1])') { throw "$($act[0]): that is no $($act[1].ToLower()) (it is a `$(`$InputObject.Type)). Try Get-$($act[1]) | $($act[0])" }
    foreach (`$i in @(`$Id) + @(`$InputObject.Id)) { if (`$null -ne `$i) { [pscustomobject]@{ PolfAction = '$($act[0])'; Id = [int]`$i; WhatIf = [bool]`$WhatIf } } }
}
"@
    }
    $functions['Set-Turret'] = $functions['Set-Turret'].Replace('[switch]$WhatIf)', '[switch]$WhatIf, [string]$Owner = "Me")')
    foreach ($f in $functions.GetEnumerator()) { $iss.Commands.Add([System.Management.Automation.Runspaces.SessionStateFunctionEntry]::new($f.Key, $f.Value)) }
    foreach ($a in @('?', 'Where-Object'), @('where', 'Where-Object'), @('%', 'ForEach-Object'), @('foreach', 'ForEach-Object'), @('select', 'Select-Object'), @('sort', 'Sort-Object'),
        @('measure', 'Measure-Object'), @('group', 'Group-Object'), @('ft', 'Format-Table'), @('fl', 'Format-List'), @('gm', 'Get-Member'), @('echo', 'Write-Output'),
        @('help', 'Get-Help'), @('man', 'Get-Help'), @('gcm', 'Get-Command'), @('kill', 'Stop-Enemy'), @('spps', 'Stop-Enemy'), @('ps', 'Get-Process'), @('gps', 'Get-Process'),
        @('ls', 'Get-ChildItem'), @('dir', 'Get-ChildItem'), @('gci', 'Get-ChildItem'), @('cat', 'Get-Content'), @('type', 'Get-Content'), @('gc', 'Get-Content'), @('more', 'Get-Content'), @('sal', 'Set-Alias'), @('icm', 'Invoke-Command'), @('Stop-Process', 'Stop-Enemy'), @('Remove-Enemy', 'Stop-Enemy'), @('Suspend-Process', 'Suspend-Enemy'), @('sajb', 'Start-Job'), @('gjb', 'Get-Job'), @('rcjb', 'Receive-Job'), @('spjb', 'Stop-Job'), @('Remove-Job', 'Stop-Job'), @('clc', 'Clear-Content'), @('rm', 'Remove-Item'), @('del', 'Remove-Item'), @('iwr', 'Invoke-WebRequest'), @('curl', 'Invoke-WebRequest')) {
        $iss.Commands.Add([System.Management.Automation.Runspaces.SessionStateAliasEntry]::new($a[0], $a[1]))
    }
    $rs = [runspacefactory]::CreateRunspace($iss); $rs.Open()
    $rs.SessionStateProxy.SetVariable('PolfHelp', $script:ConsoleHelp)
    $rs.SessionStateProxy.SetVariable('PolfCommands', @(@($functions.Keys) + @($cmdlets.Keys) | Sort-Object))
    $script:Con = @{
        Runspace = $rs; Lines = [System.Collections.Generic.List[object]]::new(); Input = ''; History = [System.Collections.Generic.List[string]]::new(); HistoryAt = 0
        Scroll = 0; Opened = 0.0; Session = [ordered]@{}; Tab = $null
        Commands = @(@($functions.Keys) + @($cmdlets.Keys) | Sort-Object); Aliases = @{}
    }
    foreach ($entry in $iss.Commands) { if ($entry -is [System.Management.Automation.Runspaces.SessionStateAliasEntry]) { $script:Con.Aliases[$entry.Name] = $entry.Definition } }
    $script:CharQueue = [System.Collections.Generic.Queue[char]]::new()
    $rs.SessionStateProxy.SetVariable('PROFILE', 'saves\profile.ps1')
    Import-ConsoleProfile
}

# ---- the profile -------------------------------------------------------------------------------
function Get-ProfilePath { Join-Path $script:SaveDir 'profile.ps1' }

# Runs saves/profile.ps1 in the sandbox. It may have been written by hand, so it gets no more trust than a typed line.
function Import-ConsoleProfile {
    $script:Hotkeys = @{}
    $path = Get-ProfilePath
    if (-not (Test-Path -LiteralPath $path)) { return }
    try { $text = [System.IO.File]::ReadAllText($path) } catch { return }
    if ($text.Length -gt 16384) { Write-ConsoleLine 'The profile is larger than 16 KB and has not been loaded.' 'F14C4C'; return }
    $result = Invoke-SandboxScript $text
    foreach ($o in $result.Output) { if ($null -ne $o -and $o.PSObject.Properties['PolfAction'] -and $o.PolfAction -eq 'Set-Hotkey') { $null = Set-ConsoleHotkey ([int]$o.Id) ([string]$o.Value) } }
    foreach ($e in $result.Errors) { Write-ConsoleLine "profile: $e" 'F14C4C' }
}

function Set-ConsoleHotkey([int]$Slot, [string]$Command) {
    if ($Slot -lt 1 -or $Slot -gt 4) { return 'Set-Hotkey: there are four hotkeys, 1 to 4.' }
    $Command = $Command.Trim()
    if ($Command.Length -gt 200) { return 'Set-Hotkey: two hundred characters is all a hotkey holds.' }
    if ($Command) { $script:Hotkeys[$Slot] = $Command } else { $script:Hotkeys.Remove($Slot) }
    $null
}

# The line of a profile that defines the same thing as the session key "function:name" | "alias:name" | "hotkey:n".
function Get-ProfilePattern([string]$Key) {
    $kind, $name = $Key.Split(':', 2); $name = [regex]::Escape($name)
    switch ($kind) {
        'function' { "^\s*(function|filter)\s+$name(\s|\{|$)" }
        'alias'    { "^\s*(Set-Alias|sal)\s+(-Name\s+)?$name\s" }
        'hotkey'   { "^\s*Set-Hotkey\s+(-Key\s+)?$name\s" }
    }
}

# Save-Profile: what has been defined in this session replaces the lines of the same name and is added at the end.
function Export-ConsoleProfile {
    $con = $script:Con; $path = Get-ProfilePath
    $lines = [System.Collections.Generic.List[string]]::new()
    if (Test-Path -LiteralPath $path) { foreach ($l in [System.IO.File]::ReadAllLines($path)) { $lines.Add($l) } }
    else {
        $lines.Add('# POLF 3D console profile. It is run inside the sandboxed console whenever that starts - nowhere else.')
        $lines.Add("# Functions, Set-Alias and Set-Hotkey <1-4> '<command line>'. Edit it by hand if you like.")
    }
    foreach ($key in @($con.Session.Keys)) {
        $pattern = Get-ProfilePattern $key
        for ($i = $lines.Count - 1; $i -ge 0; $i--) { if ($lines[$i] -match $pattern) { $lines.RemoveAt($i) } }
        $lines.Add($con.Session[$key])
    }
    $null = New-Item -ItemType Directory -Path $script:SaveDir -Force
    [System.IO.File]::WriteAllLines($path, $lines)
    $con.Session.Count
}

# A hotkey pressed in the game: the command line runs as if it had been typed, the last line of the answer is the message.
function Invoke-ConsoleHotkey([int]$Slot) {
    if ($script:NetLive) { Show-Message 'No console hotkeys in a shared world'; return }
    if ($script:Recording -or $script:Playback) { Show-Message 'No console hotkeys while a demo is recorded or played'; return }
    if (-not $script:Con) { Initialize-Console }
    $command = $script:Hotkeys[$Slot]
    if (-not $command) { Show-Message "Hotkey $Slot ($(Get-KeyName $script:Bind["Macro$Slot"])) is empty. In the console: Set-Hotkey $Slot 'Get-Enemy | select -First 1 | Suspend-Enemy'"; return }
    Stop-WhatIf
    $con = $script:Con; $con.AtTerminal = $false
    $before = $con.Lines.Count
    Invoke-ConsoleLine $command
    $answer = ''
    for ($i = $con.Lines.Count - 1; $i -gt $before; $i--) { if ("$($con.Lines[$i][0])".Trim()) { $answer = "$($con.Lines[$i][0])".Trim(); break } }
    if ($answer.Length -gt 96) { $answer = $answer.Substring(0, 93) + '...' }
    Show-Message $(if ($answer) { $answer } else { "PS> $command" })
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
        $state = if ($a.Hacked) { 'yours' } elseif ($a.Stun -gt 0) { 'suspended' } elseif ($a.AttackMode) { 'attacking' } elseif ($a.React -gt 0) { 'alerted' } elseif ($a.State -like '*.path*') { 'patrolling' } else { 'unaware' }
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
    $player = [pscustomobject]@{ Type = 'Player'; Health = $p.Health; Armour = [int]$p.Armor; Ammo = $p.Ammo; Keycards = [int]$p.Keycards; Signed = (@($p.Signed) -join ', '); Privilege = [int]$p.Privilege; Floor = $script:LevelName
        Policy = (Get-Policy).Name; Kills = "$($st.Kills)/$($st.KillTotal)"; Secrets = "$($st.Secrets)/$($st.SecretTotal)"; Treasure = "$($st.Treasures)/$($st.TreasureTotal)" }
    # the files of this floor - but only at one of the building's own terminals
    $files = @(); $texts = @{}
    $floor = Get-StoryFloor
    if ($script:Con.AtTerminal -and $floor) {
        $files = foreach ($name in $floor.Files.Keys) { $texts[$name] = "$($floor.Files[$name])".TrimEnd(); [pscustomobject]@{ Type = 'File'; Mode = '-a---'; Length = $texts[$name].Length; Name = $name } }
    }
    $proxy.SetVariable('PolfFiles', @($files)); $proxy.SetVariable('PolfFileText', $texts)
    $proxy.SetVariable('PolfPolicy', (Get-Policy).Name)
    $proxy.SetVariable('PolfModules', @(foreach ($m in @($p.Modules)) { if ($m) { [pscustomobject]@{ Type = 'Module'; Name = $m; Description = $script:ModulePerks[$m] } } }))
    $drone = Get-Drone
    $proxy.SetVariable('PolfJobs', @(if ($drone) { [pscustomobject]@{ Type = 'Job'; Id = 1; Name = 'Drone'; State = $(if ($drone.Hacked) { 'Completed' } else { 'Running' }); HasMoreData = [bool]@($script:Stats.Cargo).Count
        Carrying = (@($script:Stats.Cargo) -join ', '); Distance = (Get-Range $drone.X $drone.Y); Bearing = (Get-Bearing $drone.X $drone.Y) } }))
    $profilePath = Get-ProfilePath
    $proxy.SetVariable('PolfProfile', $(if (Test-Path -LiteralPath $profilePath) { try { [System.IO.File]::ReadAllText($profilePath).TrimEnd() } catch { '' } } else { '' }))
    $proxy.SetVariable('PolfHotkeys', @(foreach ($slot in 1..4) { [pscustomobject]@{ Type = 'Hotkey'; Id = $slot; Key = (Get-KeyName $script:Bind["Macro$slot"]); Command = "$($script:Hotkeys[$slot])" } }))
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
        'Stop-Enemy'    { if ($Target.Kind -in 'boss', 'uber', 'pilot', 'bsod') { "Access is denied: the $($Target.Kind) runs as SYSTEM" } else { 10 + [int][Math]::Ceiling($Target.HP / 2.0) } }
        'Suspend-Enemy' { if ($Target.Kind -in 'boss', 'uber', 'pilot', 'bsod') { 30 } else { 12 } }
        'Set-Turret'    { if ($Target.Kind -ne 'turret') { "that is a $($Target.Kind), not a sentry gun" } elseif ($Target.Hacked) { 'it answers to you already' } else { 25 } }
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
    if ($name -eq 'Start-Job') {
        if (Get-Drone) { Write-ConsoleLine 'Start-Job: one drone is all you have. Receive-Job takes its load and sends it home.' 'F14C4C'; return $true }
        $price = if (Test-Perk 'ThreadJob') { 15 } else { 30 }
        if ($p.Privilege -lt $price -and -not $script:InfiniteAmmo) { Write-ConsoleLine "Start-Job: Access is denied - a drone costs $price privilege, you have $([int]$p.Privilege)." 'F14C4C'; return $false }
        if (-not $script:InfiniteAmmo) { Add-Privilege (- $price) }
        $null = Start-Drone; $script:Run.Console++
        Write-ConsoleLine "Id 1  Drone  Running  -  it collects what lies around in the rooms open to you.  (-$price privilege, $([int]$p.Privilege) left)" '60FF80'
        return $true
    }
    if ($name -eq 'Stop-Job') {
        $drone = Get-Drone
        if (-not $drone) { Write-ConsoleLine 'Stop-Job: there is no job.' 'F14C4C' } else { $drone.Hacked = $true; Write-ConsoleLine 'The drone is on its way back. Receive-Job takes what it has.' '60FF80' }
        return $true
    }
    if ($name -eq 'Receive-Job') {
        if (-not (Get-Drone) -and -not @($script:Stats.Cargo).Count) { Write-ConsoleLine 'Receive-Job: there is no job.' 'F14C4C'; return $true }
        $cargo = @(Receive-Drone)
        Write-ConsoleLine $(if ($cargo.Count) { "Received: $($cargo -join ', ') - at your feet." } else { 'The drone has not found anything yet.' }) '60FF80'
        return $true
    }
    if ($name -eq 'Invoke-Mine') {
        $live = @($script:Actors | Where-Object { $_.Kind -eq 'mine' -and $_.Shootable })
        if ($live.Count) { foreach ($m in $live) { Stop-Actor $m }; Write-ConsoleLine "Invoke-Command: $($live.Count) mine(s) told to go off. Leave the console and mind the blast." '60FF80' } else { Write-ConsoleLine 'Invoke-Command: there is no mine out there. Put one down first.' 'F14C4C' }
        return $true
    }
    if ($name -eq 'Set-Policy') {
        $answer = Set-Policy ([string]$Action.Value)
        Write-ConsoleLine $answer.Text $(if ($answer.Ok) { '60FF80' } else { 'F14C4C' })
        return $answer.Ok
    }
    if ($name -eq 'Set-Hotkey') {
        $problem = Set-ConsoleHotkey $id ([string]$Action.Value)
        if ($problem) { Write-ConsoleLine $problem 'F14C4C'; return $true }
        $script:Con.Session["hotkey:$id"] = "Set-Hotkey $id '$("$($Action.Value)".Trim().Replace("'", "''"))'"
        Write-ConsoleLine "Hotkey $id - the $(Get-KeyName $script:Bind["Macro$id"]) key - $(if ("$($Action.Value)".Trim()) { "runs: $("$($Action.Value)".Trim())" } else { 'is empty again' }).  Save-Profile keeps it." '60FF80'
        return $true
    }
    if ($name -eq 'Update-Game') {
        # the game itself: is there a newer one? Installing is the title screen's job - a floor in progress would be lost
        $answer = if ($script:NewRelease) { "POLF 3D $($script:NewRelease.Version) is out - the title screen shows what is new and installs it (U)." }
            elseif ($script:UpdateState -eq 'current') { "POLF 3D $script:PolfVersion is the newest there is." }
            elseif ($script:UpdateCheckOff -or -not $script:Settings.UpdateCheck) { 'The game has not looked: update checks are off (options menu, or -NoUpdateCheck).' }
            else { 'The game has not heard back from GitHub yet. Ask again in a moment.' }
        Write-ConsoleLine $answer '60FF80'
        return $true
    }
    if ($name -eq 'Save-Profile') {
        try { $count = Export-ConsoleProfile; Write-ConsoleLine "Saved $count definition(s) of this session to `$PROFILE (saves/profile.ps1)." '60FF80' } catch { Write-ConsoleLine "Save-Profile: $($_.Exception.Message)" 'F14C4C' }
        return $true
    }
    if ($name -eq 'Clear-Profile') {
        Remove-Item -LiteralPath (Get-ProfilePath) -ErrorAction SilentlyContinue
        $script:Hotkeys = @{}; $script:Con.Session.Clear()
        Write-ConsoleLine '$PROFILE is empty and so are the hotkeys. What this session has defined lives until the game ends.' '60FF80'
        return $true
    }
    $target = switch -Wildcard ($name) {
        { $_ -like '*-Enemy' -or $_ -eq 'Set-Turret' } { $script:Actors | Where-Object { $_.NetId -eq $id -and $_.Shootable -and -not $_.Def.Inert } | Select-Object -First 1 }
        '*-Door'  { if ($id -ge 0 -and $id -lt $script:Doors.Count) { $script:Doors[$id] } }
        '*-Trap'  { if ($id -ge 0 -and $id -lt $script:Traps.Count) { $script:Traps[$id] } }
        default   { $true }
    }
    if (-not $target) { Write-ConsoleLine "${name}: cannot find anything with Id $id." 'F14C4C'; return $true }
    $label = if ($name -like '*-Enemy' -or $name -eq 'Set-Turret') { "$($target.Kind) #$id" } elseif ($name -like '*-Door') { "door #$id" } elseif ($name -like '*-Trap') { "$($target.Kind) #$id" } else { 'this floor' }
    $cost = Get-ConsoleActionCost $name $target
    if ($cost -is [string]) { Write-ConsoleLine "${name}: $cost." 'F14C4C'; return $true }
    if ($Action.WhatIf) { Write-ConsoleLine "What if: Performing the operation `"$name`" on target `"$label`". It would cost $cost privilege." ; return $true }
    if ($p.Privilege -lt $cost -and -not $script:InfiniteAmmo) { Write-ConsoleLine "${name}: Access is denied - $label costs $cost privilege, you have $([int]$p.Privilege)." 'F14C4C'; return $false }
    switch ($name) {
        'Stop-Enemy'    { $script:KillCause = 'console'; Stop-Actor $target; $script:KillCause = $null; $done = 'terminated' }
        'Suspend-Enemy' { $target.Stun = 560.0; $done = 'suspended for eight seconds' }
        'Set-Turret'    { $target.Hacked = $true; $target.AttackMode = $false; $target.React = 0; $target.AlertTics = 0; $target.Cool = 0; Set-ActorState $target 'turret.chase1'; $done = 'it answers to you now' }
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
    $script:Run.Console++
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
    if (-not $result.Errors.Count) {
        # a definition: remember the line, Save-Profile writes it to the profile
        $key = if ($Text -match '^(?:function|filter)\s+([A-Za-z_][\w-]*)') { "function:$($Matches[1])" } elseif ($Text -match '^(?:Set-Alias|sal)\s+(?:-Name\s+)?([^\s-]\S*)\s') { "alias:$($Matches[1])" }
        if ($key) { $con.Session[$key] = $Text; Write-ConsoleLine 'Defined for this session. Save-Profile keeps it for good.' 'A0A8B8' }
    }
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

# ---- Tab completion ------------------------------------------------------------------------------
# PowerShell's own completion engine finds nothing in a session state as empty as the sandbox's, so the console has
# one of its own - which, in return, knows the game: the kinds of enemies on this floor, the files of this terminal,
# the properties of whatever comes down the pipeline.
$script:ConsoleParameters = @{
    'Get-Enemy' = '-Kind'; 'Get-Loot' = '-Name'; 'Get-Content' = '-Path'; 'Unlock-Door' = '-Code'; 'Use-Token' = '-Token'
    'Stop-Enemy' = '-Id', '-WhatIf'; 'Suspend-Enemy' = '-Id', '-WhatIf'; 'Open-Door' = '-Id', '-WhatIf'; 'Close-Door' = '-Id', '-WhatIf'
    'Lock-Door' = '-Id', '-WhatIf'; 'Disable-Trap' = '-Id', '-WhatIf'; 'Set-Turret' = '-Id', '-Owner', '-WhatIf'
    'Set-Door' = '-Id', '-Open', '-Locked', '-WhatIf'; 'Set-Hotkey' = '-Key', '-Command'; 'Set-ExecutionPolicy' = '-ExecutionPolicy'; 'Update-Module' = '-Name'
    'Where-Object' = '-Property', '-EQ', '-NE', '-GT', '-GE', '-LT', '-LE', '-Like', '-NotLike', '-Match', '-In', '-FilterScript'
    'Sort-Object' = '-Property', '-Descending', '-Unique'; 'Select-Object' = '-First', '-Last', '-Skip', '-Property', '-ExpandProperty', '-Unique'
    'Measure-Object' = '-Property', '-Sum', '-Average', '-Maximum', '-Minimum'; 'Group-Object' = '-Property', '-NoElement'
    'Format-Table' = '-Property', '-AutoSize'; 'Format-List' = '-Property'; 'Get-Random' = '-Minimum', '-Maximum', '-Count'
    'ForEach-Object' = '-Process', '-MemberName'; 'Set-Alias' = '-Name', '-Value'
}
$script:ConsoleProperties = @{
    'Get-Enemy' = 'Id', 'Kind', 'Health', 'State', 'Distance', 'Bearing'; 'Get-Process' = 'Id', 'ProcessName', 'State'
    'Get-Door' = 'Id', 'Lock', 'State', 'Distance', 'Bearing'; 'Get-Loot' = 'Id', 'Name', 'Distance', 'Bearing'
    'Get-Trap' = 'Id', 'Kind', 'Disabled', 'Distance', 'Bearing'; 'Get-Job' = 'Id', 'Name', 'State', 'Carrying'
    'Get-ChildItem' = 'Name', 'Length', 'Mode'; 'Get-Hotkey' = 'Id', 'Key', 'Command'; 'Get-Module' = 'Name', 'Description'
}

# The full name behind an alias of the sandbox (or the word itself).
function Resolve-ConsoleCommand([string]$Word) {
    if ($script:Con.Aliases.ContainsKey($Word)) { $script:Con.Aliases[$Word] } else { @($script:Con.Commands | Where-Object { $_ -eq $Word })[0] ?? $Word }
}

# What could stand where the input ends. Returns @{ Start = where the word begins; Matches = candidates }.
function Get-ConsoleCompletion([string]$Text) {
    $start = $Text.Length
    while ($start -gt 0 -and $Text[$start - 1] -notin ' ', '|', ';', '(', '{', ',') { $start-- }
    $word = $Text.Substring($start)
    $segment = ($Text.Substring(0, $start) -split '[|;({]')[-1].Trim()              # this command of the pipeline, without the word
    $upstream = ($Text.Substring(0, $start) -split '[;({]')[-1] -split '\|' | ForEach-Object { ($_.Trim() -split '\s+')[0] } | Where-Object { $_ }
    $words = @($segment -split '\s+' | Where-Object { $_ })
    $command = if ($words.Count) { Resolve-ConsoleCommand $words[0] } else { '' }
    $previous = if ($words.Count) { $words[-1] } else { '' }
    $pool = @()
    if (-not $words.Count) { $pool = @($script:Con.Commands) + @($script:Con.Aliases.Keys) | Sort-Object -Unique }          # a command is wanted
    elseif ($word.StartsWith('-')) { $pool = @($script:ConsoleParameters[$command]) }
    elseif ($previous -eq '-Kind' -or ($command -eq 'Get-Enemy' -and $words.Count -eq 1)) { Update-ConsoleData; $pool = @($script:Con.Runspace.SessionStateProxy.GetVariable('PolfEnemies') | ForEach-Object Kind | Sort-Object -Unique) }
    elseif ($previous -eq '-Owner') { $pool = @('Me') }
    elseif ($previous -in '-Open', '-Locked') { $pool = '$true', '$false' }
    elseif ($command -eq 'Set-ExecutionPolicy') { $pool = @($script:PolicyLevels | ForEach-Object Name) }
    elseif ($command -in 'Get-Content', 'Clear-Content') { Update-ConsoleData; $pool = @($script:Con.Runspace.SessionStateProxy.GetVariable('PolfFiles') | ForEach-Object Name) + '$PROFILE' }
    elseif ($command -eq 'Get-Loot') { Update-ConsoleData; $pool = @($script:Con.Runspace.SessionStateProxy.GetVariable('PolfLoot') | ForEach-Object Name | Sort-Object -Unique) }
    elseif ($command -in 'Where-Object', 'Sort-Object', 'Select-Object', 'Group-Object', 'Measure-Object', 'Format-Table', 'Format-List', 'ForEach-Object') {
        # a property of what comes down the pipe: look upstream for the Get- that started it
        foreach ($up in @($upstream)) { $full = Resolve-ConsoleCommand $up; if ($script:ConsoleProperties.ContainsKey($full)) { $pool = @($script:ConsoleProperties[$full]) } }
    }
    @{ Start = $start; Matches = @($pool | Where-Object { $_ -and "$_" -like "$word*" }) }
}

# Tab: the first candidate; Tab again: the next one. Several candidates are listed once.
function Complete-ConsoleInput {
    $con = $script:Con
    if (-not $con.Tab) {
        $found = Get-ConsoleCompletion $con.Input
        if (-not $found.Matches.Count) { Start-Sfx 'noway'; return }
        $con.Tab = @{ Base = $con.Input.Substring(0, $found.Start); Matches = $found.Matches; Index = -1 }
        if ($found.Matches.Count -gt 1) { Write-ConsoleLine ($found.Matches -join '   ') '7080A0' }
    }
    $tab = $con.Tab
    $tab.Index = ($tab.Index + 1) % $tab.Matches.Count
    $con.Input = $tab.Base + $tab.Matches[$tab.Index]
    if ($tab.Matches.Count -eq 1 -and -not $con.Input.EndsWith(' ')) { $con.Input += ' '; $con.Tab = $null }      # nothing to choose: go on typing
}

# $Keys: the key codes pressed this frame. Characters come from the form's KeyPress event.
function Update-Console([int[]]$Keys) {
    $con = $script:Con
    $justOpened = $script:Clock.Elapsed.TotalSeconds - $con.Opened -lt 0.15
    foreach ($k in $Keys) {
        switch ($k) {
            27 { Close-Console; return }                                                             # Esc
            9  { if (-not $justOpened) { Complete-ConsoleInput } }                                  # Tab: completion (it used to close the console)
            13 { $line = $con.Input; $con.Input = ''; $script:CharQueue.Clear(); Invoke-ConsoleLine $line; if ($script:Mode -ne 'console') { return } }
            8  { if ($con.Input.Length) { $con.Input = $con.Input.Substring(0, $con.Input.Length - 1) }; $con.Tab = $null }
            38 { if ($con.HistoryAt -gt 0) { $con.HistoryAt--; $con.Input = $con.History[$con.HistoryAt] } }
            40 { if ($con.HistoryAt -lt $con.History.Count - 1) { $con.HistoryAt++; $con.Input = $con.History[$con.HistoryAt] } else { $con.HistoryAt = $con.History.Count; $con.Input = '' } }
            33 { $con.Scroll = [Math]::Min([Math]::Max(0, $con.Lines.Count - 5), $con.Scroll + 10) }                                # PgUp
            34 { $con.Scroll = [Math]::Max(0, $con.Scroll - 10) }
        }
    }
    while ($script:CharQueue.Count) {
        $c = $script:CharQueue.Dequeue()
        if ($justOpened -or [int]$c -lt 32 -or [int]$c -eq 127) { continue }                          # the key that opened it, control characters
        if ($con.Input.Length -lt 110) { $con.Input += $c; $con.Tab = $null }
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
