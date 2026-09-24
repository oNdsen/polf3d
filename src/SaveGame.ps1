# POLF 3D - Copyright (c) 2026 oNdsen. Licensed under the MIT License, see LICENSE.

# SaveGame.ps1 - saved games (quick save, autosave, three slots; JSON), speedrun records, high scores.
#
# A save file holds only what differs from a freshly loaded map: the tile grid (push-walls,
# the switch), doors, items, actors, the player and the statistics. Loading rebuilds the level
# from its map file and then lays the saved state over it.

$script:ActorSaveProps = 'Kind', 'State', 'Tics', 'X', 'Y', 'TX', 'TY', 'Dir', 'PathDir', 'Dist', 'WaitDoor', 'Speed', 'HP', 'Area',
                         'Active', 'Shootable', 'AttackMode', 'FirstAttack', 'Ambush', 'Corpse', 'React', 'VX', 'VY', 'Hacked', 'Cool'

# Slots: 'quick' (F5/F9), 'auto' (written whenever the lift arrives on a new floor), '1'..'3' (pause menu).
function Get-SavePath([string]$Slot = 'quick') { Join-Path $script:SaveDir $(if ($Slot -eq 'quick') { 'quicksave.json' } else { "save-$Slot.json" }) }

function Test-SaveGame { @(Get-SaveList).Count -gt 0 }

# Every existing save, newest first: @{ Slot; Path; Saved; Text }
function Get-SaveList {
    $list = foreach ($slot in 'quick', 'auto', '1', '2', '3') {
        $path = Get-SavePath $slot
        if (-not (Test-Path -LiteralPath $path)) { continue }
        try {
            $s = (Get-Content -LiteralPath $path -Raw | ConvertFrom-Json -AsHashtable).Summary
            @{ Slot = $slot; Path = $path; Saved = [datetime]$s.Saved
                Text = '{0,-6} {1,-26} health {2,3}   score {3,6}   {4:yyyy-MM-dd HH:mm}' -f $(if ($slot -match '^\d$') { "slot $slot" } else { $slot }), $s.Floor, $s.Health, $s.Score, [datetime]$s.Saved }
        }
        catch { }                                                  # unreadable or from before the summary existed: skip
    }
    @($list | Sort-Object { $_.Saved } -Descending)
}

function Save-Game([string]$Slot = 'quick') {
    # only the campaign is saved: a game saved in the arena, the dungeon, the onboarding or a network game could never be loaded
    if ($script:Net -or $script:DungeonSeed -or $script:HordeSeed -or $script:TutorialMode) { if ($Slot -ne 'auto') { Show-Message 'There is no saving here' }; return }
    Stop-WhatIf                                                   # its ghosts are no part of the world
    $seen = for ($i = 0; $i -lt $script:Vis.Length; $i++) { if ($script:Vis[$i] -gt 0) { $i } }
    $floor = if ($script:BonusMap) { "Bonus: $($script:LevelName)" } else { "Floor $($script:LevelIndex + 1): $($script:LevelName)" }
    $state = [ordered]@{
        Summary    = [ordered]@{ Saved = (Get-Date).ToString('s'); Floor = $floor; Health = $script:P.Health; Score = $script:P.Score }
        Version    = 1
        Saved      = (Get-Date).ToString('s')
        Map        = Split-Path $script:MapFile -Leaf
        Difficulty = $script:Difficulty
        LevelStartScore = $script:LevelStartScore
        Player     = $script:P
        Stats      = $script:Stats
        PushWall   = $script:PW
        Tiles      = $script:Tiles
        PushTex    = $script:PushTex
        Seen       = @($seen)
        Traps      = @(foreach ($t in $script:Traps) { $t.Phase })
        Doors      = @(foreach ($d in $script:Doors) { @{ Action = $d.Action; Open = $d.Open; Timer = $d.Timer; Unlocked = $d.Unlocked } })
        Items      = @(foreach ($s in $script:Items) { if (-not $s.Removed) { @{ Item = $s.Item; X = $s.X; Y = $s.Y } } })
        Actors     = @(foreach ($a in $script:Actors) { $h = @{}; foreach ($n in $script:ActorSaveProps) { $h[$n] = $a.$n }; $h })
    }
    try {
        $null = New-Item -ItemType Directory -Path $script:SaveDir -Force
        $state | ConvertTo-Json -Depth 6 -Compress | Set-Content -LiteralPath (Get-SavePath $Slot) -Encoding utf8
        if ($Slot -ne 'auto') { Show-Message $(if ($Slot -eq 'quick') { 'Game saved' } else { "Game saved in slot $Slot" }) }
    }
    catch { Show-Message "Saving failed: $($_.Exception.Message)" }
}

