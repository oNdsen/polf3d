# POLF 3D - Copyright (c) 2026 oNdsen. Licensed under the MIT License, see LICENSE.

# Achievements.ps1 - every floor is a test suite. When the lift switch is thrown, the run is put
# through ten tests and the result scrolls past the way Pester prints it. What has been passed once
# stays passed (saves/achievements.json); the title screen counts them.

$script:Run = @{}

# What a run is measured by. Reset when a floor starts, counted by hooks all over the game.
function Reset-RunStats { $script:Run = @{ Alerts = 0; Shots = 0; MinHealth = 100; Powers = 0; Console = 0; Deaths = 0 } }

$script:Tests = @(
    @{ Id = 'done';     Name = 'reaches the lift';                         Test = { $true } }
    @{ Id = 'par';      Name = 'beats the par time';                       Test = { $script:Stats.Tics / $script:TICRATE -le $script:ParSeconds } }
    @{ Id = 'kills';    Name = 'leaves nobody standing';                   Test = { $script:Stats.Kills -ge $script:Stats.KillTotal } }
    @{ Id = 'secrets';  Name = 'finds every secret';                       Test = { $script:Stats.Secrets -ge $script:Stats.SecretTotal } }
    @{ Id = 'treasure'; Name = 'collects all the treasure';                Test = { $script:Stats.Treasures -ge $script:Stats.TreasureTotal } }
    @{ Id = 'quiet';    Name = 'is noticed by nobody';                     Test = { $script:Run.Alerts -eq 0 } }
    @{ Id = 'pacifist'; Name = 'fires no gun (blades are fine)';           Test = { $script:Run.Shots -eq 0 } }
    @{ Id = 'healthy';  Name = 'never drops below 50 health';              Test = { $script:Run.MinHealth -ge 50 } }
    @{ Id = 'manual';   Name = 'uses no power and no console command';     Test = { $script:Run.Powers -eq 0 -and $script:Run.Console -eq 0 } }
    @{ Id = 'honest';   Name = 'does not cheat';                           Test = { -not $script:P.Cheated } }
)

function Get-AchievementPath { Join-Path $script:SaveDir 'achievements.json' }

function Get-Achievements {
    $path = Get-AchievementPath
    if (Test-Path -LiteralPath $path) { try { return (Get-Content -LiteralPath $path -Raw | ConvertFrom-Json -AsHashtable) } catch { } }
    @{}
}

# "12 of 100" for the title screen: floors of the campaign times tests.
function Get-AchievementCount {
    $all = Get-Achievements; $passed = 0
    foreach ($floor in $all.Keys) { $passed += @($all[$floor]).Count }
    "$passed of $($script:MapFiles.Count * $script:Tests.Count)"
}

# Runs the suite on the floor that has just been completed. Returns @{ Lines = @(text, colour), ...; Passed; Failed }.
function Invoke-FloorTests {
    $floor = if ($script:DungeonSeed) { "Dungeon #$($script:DungeonSeed)" } elseif ($script:BonusMap) { "Bonus: $($script:LevelName)" } else { "Floor $($script:LevelIndex + 1): $($script:LevelName)" }
    $key = if ($script:DungeonSeed) { $null } elseif ($script:BonusMap) { 'bonus' } else { "floor$($script:LevelIndex + 1)" }
    $all = Get-Achievements
    $known = @(if ($key) { $all[$key] })
    $lines = [System.Collections.Generic.List[object]]::new()
    $lines.Add(@("Describing $floor", '60FF80'))
    $passed = 0; $failed = 0; $new = @()
    foreach ($t in $script:Tests) {
        $ok = [bool](& $t.Test)
        $ms = 3 + ($t.Id.Length * 7 + [int]$script:Stats.Tics) % 40
        if ($ok) {
            $passed++
            $fresh = $key -and $t.Id -notin $known
            if ($fresh) { $new += $t.Id }
            $lines.Add(@("  [+] $($t.Name) ${ms}ms$(if ($fresh) { '   NEW' })", $(if ($fresh) { 'F0D040' } else { '60FF80' })))
        }
        else { $failed++; $lines.Add(@("  [-] $($t.Name) ${ms}ms", 'F14C4C')) }
    }
    $lines.Add(@("Tests completed in $([Math]::Round($script:Stats.Tics / $script:TICRATE, 1))s", 'FFFFFF'))
    $lines.Add(@("Tests Passed: $passed, Failed: $failed, Skipped: 0", $(if ($failed) { 'F14C4C' } else { '60FF80' })))
    if ($key -and $new.Count -and -not $script:Net) {
        $all[$key] = @($known + $new | Where-Object { $_ } | Select-Object -Unique)
        try { $null = New-Item -ItemType Directory -Path $script:SaveDir -Force; $all | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath (Get-AchievementPath) -Encoding utf8 } catch { }
    }
    @{ Lines = $lines.ToArray(); Passed = $passed; Failed = $failed; New = $new }
}
