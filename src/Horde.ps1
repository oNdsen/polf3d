# POLF 3D - Copyright (c) 2026 oNdsen. Licensed under the MIT License, see LICENSE.

# Horde.ps1 - the arena (H on the title screen, or -Horde [number]). One life, one hall, and wave after wave coming
# out of the four gates: every wave has more to spend than the last, every fifth brings a commander, every tenth
# a war machine. Between the waves supplies drop in the middle of the hall, and now and then a new weapon.
# The waves are made from the horde's number: the same number, the same waves - so runs can be compared, and
# saves/horde.json keeps the best of every number and difficulty. The lift is the way out: taking it ends the run.
# The host of a co-op game can open the arena too (H, or -HostGame Coop -Horde): the waves grow with the number of
# players, nobody runs out of lives, and the run is not rated. The guests load the arena the way they load a secret floor.
#
# What a wave still has to send is kept in $script:Stats (a new array with every change): Undo and saved games work.

$script:HordeSeed = 0
$script:HordePrices = [ordered]@{ guard = 1; dog = 1; officer = 2; bot = 2; elite = 3; mutant = 3; sniper = 3; shield = 4 }
$script:HordeGifts = @{ 2 = 'mgun'; 4 = 'chaingun'; 6 = 'launcher'; 8 = 'pipeline'; 10 = 'flamer'; 12 = 'forcegun' }

function Get-HordeMap { Join-Path (Split-Path $script:MapFiles[0]) 'arena.map' }
function Get-HordePath { Join-Path $script:SaveDir 'horde.json' }

function Start-Horde([int]$Seed) {
    if ($script:Net -and ($script:Net.Role -ne 'host' -or $script:Net.Mode -ne 'coop')) { Show-Message 'In a network game the arena is opened by the host of a co-op game'; return $false }
    if (-not (Test-Path -LiteralPath (Get-HordeMap))) { Show-Message 'maps/arena.map is missing'; return $false }
    if ($Seed -le 0) { $Seed = Get-DailySeed }
    $script:HordeSeed = $Seed; $script:BonusMap = $null; $script:NextSeed = $Seed
    Start-Level $false $false
    $script:P.Lives = 0                                           # one life
    Show-Message "Horde #$Seed - one life. They come through the four gates. The lift is the way out."
    $true
}

function Stop-Horde { $script:HordeSeed = 0 }

# Who comes with wave $Wave: a shopping trip with a budget, the dearer ones only from later waves on.
function Get-HordeWave([int]$Wave) {
    $rng = [System.Random]::new(($script:HordeSeed % 1000000) * 97 + $Wave)
    $budget = 4 + 3 * $Wave
    if ($script:Net) { $budget = [int]($budget * (1.0 + 0.6 * @($script:Net.Guests).Count)) }      # more players, more visitors
    $list = [System.Collections.Generic.List[string]]::new()
    if ($Wave % 10 -eq 0) { $list.Add('uber'); $budget -= 12 } elseif ($Wave % 5 -eq 0) { $list.Add('boss'); $budget -= 8 }
    $kinds = @($script:HordePrices.Keys | Where-Object { $script:HordePrices[$_] -le 1 + $Wave / 2 })
    while ($budget -gt 0 -and $list.Count -lt 40) {
        $kind = $kinds[$rng.Next($kinds.Count)]
        if ($script:HordePrices[$kind] -gt $budget) { $kind = 'guard' }
        $list.Add($kind); $budget -= $script:HordePrices[$kind]
    }
    $list.ToArray()
}

# Between the waves: ammunition, first aid - and what the wave number promises.
function Add-HordeSupplies([int]$Wave) {
    $cx = [int]($script:MapW / 2); $cy = [int]($script:MapH / 2)
    $drops = @('clip', 'clip') + $(if ($Wave % 2 -eq 0) { 'medkit' } else { 'food' }) + $(if ($script:P.Owned[6]) { 'rockets' }) + $(if ($Wave % 3 -eq 0) { 'charge' }) + $script:HordeGifts[$Wave]
    $spots = @(-1, -1), @(1, -1), @(-1, 1), @(1, 1), @(0, -2), @(0, 2), @(-2, 0), @(2, 0)
    $i = 0
    foreach ($item in $drops) { if ($item) { Add-Item $item ($cx + $spots[$i % 8][0]) ($cy + $spots[$i % 8][1]); $i++ } }
}