function Assert-SaveState([hashtable]$State, [string]$MapPath) {
    if (-not $State -or [int]$State.Version -ne 1) { throw "unsupported or missing save version '$($State.Version)'" }
    $difficulty = [int]$State.Difficulty
    if ($difficulty -lt 0 -or $difficulty -ge $script:Difficulties.Count) { throw "invalid difficulty '$difficulty'" }
    foreach ($name in 'Player', 'Stats', 'PushWall') {
        if ($State[$name] -isnot [System.Collections.IDictionary]) { throw "save section '$name' is missing or invalid" }
    }

    $map = Read-MapFile $MapPath
    $cells = $map.W * $map.H
    if (@($State.Tiles).Count -ne $cells -or @($State.PushTex).Count -ne $cells) { throw "tile data does not match the saved map ($($map.W)x$($map.H))" }
    foreach ($tile in @($State.Tiles) + @($State.PushTex)) { $null = [int]$tile }
    foreach ($seen in @($State.Seen)) {
        $index = [int]$seen
        if ($index -lt 0 -or $index -ge $cells) { throw "seen tile index '$index' is outside the map" }
    }

    $doorCount = 0
    foreach ($row in $map.Rows) {
        for ($x = 0; $x -lt $map.W; $x++) {
            $code = $row.Substring($x * 2, 2)
            if ($code[0] -ceq 'D' -and ($script:DoorCodes.ContainsKey($code[1]) -or [char]::IsDigit($code[1]))) { $doorCount++ }
        }
    }
    if (@($State.Doors).Count -ne $doorCount) { throw "door data does not match the saved map (expected $doorCount)" }
    foreach ($door in @($State.Doors)) {
        if ($door -isnot [System.Collections.IDictionary] -or $door.Action -notin 'closed', 'opening', 'open', 'closing') { throw 'invalid door data' }
        $open = [double]$door.Open; $timer = [double]$door.Timer
        if ([double]::IsNaN($open) -or [double]::IsInfinity($open) -or $open -lt 0 -or $open -gt 1 -or
            [double]::IsNaN($timer) -or [double]::IsInfinity($timer) -or $timer -lt 0) { throw 'invalid door position or timer' }
    }

    foreach ($phase in @($State.Traps)) {
        $value = [double]$phase
        if ([double]::IsNaN($value) -or [double]::IsInfinity($value)) { throw 'invalid trap phase' }
    }

    foreach ($item in @($State.Items)) {
        if ($item -isnot [System.Collections.IDictionary]) { throw 'invalid item data' }
        $x = [int]$item.X; $y = [int]$item.Y
        if ($x -lt 0 -or $x -ge $map.W -or $y -lt 0 -or $y -ge $map.H -or -not $item.Item) { throw "invalid item '$($item.Item)' at $x,$y" }
    }

    foreach ($actor in @($State.Actors)) {
        if ($actor -isnot [System.Collections.IDictionary]) { throw 'invalid actor data' }
        foreach ($name in $script:ActorSaveProps) { if (-not $actor.Contains($name)) { throw "actor is missing '$name'" } }
        if (-not $script:EnemyDefs.ContainsKey([string]$actor.Kind) -and -not $script:MiscDefs.ContainsKey([string]$actor.Kind)) { throw "unknown actor kind '$($actor.Kind)'" }
        if (-not $script:States.ContainsKey([string]$actor.State)) { throw "unknown actor state '$($actor.State)'" }
        $probe = [Actor]::new()
        foreach ($name in $script:ActorSaveProps) { $probe.$name = $actor[$name] }
        $x = [double]$actor.X; $y = [double]$actor.Y; $tx = [int]$actor.TX; $ty = [int]$actor.TY
        if ([double]::IsNaN($x) -or [double]::IsInfinity($x) -or [double]::IsNaN($y) -or [double]::IsInfinity($y) -or
            $tx -lt 0 -or $tx -ge $map.W -or $ty -lt 0 -or $ty -ge $map.H) { throw "actor '$($actor.Kind)' is outside the map" }
    }

    $px = [double]$State.Player.X; $py = [double]$State.Player.Y
    if ([double]::IsNaN($px) -or [double]::IsInfinity($px) -or [double]::IsNaN($py) -or [double]::IsInfinity($py) -or
        $px -lt 0 -or $px -ge $map.W -or $py -lt 0 -or $py -ge $map.H) { throw 'player position is outside the map' }
}

