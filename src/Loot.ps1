# POLF 3D - Copyright (c) 2026 oNdsen. Licensed under the MIT License, see LICENSE.

# Loot.ps1 - what the fallen leave behind, and what the player makes of it.
#
#   Loot tables   every kind of enemy has a list of @(item, chance in percent); each entry is rolled by itself with the
#                 floor's own random numbers, so a demo drops the same things. 'mgun_or_clip' and 'key_gold' keep their
#                 special meaning (Actors.ps1).
#   Armour        a vest (+50) or a shard of one (+15), 100 at most. It takes half of every hit until it is gone.
#   Keycards      officers carry them, auditors always do. A locked door without the key eats one and stays open.
#   Scrap         what is left of a machine: ten privilege.
#   Signed drops  rare - and certain at a silent streak of five: a module that is imported for the rest of the floor
#                 (Import-Module ... -Scope Floor). Overclock: the guns cycle faster. ArmorPiercing: bullets hit half as
#                 hard again and go through shields. Compress-Archive: every second round is free.
#   Silent streak enemies killed one after another without anybody having noticed the player in between. From three on
#                 every such kill leaves something extra; the fifth brings a signed drop. Being noticed ends it.

$script:LootTables = @{
    guard    = @(@('clip_small', 100), @('food', 6))
    officer  = @(@('clip_small', 100), @('keycard', 30))
    elite    = @(@('mgun_or_clip', 100), @('armor_shard', 20))
    mutant   = @(@('clip_small', 100), @('food', 30))
    sniper   = @(@('clip_small', 100), @('tknives', 25))
    shield   = @(@('clip_small', 100), @('armor_shard', 40))
    bot      = @(, @('scrap', 50))
    turret   = @(@('clip_small', 100), @('scrap', 100))
    camera   = @(, @('scrap', 35))
    engineer = @(@('clip_small', 100), @('armor_shard', 60), @('mine', 30))
    auditor  = @(, @('keycard', 100))
    boss     = @(@('key_gold', 100), @('vest', 100))
    pilot    = @(, @('crown', 100))
}
$script:SignedModules = [ordered]@{
    'Overclock'        = 'the guns cycle half as fast again'
    'ArmorPiercing'    = 'bullets hit half as hard again and go through shields'
    'Compress-Archive' = 'every second round is free'
}
$script:SIGNED_CHANCE = 3                       # percent, per humanoid kill

function Test-Signed([string]$Name) { $script:P -and $script:P.Signed -and $script:P.Signed -contains $Name }

# What this enemy leaves behind: item names, rolled with the floor's random numbers.
function Get-Loot([Actor]$a) {
    # (assigned, not returned from an if: that would unroll a table with a single entry into its two halves)
    $table = @()
    if ($a.Def.Loot) { $table = $a.Def.Loot } elseif ($script:LootTables.ContainsKey($a.Kind)) { $table = $script:LootTables[$a.Kind] } elseif ($a.Def.Drop) { $table = @(, @($a.Def.Drop, 100)) }      # a mod's enemy: its own Loot, or the old single Drop
    $items = [System.Collections.Generic.List[string]]::new()
    foreach ($entry in $table) { if ($entry -is [array] -and ($entry[1] -ge 100 -or $script:Rng.Next(100) -lt $entry[1])) { $items.Add([string]$entry[0]) } }
    if ($a.Def.Rotates -and -not $a.Def.NoCount -and $script:Rng.Next(100) -lt $script:SIGNED_CHANCE) { $items.Add('signed') }
    # the silent streak: from the third on something extra, the fifth is signed
    $streak = [int]$script:Stats.Streak
    if ($streak -ge 5 -and $streak % 5 -eq 0) { if ('signed' -notin $items) { $items.Add('signed') } }
    elseif ($streak -ge 3) { $items.Add($(if ($streak % 2) { 'armor_shard' } else { 'food' })) }
    $items
}

# Called when an enemy dies ($Unaware: it never knew), and when one notices the player.
function Update-Streak([bool]$Unaware) {
    $st = $script:Stats
    if (-not $Unaware) { return }
    $st.Streak = [int]$st.Streak + 1
    if ($st.Streak -ge 3 -and -not $script:Predicting) { Show-Message "Silent streak x$($st.Streak)$(if ($st.Streak % 5 -eq 0) { ' - a signed drop!' } else { ' - they leave more behind' })" }
}
function Reset-Streak { if ($script:Stats -and [int]$script:Stats.Streak -gt 0) { $script:Stats.Streak = 0 } }

# Armour takes half of a hit for as long as it lasts. Returns what gets through to the health.
function Get-ArmoredDamage([int]$Points) {
    $p = $script:P
    if ([int]$p.Armor -le 0 -or $Points -le 0) { return $Points }
    $taken = [Math]::Min([int]$p.Armor, [int][Math]::Ceiling($Points / 2.0))
    $p.Armor = [int]$p.Armor - $taken
    $Points - $taken
}

# The pick-ups of this file. Returns $null for items that are none of its business.
function Invoke-LootPickup([string]$Item) {
    $p = $script:P
    switch ($Item) {
        'armor_shard' { if ([int]$p.Armor -ge 100) { return $false }; $p.Armor = [Math]::Min(100, [int]$p.Armor + 15); Start-Sfx 'ammo'; return $true }
        'vest'        { if ([int]$p.Armor -ge 100) { return $false }; $p.Armor = [Math]::Min(100, [int]$p.Armor + 50); Start-Sfx 'weapon'; Show-Message 'Armour: it takes half of every hit until it is gone'; return $true }
        'keycard'     { $p.Keycards = [int]$p.Keycards + 1; Start-Sfx 'key'; Show-Message "Keycard ($($p.Keycards)): opens one locked door for good"; return $true }
        'scrap'       { Add-Privilege 10; Start-Sfx 'pickup'; return $true }
        'signed'      {
            $free = @($script:SignedModules.Keys | Where-Object { -not (Test-Signed $_) })
            if (-not $free.Count) { Add-Privilege 25; Start-Sfx 'pickup'; return $true }
            $name = $free[$script:Rng.Next($free.Count)]
            $p.Signed = @($p.Signed) + $name
            Start-Sfx 'sudo'; Show-Message "Import-Module $name -Scope Floor   # $($script:SignedModules[$name])"
            Add-TranscriptLine "Import-Module $name -Scope Floor"
            return $true
        }
    }
    $null
}
