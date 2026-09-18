# POLF 3D - Copyright (c) 2026 oNdsen. Licensed under the MIT License, see LICENSE.

# Events.ps1 - things that happen to a floor at a fixed time, whether the player is ready or not. A map lists
# them in its header: "@event <kind> <seconds after the floor started>".
#
#   lockdown    every plain door slams shut and is sealed for fifteen seconds. The player's own hand still opens
#               them ("use"), so for a quarter of a minute nobody can follow - or come to help
#   powerfail   the light goes out on the whole floor for twenty-five seconds: flashlight and muzzle flashes only,
#               and nobody sees further than three and a half tiles unless the player carries a light
#   patch       Patch Tuesday. There is a countdown on the screen. When it runs out every enemy still alive is
#               restored to full health and the building's execution policy heats up by thirty
#
# What has fired already is a bit mask in $script:Stats (so are the tics the power stays out): saved games, Undo and
# the -WhatIf forecast take it along, and demos replay it, because the floor's clock is part of the simulation.

$script:LevelEvents = @()
$script:EventNames = @{ lockdown = 'LOCKDOWN'; powerfail = 'POWER FAILURE'; patch = 'PATCH TUESDAY' }

function Invoke-LevelEvent([string]$Kind) {
    switch ($Kind) {
        'lockdown' {
            for ($i = 0; $i -lt $script:Doors.Count; $i++) {
                $d = $script:Doors[$i]
                if ($d.Lock -ne 0) { continue }                  # locks, levers and the lift have rules of their own
                Close-Door $i; $d.Jam = 1050.0
            }
            Start-Sfx 'alarm'
            Show-Message 'LOCKDOWN - every door is sealed for fifteen seconds. Only your own hand opens them.'
        }
        'powerfail' {
            $script:Stats.PowerOut = 1750.0
            Start-Sfx 'noway'
            Show-Message "POWER FAILURE - twenty-five seconds of darkness. $(Get-KeyName $script:Bind.Light) = flashlight"
        }
        'patch' {
            $healed = 0
            foreach ($a in $script:Actors) {
                if (-not $a.Shootable -or $a.Def.Inert -or $a.Hacked -or -not $a.Def.HP -or $a.Kind -in 'peer', 'whatif') { continue }
                $full = [int]@($a.Def.HP)[[Math]::Min($script:Difficulty, @($a.Def.HP).Count - 1)]
                if ($a.HP -lt $full) { $a.HP = $full; $healed++ }
            }
            Add-PolicyHeat 30
            Start-Sfx 'sudo'
            Show-Message "PATCH TUESDAY - updates installed: $healed of them are as good as new. Do not switch off your enemies."
        }
    }
    if (-not $script:Predicting) { Add-TranscriptLine "the floor's schedule: $($script:EventNames[$Kind])" 'WARNING' }
}

# Once a frame, with the world's tics.
function Update-Events([double]$Tics) {
    $st = $script:Stats
    if ($st.PowerOut -gt 0) { $st.PowerOut -= $Tics; if ($st.PowerOut -le 0 -and -not $script:Predicting) { Show-Message 'The power is back.' } }
    if (-not $script:LevelEvents.Count) { return }
    $done = [int]$st.EventsDone
    for ($i = 0; $i -lt $script:LevelEvents.Count; $i++) {
        if (($done -band (1 -shl $i)) -or $st.Tics -lt $script:LevelEvents[$i].At) { continue }
        $st.EventsDone = $done = $done -bor (1 -shl $i)
        Invoke-LevelEvent $script:LevelEvents[$i].Kind
    }
}

# For the HUD: the next event that announces itself - Patch Tuesday always, the others ten seconds ahead.
function Get-EventNotice {
    $st = $script:Stats; $best = $null
    for ($i = 0; $i -lt $script:LevelEvents.Count; $i++) {
        $e = $script:LevelEvents[$i]
        if ([int]$st.EventsDone -band (1 -shl $i)) { continue }
        $left = ($e.At - $st.Tics) / $script:TICRATE
        if ($e.Kind -ne 'patch' -and $left -gt 10) { continue }
        if (-not $best -or $left -lt $best.Left) { $best = @{ Left = $left; Text = "$($script:EventNames[$e.Kind]) in $(Format-Time ([Math]::Max(0, $left)))"; Color = $(if ($left -lt 30) { 'FF4030' } else { 'F9F1A5' }) } }
    }
    if ($st.PowerOut -gt 0) { $best = @{ Left = 0; Text = "POWER FAILURE  $([int][Math]::Ceiling($st.PowerOut / $script:TICRATE)) s"; Color = 'FF4030' } }
    $best
}
