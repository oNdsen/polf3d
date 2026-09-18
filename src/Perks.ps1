# POLF 3D - Copyright (c) 2026 oNdsen. Licensed under the MIT License, see LICENSE.

# Perks.ps1 - Install-Module. After every floor of the campaign the lift offers three modules; one of them can be
# installed (1, 2 or 3 on the floor-completed screen) and stays for the rest of the run. They are kept in
# $script:P.Modules, so saved games and Undo take them along. Get-Module in the console lists what is installed.
# Not in network games (the host decides what hurts whom) and not in the dungeon (a run must be comparable).

$script:ModulePerks = [ordered]@{
    'PSReadLine'          = 'the powers cost a quarter less privilege'
    'ThreadJob'           = 'the drone costs 15, carries ten things and flies half as fast again'
    'SecretManagement'    = 'secret and cracked walls are marked on the automap of every floor'
    'Pester'              = 'whoever has not noticed you takes triple instead of double damage'
    'PSScriptAnalyzer'    = '-Verbose is free and lasts twice as long'
    'PowerShellGet'       = 'every clip holds a quarter more rounds'
    'Microsoft.PowerShell.Archive' = 'food and first aid heal half as much again'
    'PSWindowsUpdate'     = 'privilege comes back half as fast again'
}

function Test-Perk([string]$Name) { $script:P -and $script:P.Modules -and $script:P.Modules -contains $Name }

# Three modules that are not installed yet - the same three for the same floor and score.
function Get-PerkOffer {
    if ($script:Net -or $script:DungeonSeed -or $script:MapFiles.Count -le 1) { return @() }
    $free = @($script:ModulePerks.Keys | Where-Object { -not (Test-Perk $_) })
    $rng = [System.Random]::new($script:LevelIndex * 7919 + [int]($script:P.Score % 100000))
    $offer = @()
    while ($offer.Count -lt 3 -and $free.Count) { $pick = $free[$rng.Next($free.Count)]; $offer += $pick; $free = @($free | Where-Object { $_ -ne $pick }) }
    $offer
}

function Install-Perk([string]$Name) {
    if (-not $script:ModulePerks.Contains($Name) -or (Test-Perk $Name)) { return }
    $script:P.Modules = @($script:P.Modules) + $Name
    Add-TranscriptLine "Install-Module $Name   # $($script:ModulePerks[$Name])"
    Start-Sfx 'weapon'
}

# The price of a power with what is installed.
function Get-AbilityCost([int]$Id) {
    $cost = [double]$script:Abilities[$Id].Cost
    if ($Id -eq 3 -and (Test-Perk 'PSScriptAnalyzer')) { return 0 }
    if (Test-Perk 'PSReadLine') { $cost *= 0.75 }
    [int][Math]::Round($cost)
}
