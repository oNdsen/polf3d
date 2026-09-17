# POLF 3D - Copyright (c) 2026 oNdsen. Licensed under the MIT License, see LICENSE.

# Assets.Sfx.ps1 - sound effects are synthesised at start-up (8 bit, 11 kHz, mono) and played
# through System.Media.SoundPlayer. Like the original's sound system there is ONE effect
# channel: a new sound only interrupts the running one if its priority is equal or higher.

$script:SFX_RATE = 11025
$script:Sfx = @{}
$script:SfxEnabled = $true
$script:SfxBusyUntil = 0.0
$script:SfxBusyPrio = 0

# Segment = @(seconds, wave, freqStart, freqEnd, volStart, volEnd); wave: q=square s=saw n=noise
function New-SfxPlayer([object[]]$Segments) {
    $rate = $script:SFX_RATE
    $total = 0
    foreach ($s in $Segments) { $total += [int]($s[0] * $rate) }
    $data = [byte[]]::new($total)
    $rng = $script:Rng
    [int]$pos = 0
    foreach ($s in $Segments) {
        [int]$n = [int]($s[0] * $rate)
        [string]$wave = $s[1]
        [double]$f0 = $s[2]; [double]$df = ($s[3] - $s[2]) / $n
        [double]$v0 = $s[4]; [double]$dv = ($s[5] - $s[4]) / $n
        [double]$phase = 0; [double]$held = 0; [int]$lastCycle = -1
        for ([int]$i = 0; $i -lt $n; $i++) {
            $phase += ($f0 + $df * $i) / $rate
            [int]$cycle = [Math]::Floor($phase)
            [double]$frac = $phase - $cycle
            if ($wave -eq 'q') { $smp = if ($frac -lt 0.5) { 1.0 } else { -1.0 } }
            elseif ($wave -eq 's') { $smp = 2.0 * $frac - 1.0 }
            else {
                if ($cycle -ne $lastCycle) { $held = $rng.NextDouble() * 2.0 - 1.0; $lastCycle = $cycle }
                $smp = $held
            }
            $data[$pos++] = [byte](128 + [Math]::Floor(120.0 * $smp * ($v0 + $dv * $i)))
        }
    }

    $ms = [System.IO.MemoryStream]::new()
    $bw = [System.IO.BinaryWriter]::new($ms)
    $bw.Write([byte[]][char[]]'RIFF'); $bw.Write([int](36 + $total)); $bw.Write([byte[]][char[]]'WAVEfmt ')
    $bw.Write([int]16); $bw.Write([int16]1); $bw.Write([int16]1); $bw.Write([int]$rate); $bw.Write([int]$rate)
    $bw.Write([int16]1); $bw.Write([int16]8)
    $bw.Write([byte[]][char[]]'data'); $bw.Write([int]$total); $bw.Write($data)
    $bw.Flush()
    $ms.Position = 0
    $player = [System.Media.SoundPlayer]::new($ms)
    $player.Load()
    @{ Player = $player; Seconds = $total / $rate }
}

