# POLF 3D - Copyright (c) 2026 oNdsen. Licensed under the MIT License, see LICENSE.

# Policy.ps1 - the building's execution policy: how nervous the whole floor is. Being seen and making
# noise heat it up, keeping quiet lets it cool down again (about a point every two seconds).
#
#   Restricted     nobody suspects a thing - and nobody watches the logs: privilege comes back faster
#   AllSigned      they have been told to look twice: quicker to react, gunfire carries further
#   RemoteSigned   everybody is on edge
#   Unrestricted   the alarm: everybody in reach comes for you, and every shot is heard everywhere
#
# The heat is kept in $script:Stats, so saved games, Undo and the -WhatIf forecast take it along.
# In the console: Get-ExecutionPolicy, and Set-ExecutionPolicy <name> - calming the house down costs privilege.

$script:PolicyLevels = @(
    @{ Name = 'Restricted';   From = 0;  Color = '60FF80'; React = 1.0;  Hear = 1.0;  Text = 'nobody suspects a thing' }
    @{ Name = 'AllSigned';    From = 25; Color = 'F9F1A5'; React = 0.8;  Hear = 1.25; Text = 'they have been told to look twice' }
    @{ Name = 'RemoteSigned'; From = 55; Color = 'FFA040'; React = 0.6;  Hear = 1.6;  Text = 'everybody is on edge' }
    @{ Name = 'Unrestricted'; From = 85; Color = 'FF4030'; React = 0.45; Hear = 99.0; Text = 'THE ALARM - they are all coming' }
)
$script:POLICY_CALM_COST = 15                  # privilege per step down, from the console
$script:PolicyNoisy = $false

function Get-Policy { $script:PolicyLevels[[int]$script:Stats.Policy] }

function Add-PolicyHeat([double]$Points) {
    if ($script:Predicting -or $script:PolicyQuiet -or $null -eq $script:Stats) { return }
    $scale = (0.5, 0.75, 1.0, 1.25)[$script:Difficulty]
    $script:Stats.Heat = [Math]::Max(0.0, [Math]::Min(100.0, [double]$script:Stats.Heat + $Points * $(if ($Points -gt 0) { $scale } else { 1.0 })))
}

# The alarm: whoever can get to the player comes running.
function Start-PolicyAlarm {
    $script:PolicyQuiet = $true                                  # their shouting must not heat things up any further
    foreach ($a in $script:Actors) {
        if ($a.Shootable -and -not $a.Def.Inert -and -not $a.AttackMode -and $a.Kind -notin 'peer', 'whatif' -and $script:AreaByPlayer[$a.Area]) { $a.React = 0; Start-Attack $a }
    }
    $script:PolicyQuiet = $false
    Start-Sfx 'alarm'
}

# Once a frame, before the enemies think.
function Update-Policy([double]$Tics) {
    $st = $script:Stats
    if ($null -eq $st.Heat) { $st.Heat = 0.0; $st.Policy = 0 }
    if ($script:MadeNoise) { Add-PolicyHeat $(if ($script:PolicyNoisy) { 0.04 * $Tics } else { 1.2 }) }
    $script:PolicyNoisy = [bool]$script:MadeNoise
    Add-PolicyHeat (- $Tics / 140.0)
    # up at the threshold, down only ten points below it: no flickering between two levels
    $level = [int]$st.Policy
    while ($level -lt 3 -and $st.Heat -ge $script:PolicyLevels[$level + 1].From) { $level++ }
    while ($level -gt 0 -and $st.Heat -lt $script:PolicyLevels[$level].From - 10) { $level-- }
    if ($level -eq [int]$st.Policy) { return }
    $rising = $level -gt [int]$st.Policy
    $st.Policy = $level
    $policy = Get-Policy
    if ($script:Predicting) { return }
    Show-Message "Set-ExecutionPolicy $($policy.Name)  -  $($policy.Text)"
    Add-TranscriptLine "the execution policy is now $($policy.Name)" $(if ($rising) { 'WARNING' } else { 'VERBOSE' })
    $script:HudDirty = $true
    if ($rising -and $level -eq 3) { Start-PolicyAlarm } elseif ($rising) { Start-Sfx 'noway' }
}

# Set-ExecutionPolicy from the console. Returns @{ Ok; Text = the line to print }.
function Set-Policy([string]$Name) {
    $st = $script:Stats; $p = $script:P
    $want = -1
    for ($i = 0; $i -lt $script:PolicyLevels.Count; $i++) { if ($script:PolicyLevels[$i].Name -eq $Name.Trim()) { $want = $i } }
    if ($want -lt 0) { return @{ Ok = $false; Text = "Set-ExecutionPolicy: '$Name' is none of Restricted, AllSigned, RemoteSigned, Unrestricted." } }
    $now = [int]$st.Policy
    if ($want -eq $now) { return @{ Ok = $true; Text = "The execution policy is $($script:PolicyLevels[$now].Name) already." } }
    if ($want -gt $now) {
        $st.Heat = [double]$script:PolicyLevels[$want].From + 5
        return @{ Ok = $true; Text = "As you wish: the heat is on. (Free of charge. You will pay for it in other ways.)" }
    }
    $cost = ($now - $want) * $script:POLICY_CALM_COST
    if ($p.Privilege -lt $cost -and -not $script:InfiniteAmmo) { return @{ Ok = $false; Text = "Set-ExecutionPolicy: Access is denied - calming the house down to $Name costs $cost privilege, you have $([int]$p.Privilege)." } }
    if (-not $script:InfiniteAmmo) { Add-Privilege (- $cost) }
    $st.Heat = [double]$script:PolicyLevels[$want].From + $(if ($want -eq 0) { 0 } else { 8 })
    $st.Policy = $want; $script:HudDirty = $true
    $script:Run.Console++
    @{ Ok = $true; Text = "Set-ExecutionPolicy: the house believes it is $Name again.  (-$cost privilege, $([int]$p.Privilege) left) Those who are after you already still are." }
}
