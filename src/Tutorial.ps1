# POLF 3D - Copyright (c) 2026 oNdsen. Licensed under the MIT License, see LICENSE.

# Tutorial.ps1 - the onboarding (N on the title screen, or -Tutorial): a floor of its own, maps/tutorial.map, where
# every room explains one thing and lets the player try it - moving and doors, shooting the unaware, sneaking and
# blades, keys and secret walls, the powers, the console with a terminal, a file and a code, camera, sentry gun and
# taser, darkness, flashlight, mines and bugs, loot - and the lift, which goes back to the title screen.
#
# The explaining is done by hints, and those are a feature of the map format that any map may use:
#     @hint <x> <y> <width> <height> <text>
# The first time the player stands inside that rectangle the text appears at the top of the view and stays for a
# while. Which hints have been shown is a bit mask in the floor's statistics, so Undo does not repeat them.
#
# In the onboarding the difficulty is Intern whatever was chosen, privilege comes back five times as fast (the
# powers are there to be tried) and nothing is rated, saved or recorded as an achievement.

$script:TutorialMode = $false
$script:LevelHints = @()
$script:HintText = ''; $script:HintTics = 0.0

function Get-TutorialMap { Join-Path (Split-Path $script:MapFiles[0]) 'tutorial.map' }

function Start-Tutorial {
    if ($script:Net) { Show-Message 'The onboarding is a solo affair'; return $false }
    if (-not (Test-Path -LiteralPath (Get-TutorialMap))) { Show-Message 'maps/tutorial.map is missing'; return $false }
    $script:TutorialMode = $true; $script:TutorialKeepDifficulty = $script:Difficulty; $script:Difficulty = 0
    $script:BonusMap = $null; $script:LevelIndex = 0
    Start-Level $false $false
    $script:P.Privilege = 100.0
    $true
}

function Stop-Tutorial {
    if (-not $script:TutorialMode) { return }
    $script:TutorialMode = $false
    if ($null -ne $script:TutorialKeepDifficulty) { $script:Difficulty = $script:TutorialKeepDifficulty; $script:TutorialKeepDifficulty = $null }
    $script:HintText = ''
}

# Once a frame: has the player walked into a hint that has not been shown yet?
function Update-Hints([double]$Tics) {
    if ($script:HintTics -gt 0) { $script:HintTics -= $Tics; if ($script:HintTics -le 0) { $script:HintText = '' } }
    if (-not $script:LevelHints.Count -or $script:Predicting) { return }
    $st = $script:Stats; $shown = [long]$st.HintsShown
    $px = [int][Math]::Floor($script:P.X); $py = [int][Math]::Floor($script:P.Y)
    for ($i = 0; $i -lt $script:LevelHints.Count -and $i -lt 62; $i++) {
        $h = $script:LevelHints[$i]
        if (($shown -band ([long]1 -shl $i)) -or $px -lt $h.X -or $py -lt $h.Y -or $px -ge $h.X + $h.W -or $py -ge $h.Y + $h.H) { continue }
        $st.HintsShown = $shown -bor ([long]1 -shl $i)
        $script:HintText = $h.Text; $script:HintTics = 70.0 * [Math]::Max(12, $h.Text.Length / 9.0)      # time to read it
        Start-Sfx 'pickup'
        return
    }
}

# The hint as lines that fit the view.
function Get-HintLines([int]$Width = 74) {
    if (-not $script:HintText) { return @() }
    $lines = [System.Collections.Generic.List[string]]::new(); $line = ''
    foreach ($word in $script:HintText.Split(' ')) {
        if ($line.Length + $word.Length + 1 -gt $Width -and $line) { $lines.Add($line); $line = $word } else { $line = if ($line) { "$line $word" } else { $word } }
    }
    if ($line) { $lines.Add($line) }
    $lines
}

function Show-Hint {
    $lines = @(Get-HintLines)
    if (-not $lines.Count) { return }
    Write-HudBar 'D0061020' 30 17 232 ($lines.Count * 6.2 + 5)
    Write-HudBar 'FF2C54C4' 30 17 1.2 ($lines.Count * 6.2 + 5)
    $y = 19.5
    foreach ($l in $lines) { Write-HudLine $l 'Small' 'FFFFFF' 35 $y; $y += 6.2 }
}