function Initialize-Sounds {
    if (-not $script:SfxEnabled) { return }
    $defs = @{
        knife         = @(2, @(, @(0.09, 'n', 3000, 800, 0.35, 0.0)))
        shot_pistol   = @(5, @(@(0.03, 'n', 5000, 3000, 1.0, 0.8), @(0.16, 'n', 2200, 300, 0.8, 0.0)))
        shot_mgun     = @(5, @(@(0.02, 'n', 6000, 3000, 1.0, 0.8), @(0.09, 'n', 1800, 400, 0.7, 0.0)))
        shot_chain    = @(5, @(@(0.02, 'n', 4000, 2000, 1.0, 0.9), @(0.07, 'n', 1200, 250, 0.9, 0.0)))
        shot_enemy    = @(4, @(@(0.03, 'n', 3000, 1500, 0.7, 0.6), @(0.14, 'n', 1200, 200, 0.6, 0.0)))
        shot_elite    = @(4, @(@(0.02, 'n', 3500, 2000, 0.8, 0.6), @(0.08, 'n', 1500, 300, 0.6, 0.0)))
        shot_boss     = @(4, @(@(0.03, 'n', 2500, 1200, 1.0, 0.8), @(0.10, 'n', 900, 150, 0.9, 0.0)))
        shot_pipe     = @(7, @(@(0.05, 's', 2400, 2400, 0.7, 0.9), @(0.30, 's', 2400, 180, 0.9, 0.0)))
        shot_force    = @(9, @(@(0.25, 'q', 60, 240, 0.5, 1.0), @(0.10, 'n', 6000, 3000, 1.0, 1.0), @(0.80, 'n', 900, 60, 1.0, 0.0)))
        rocket        = @(5, @(, @(0.30, 'n', 500, 1600, 0.7, 0.2)))
        boom          = @(7, @(@(0.05, 'n', 4000, 2000, 1.0, 1.0), @(0.45, 'n', 600, 60, 1.0, 0.0)))
        sudo          = @(8, @(@(0.10, 'q', 262, 262, 0.5, 0.5), @(0.10, 'q', 330, 330, 0.5, 0.5), @(0.10, 'q', 392, 392, 0.5, 0.5), @(0.10, 'q', 523, 523, 0.5, 0.5), @(0.10, 'q', 659, 659, 0.5, 0.5), @(0.30, 'q', 1047, 1047, 0.6, 0.0)))
        alert_uber    = @(9, @(@(0.25, 's', 70, 90, 0.9, 0.9), @(0.06, 'q', 1, 1, 0, 0), @(0.25, 's', 90, 70, 0.9, 0.9), @(0.06, 'q', 1, 1, 0, 0), @(0.45, 's', 110, 45, 0.9, 0.1)))
        die_uber      = @(9, @(@(0.10, 'n', 5000, 2500, 1.0, 1.0), @(0.50, 'n', 800, 100, 1.0, 0.6), @(0.10, 'n', 5000, 2500, 1.0, 1.0), @(0.80, 'n', 500, 40, 1.0, 0.0)))
        shot_sniper   = @(6, @(@(0.02, 'n', 8000, 5000, 1.0, 1.0), @(0.35, 'n', 3000, 150, 0.9, 0.0)))
        clang         = @(4, @(@(0.03, 'q', 2600, 2400, 0.6, 0.5), @(0.12, 'q', 1900, 1700, 0.4, 0.0)))
        bot_beep      = @(6, @(@(0.06, 'q', 1800, 1800, 0.5, 0.5), @(0.04, 'q', 1, 1, 0, 0), @(0.06, 'q', 1800, 1800, 0.5, 0.5), @(0.04, 'q', 1, 1, 0, 0), @(0.10, 'q', 2400, 2400, 0.5, 0.2)))
        bite          = @(4, @(@(0.05, 'n', 900, 500, 0.8, 0.6), @(0.08, 's', 180, 90, 0.7, 0.0)))
        alert_guard   = @(6, @(@(0.10, 'q', 330, 260, 0.5, 0.5), @(0.03, 'q', 1, 1, 0, 0), @(0.16, 'q', 300, 190, 0.5, 0.1)))
        alert_officer = @(6, @(@(0.08, 'q', 420, 470, 0.5, 0.5), @(0.03, 'q', 1, 1, 0, 0), @(0.08, 'q', 470, 420, 0.5, 0.5), @(0.12, 'q', 380, 280, 0.5, 0.1)))
        alert_elite   = @(6, @(@(0.14, 'q', 200, 240, 0.6, 0.6), @(0.03, 'q', 1, 1, 0, 0), @(0.18, 'q', 240, 130, 0.6, 0.1)))
        alert_dog     = @(6, @(@(0.07, 's', 500, 300, 0.7, 0.4), @(0.04, 'q', 1, 1, 0, 0), @(0.09, 's', 520, 260, 0.7, 0.1)))
        alert_boss    = @(8, @(@(0.20, 'q', 110, 140, 0.8, 0.8), @(0.05, 'q', 1, 1, 0, 0), @(0.35, 'q', 140, 70, 0.8, 0.1)))
        die_a         = @(5, @(, @(0.35, 'q', 420, 110, 0.55, 0.0)))
        die_b         = @(5, @(@(0.12, 'q', 300, 360, 0.55, 0.5), @(0.30, 'q', 360, 90, 0.5, 0.0)))
        die_c         = @(5, @(, @(0.40, 's', 200, 60, 0.7, 0.0)))
        die_dog       = @(5, @(@(0.08, 's', 700, 900, 0.6, 0.6), @(0.22, 's', 900, 250, 0.6, 0.0)))
        die_boss      = @(8, @(@(0.30, 'q', 160, 200, 0.8, 0.8), @(0.70, 'q', 200, 40, 0.8, 0.0)))
        door_open     = @(2, @(, @(0.35, 'n', 300, 700, 0.35, 0.1)))
        door_close    = @(2, @(@(0.28, 'n', 700, 300, 0.3, 0.3), @(0.05, 'n', 150, 100, 0.8, 0.0)))
        pickup        = @(3, @(@(0.05, 'q', 660, 660, 0.4, 0.4), @(0.08, 'q', 880, 880, 0.4, 0.1)))
        ammo          = @(3, @(@(0.04, 'n', 2500, 2500, 0.5, 0.2), @(0.05, 'q', 520, 520, 0.4, 0.1)))
        weapon        = @(6, @(@(0.07, 'q', 392, 392, 0.5, 0.5), @(0.07, 'q', 523, 523, 0.5, 0.5), @(0.16, 'q', 784, 784, 0.5, 0.1)))
        key           = @(6, @(@(0.06, 'q', 988, 988, 0.4, 0.4), @(0.06, 'q', 1319, 1319, 0.4, 0.4), @(0.12, 'q', 1568, 1568, 0.4, 0.0)))
        treasure      = @(4, @(@(0.05, 'q', 1047, 1047, 0.4, 0.4), @(0.05, 'q', 1319, 1319, 0.4, 0.4), @(0.10, 'q', 2093, 2093, 0.4, 0.0)))
        oneup         = @(7, @(@(0.08, 'q', 523, 523, 0.5, 0.5), @(0.08, 'q', 659, 659, 0.5, 0.5), @(0.08, 'q', 784, 784, 0.5, 0.5), @(0.25, 'q', 1047, 1047, 0.5, 0.0)))
        pain          = @(6, @(, @(0.18, 's', 260, 140, 0.8, 0.1)))
        player_die    = @(10, @(@(0.25, 's', 300, 200, 0.8, 0.7), @(0.75, 's', 200, 40, 0.7, 0.0)))
        pushwall      = @(7, @(, @(1.20, 'n', 120, 80, 0.7, 0.3)))
        noway         = @(3, @(@(0.07, 'q', 110, 110, 0.5, 0.5), @(0.03, 'q', 1, 1, 0, 0), @(0.09, 'q', 90, 90, 0.5, 0.2)))
        level_done    = @(10, @(@(0.12, 'q', 523, 523, 0.5, 0.5), @(0.12, 'q', 659, 659, 0.5, 0.5), @(0.12, 'q', 784, 784, 0.5, 0.5), @(0.12, 'q', 1047, 1047, 0.5, 0.5), @(0.35, 'q', 1319, 1319, 0.5, 0.0)))
    }
    try {
        foreach ($name in $defs.Keys) {
            $p = New-SfxPlayer $defs[$name][1]
            $p.Prio = $defs[$name][0]
            $script:Sfx[$name] = $p
        }
    }
    catch {
        Write-Warning "Sound disabled: $($_.Exception.Message)"
        $script:SfxEnabled = $false
    }
}

function Start-Sfx([string]$Name) {
    if (-not $script:SfxEnabled -or -not $Name) { return }
    $s = $script:Sfx[$Name]
    if ($null -eq $s) { return }
    $now = $script:Clock.Elapsed.TotalSeconds
    if ($now -lt $script:SfxBusyUntil -and $s.Prio -lt $script:SfxBusyPrio) { return }
    try { $s.Player.Play() } catch { $script:SfxEnabled = $false; return }
    $script:SfxBusyUntil = $now + $s.Seconds
    $script:SfxBusyPrio = $s.Prio
}