# Once a frame. Stats: Wave, WaveQueue (kinds still to come), WaveTimer (tics to the next arrival / the next wave).
function Update-Horde([double]$Tics) {
    if (-not $script:HordeSeed) { return }
    $st = $script:Stats
    if ($null -eq $st.Wave) { $st.Wave = 0; $st.WaveQueue = @(); $st.WaveTimer = 210.0 }
    $st.WaveTimer -= $Tics
    $queue = @($st.WaveQueue)
    if ($queue.Count) {
        if ($st.WaveTimer -gt 0) { return }
        # the next one steps out of a gate - the first gate that is free, starting with a different one every time
        for ($g = 0; $g -lt $script:HordeSpots.Count; $g++) {
            $spot = $script:HordeSpots[($g + $queue.Count) % $script:HordeSpots.Count]
            if (-not (Test-TileFree $spot[0] $spot[1])) { continue }
            $a = New-Enemy $queue[0] $spot[0] $spot[1] 6 'stand'
            $a.Active = $true; $script:ActorAt[$spot[1] * $script:MapW + $spot[0]] = $a
            $script:NewActors.Add($a); $st.KillTotal++
            if ($queue[0] -eq 'uber') { $st.KillTotal++ }
            $script:PolicyQuiet = $true; Start-Attack $a; $script:PolicyQuiet = $false
            $st.WaveQueue = @($queue | Select-Object -Skip 1)
            break
        }
        $st.WaveTimer = [Math]::Max(25.0, 70.0 - 2.0 * $st.Wave)
        return
    }
    if ($st.Kills -lt $st.KillTotal) { $st.WaveTimer = 280.0; return }      # somebody is still standing: the break starts when the last one falls
    if ($st.WaveTimer -gt 0) { return }
    if ($st.Wave -gt 0) { Add-Score (500 * $st.Wave) }
    $st.Wave++
    $st.WaveQueue = @(Get-HordeWave $st.Wave)
    $st.WaveTimer = 0.0
    if ($st.Wave -gt 1) { Add-HordeSupplies ($st.Wave - 1) }
    Start-Sfx 'alarm'
    Show-Message "WAVE $($st.Wave)  -  $(@($st.WaveQueue).Count) of them$(if ($st.Wave -gt 1) { '.  Supplies are in the middle of the hall.' })"
    Add-TranscriptLine "wave $($st.Wave): $((@($st.WaveQueue) | Group-Object | ForEach-Object { "$($_.Count) $($_.Name)" }) -join ', ')" 'WARNING'
}

function Get-HordeNotice {
    $st = $script:Stats
    if (-not $st.Wave) { return @{ Text = 'the gates open in a moment'; Color = 'F9F1A5' } }
    $left = $st.KillTotal - $st.Kills + @($st.WaveQueue).Count
    @{ Text = "WAVE $($st.Wave)   $(if ($left) { "$left left" } else { 'cleared' })"; Color = $(if ($left) { 'FF4030' } else { '60FF80' }) }
}

# The end of a run (death, or the lift): into the list, and back comes the line for the screen.
function Save-HordeRun([bool]$Evacuated) {
    $st = $script:Stats; $p = $script:P
    $wave = [int]$st.Wave - $(if ($Evacuated -and $st.Kills -ge $st.KillTotal -and -not @($st.WaveQueue).Count) { 0 } else { 1 })      # completed waves
    $wave = [Math]::Max(0, $wave)
    $runs = @()
    $path = Get-HordePath
    if (Test-Path -LiteralPath $path) { try { $runs = @(Get-Content -LiteralPath $path -Raw | ConvertFrom-Json) } catch { } }
    $mine = @($runs | Where-Object { $_.Seed -eq $script:HordeSeed -and $_.Difficulty -eq $script:Difficulty + 1 } | Sort-Object Waves, Score -Descending)
    $best = if ($mine.Count) { $mine[0] } else { $null }
    if ($script:Net) { $script:HordeResult = "Horde #$($script:HordeSeed): $wave wave(s) cleared together. Co-op runs are not rated."; return $script:HordeResult }
    $line = "Horde #$($script:HordeSeed): $wave wave(s) cleared, $($p.Score) points - " + $(if ($p.Cheated) { 'not rated' } elseif (-not $best) { 'the first run with this number' } elseif ($wave -gt $best.Waves -or ($wave -eq $best.Waves -and $p.Score -gt $best.Score)) { "NEW RECORD (it was $($best.Waves) waves, $($best.Score) points)" } else { "your best: $($best.Waves) waves, $($best.Score) points" })
    if (-not $p.Cheated) {
        $runs = @($runs) + [pscustomobject]@{ Seed = $script:HordeSeed; Difficulty = $script:Difficulty + 1; Waves = $wave; Score = $p.Score; Evacuated = $Evacuated; Date = (Get-Date).ToString('yyyy-MM-dd') }
        try { $null = New-Item -ItemType Directory -Path $script:SaveDir -Force; ConvertTo-Json @($runs | Select-Object -Last 200) | Set-Content -LiteralPath $path -Encoding utf8 } catch { }
    }
    $script:HordeResult = $line
    $line
}