# Returns $true if a saved game is now running.
function Restore-Game([string]$Slot = 'quick') {
    if (-not (Test-Path -LiteralPath (Get-SavePath $Slot))) { Show-Message 'No saved game found'; return $false }
    try {
        $state = Get-Content -LiteralPath (Get-SavePath $Slot) -Raw | ConvertFrom-Json -AsHashtable
        $index = -1; $bonus = $null
        for ($i = 0; $i -lt $script:MapFiles.Count; $i++) { if ((Split-Path $script:MapFiles[$i] -Leaf) -eq $state.Map) { $index = $i } }
        if ($index -lt 0 -and $state.Map -match '^bonus(\d+)\.map$') {                # saved on a secret floor
            $bonus = Join-Path (Split-Path $script:MapFiles[0]) $state.Map
            if (Test-Path -LiteralPath $bonus) { $index = [Math]::Min([int]$Matches[1], $script:MapFiles.Count) - 1 } else { $bonus = $null }
        }
        if ($index -lt 0) { throw "the saved game's map '$($state.Map)' is missing" }
        $mapPath = if ($bonus) { $bonus } else { $script:MapFiles[$index] }
        Assert-SaveState $state $mapPath
        $script:BonusMap = $bonus

        $script:Difficulty = [int]$state.Difficulty
        $script:LevelIndex = $index
        $script:LevelStartScore = [int]$state.LevelStartScore
        $script:MapFile = $mapPath
        $script:SecretExit = $false
        Initialize-Level $script:MapFile
        $w = $script:MapW

        $script:Tiles = [int[]]$state.Tiles
        $script:PushTex = [int[]]$state.PushTex
        for ($i = 0; $i -lt $script:Breakable.Length; $i++) { if ($script:Breakable[$i] -and $script:Tiles[$i] -eq 0) { $script:Breakable[$i] = $false } }
        foreach ($i in $state.Seen) { $script:Vis[[int]$i] = 1 }
        if ($script:FrameNo -lt 10) { $script:FrameNo = 10 }
        foreach ($k in @($state.PushWall.Keys)) { $script:PW[$k] = $state.PushWall[$k] }
        foreach ($k in @($state.Stats.Keys)) { $script:Stats[$k] = $state.Stats[$k] }

        for ($i = 0; $i -lt $script:Doors.Count; $i++) {
            $d = $script:Doors[$i]; $sd = $state.Doors[$i]
            $d.Action = $sd.Action; $d.Open = $sd.Open; $d.Timer = $sd.Timer; $d.Unlocked = [bool]$sd.Unlocked
            if ($d.Action -ne 'closed') { $script:AreaConnect[$d.Area1, $d.Area2]++; $script:AreaConnect[$d.Area2, $d.Area1]++ }
        }

        for ($i = 0; $i -lt [Math]::Min($script:Traps.Count, @($state.Traps).Count); $i++) { $script:Traps[$i].Phase = [double]$state.Traps[$i]; $script:Traps[$i].State = -1 }

        # items: drop the map's own, take the saved ones (includes what enemies dropped)
        for ($i = $script:Statics.Count - 1; $i -ge 0; $i--) { if ($null -ne $script:Statics[$i].Item) { $script:Statics.RemoveAt($i) } }
        $script:Items.Clear()
        foreach ($it in $state.Items) { Add-Item $it.Item ([int]$it.X) ([int]$it.Y) }

        [Array]::Clear($script:ActorAt, 0, $script:ActorAt.Length)
        $script:Actors.Clear()
        foreach ($sa in $state.Actors) {
            $a = [Actor]::new()
            foreach ($n in $script:ActorSaveProps) { $a.$n = $sa[$n] }
            $a.Def = if ($script:EnemyDefs.ContainsKey($a.Kind)) { $script:EnemyDefs[$a.Kind] } else { $script:MiscDefs[$a.Kind] }
            $script:Actors.Add($a)
            if (-not $a.Corpse) { $script:ActorAt[$a.TY * $w + $a.TX] = $a }
        }

        New-Player
        foreach ($k in @($state.Player.Keys)) {
            $v = $state.Player[$k]
            $script:P[$k] = if ($v -is [long]) { [int]$v } else { $v }
        }
        $owned = New-OwnedList $false                              # older saves know fewer weapons
        for ($i = 0; $i -lt [Math]::Min($owned.Length, @($state.Player.Owned).Count); $i++) { $owned[$i] = [bool]$state.Player.Owned[$i] }
        $script:P.Owned = $owned
        $script:P.UseHeld = $true; $script:P.FireHeld = $true
        $script:P.RunInvalid = $true                              # a loaded game is no clean speedrun

        Update-AreaByPlayer
        Set-Background
        $script:MapBmp = $null
        Reset-ScreenEffects
        Reset-Abilities
        $script:PlayerDied = $false; $script:LevelDone = $false; $script:Killer = $null
        $script:ShowWeapon = $true
        $script:HudDirty = $true
        Show-Message "Loaded the game saved on $($state.Saved.ToString().Replace('T', ' '))"
        return $true
    }
    catch {
        Show-Message "Loading failed: $($_.Exception.Message)"
        return $false
    }
}

