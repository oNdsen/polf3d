# POLF 3D - Copyright (c) 2026 oNdsen. Licensed under the MIT License, see LICENSE.

# SaveGame.ps1 - quick save / quick load (JSON) and the high score list.
#
# A save file holds only what differs from a freshly loaded map: the tile grid (push-walls,
# the switch), doors, items, actors, the player and the statistics. Loading rebuilds the level
# from its map file and then lays the saved state over it.

$script:ActorSaveProps = 'Kind', 'State', 'Tics', 'X', 'Y', 'TX', 'TY', 'Dir', 'PathDir', 'Dist', 'WaitDoor', 'Speed', 'HP', 'Area',
                         'Active', 'Shootable', 'AttackMode', 'FirstAttack', 'Ambush', 'Corpse', 'React', 'VX', 'VY'

function Get-SavePath { Join-Path $script:SaveDir 'quicksave.json' }

function Test-SaveGame { Test-Path -LiteralPath (Get-SavePath) }

function Save-Game {
    $seen = for ($i = 0; $i -lt $script:Vis.Length; $i++) { if ($script:Vis[$i] -gt 0) { $i } }
    $state = [ordered]@{
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
        Doors      = @(foreach ($d in $script:Doors) { @{ Action = $d.Action; Open = $d.Open; Timer = $d.Timer; Unlocked = $d.Unlocked } })
        Items      = @(foreach ($s in $script:Items) { if (-not $s.Removed) { @{ Item = $s.Item; X = $s.X; Y = $s.Y } } })
        Actors     = @(foreach ($a in $script:Actors) { $h = @{}; foreach ($n in $script:ActorSaveProps) { $h[$n] = $a.$n }; $h })
    }
    try {
        $null = New-Item -ItemType Directory -Path $script:SaveDir -Force
        $state | ConvertTo-Json -Depth 6 -Compress | Set-Content -LiteralPath (Get-SavePath) -Encoding utf8
        Show-Message 'Game saved'
    }
    catch { Show-Message "Saving failed: $($_.Exception.Message)" }
}

# Returns $true if a saved game is now running.
function Restore-Game {
    if (-not (Test-SaveGame)) { Show-Message 'No saved game found'; return $false }
    try {
        $state = Get-Content -LiteralPath (Get-SavePath) -Raw | ConvertFrom-Json -AsHashtable
        $index = -1
        for ($i = 0; $i -lt $script:MapFiles.Count; $i++) { if ((Split-Path $script:MapFiles[$i] -Leaf) -eq $state.Map) { $index = $i } }
        if ($index -lt 0) { throw "the saved game's map '$($state.Map)' is missing" }

        $script:Difficulty = [int]$state.Difficulty
        $script:LevelIndex = $index
        $script:LevelStartScore = [int]$state.LevelStartScore
        $script:MapFile = $script:MapFiles[$index]
        Initialize-Level $script:MapFile
        $w = $script:MapW

        $script:Tiles = [int[]]$state.Tiles
        $script:PushTex = [int[]]$state.PushTex
        foreach ($i in $state.Seen) { $script:Vis[[int]$i] = 1 }
        if ($script:FrameNo -lt 10) { $script:FrameNo = 10 }
        foreach ($k in @($state.PushWall.Keys)) { $script:PW[$k] = $state.PushWall[$k] }
        foreach ($k in @($state.Stats.Keys)) { $script:Stats[$k] = $state.Stats[$k] }

        for ($i = 0; $i -lt $script:Doors.Count; $i++) {
            $d = $script:Doors[$i]; $sd = $state.Doors[$i]
            $d.Action = $sd.Action; $d.Open = $sd.Open; $d.Timer = $sd.Timer; $d.Unlocked = [bool]$sd.Unlocked
            if ($d.Action -ne 'closed') { $script:AreaConnect[$d.Area1, $d.Area2]++; $script:AreaConnect[$d.Area2, $d.Area1]++ }
        }

        # items: drop the map's own, take the saved ones (includes what enemies dropped)
        $null = $script:Statics.RemoveAll([Predicate[Static]] { param($s) $null -ne $s.Item })
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