# ---- speedrun records ---------------------------------------------------------------------------
# saves/speedrun.json: the best time per floor and difficulty, and the five fastest full runs.
function Format-Time([double]$Seconds, [switch]$Tenths) {
    $m = [int][Math]::Floor($Seconds / 60); $s = $Seconds - 60 * $m
    if ($Tenths) { '{0}:{1:00.0}' -f $m, ([Math]::Floor($s * 10) / 10) } else { '{0}:{1:00}' -f $m, [int][Math]::Floor($s) }
}

function Get-SpeedrunData {
    $path = Join-Path $script:SaveDir 'speedrun.json'
    $data = $null
    if (Test-Path -LiteralPath $path) { try { $data = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json -AsHashtable } catch { $data = $null } }
    if (-not $data) { $data = @{} }
    if (-not $data.Floors) { $data.Floors = @{} }
    if (-not $data.Runs) { $data.Runs = @() }
    $data
}

function Save-SpeedrunData([hashtable]$Data) {
    try {
        $null = New-Item -ItemType Directory -Path $script:SaveDir -Force
        $Data | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $script:SaveDir 'speedrun.json') -Encoding utf8
    }
    catch { Write-Warning "Could not save the speedrun records: $($_.Exception.Message)" }
}

# Registers a finished floor (and, after the last one, the whole run). Returns the previous best
# time of the floor, or 0 if there was none. Cheated or loaded runs never enter the records.
function Add-SpeedrunResult([double]$FloorSeconds, [bool]$RunComplete) {
    $p = $script:P
    $data = Get-SpeedrunData
    $key = "$(Split-Path $script:MapFile -Leaf)|$($script:Difficulty)"
    $previous = [double]$data.Floors[$key]
    if ($p.Cheated -or $p.RunInvalid) { return $previous }
    if ($previous -le 0 -or $FloorSeconds -lt $previous) { $data.Floors[$key] = [Math]::Round($FloorSeconds, 1) }
    if ($RunComplete -and $script:StartLevelIndex -eq 0) {
        $run = @{ Name = $env:USERNAME; Seconds = [Math]::Round($p.RunTics / $script:TICRATE, 1); Difficulty = $script:Difficulties[$script:Difficulty].Name; Date = (Get-Date).ToString('yyyy-MM-dd') }
        $data.Runs = @(@($data.Runs) + $run | Sort-Object { [double]$_.Seconds } | Select-Object -First 5)
    }
    Save-SpeedrunData $data
    $previous
}

# ---- high scores ------------------------------------------------------------------------------
function Get-HighScores {
    $path = Join-Path $script:SaveDir 'highscores.json'
    if (-not (Test-Path -LiteralPath $path)) { return @() }
    try { @(Get-Content -LiteralPath $path -Raw | ConvertFrom-Json) } catch { @() }
}

function Add-HighScore([int]$Score, [string]$Result) {
    if ($Score -le 0) { return }
    $entry = [pscustomobject]@{ Name = $env:USERNAME; Score = $Score; Result = $Result; Difficulty = $script:Difficulties[$script:Difficulty].Name; Date = (Get-Date).ToString('yyyy-MM-dd') }
    $list = @(Get-HighScores) + $entry | Sort-Object Score -Descending | Select-Object -First 5
    try {
        $null = New-Item -ItemType Directory -Path $script:SaveDir -Force
        ConvertTo-Json @($list) -Depth 3 | Set-Content -LiteralPath (Join-Path $script:SaveDir 'highscores.json') -Encoding utf8
    }
    catch { Write-Warning "Could not save the high scores: $($_.Exception.Message)" }
}
