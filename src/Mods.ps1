# POLF 3D - Copyright (c) 2026 oNdsen. Licensed under the MIT License, see LICENSE.

# Mods.ps1 - mods are data: every mods/*.psd1 is read with Import-PowerShellDataFile (which cannot run
# code) and merged into the game's tables before anything is painted or synthesised. Since all art and
# sound is generated from those tables, a new enemy needs no picture - only a palette.
#
#   @{
#       Name         = 'Purple interns'
#       Enemies      = @{                       # change a field of an existing enemy, or define a new one:
#           guard  = @{ Points = 150 }
#           intern = @{ BasedOn = 'guard'; HP = 10, 12, 15, 15; Points = 50; Code = 'i'      # 'i>' in a map
#                       Replaces = 'guard'; Share = 0.3 }                                      # ... or takes over 30 % of the guards
#       }
#       Palettes     = @{ intern = @{ Uniform = '7A3AA8'; UniformDark = '5A2A80'; HatStyle = 'none' } }
#       Voices       = @{ intern = 'It works on my machine!', 'Is this production?'; 'intern.die' = 'I will put it in a ticket.' }
#       Weapons      = @{ pistol = @{ Name = 'Service pistol' } }                              # Name and Cost
#       Difficulties = @( @{ DamageScale = 0.1 } )                                             # by position: Intern first
#       Music        = @{ rock = @{ Tempo = 168 } }                                            # Tempo, Root, Scale, Chords
#   }
#
# New enemies are soldiers: BasedOn must be guard, officer, elite, mutant, sniper or pilot.
# Demos remember which mods were loaded, and -VerifyDemo insists on the same ones.

$script:Mods = @()                    # names of the mods that are in
$script:ModKinds = @()                # enemy kinds that mods have added (they need sprites)
$script:ModReplace = @{}              # kind -> @{ By = new kind; Share = 0..1 }

function Import-Mods([string]$Dir) {
    if (-not (Test-Path -LiteralPath $Dir)) { return }
    foreach ($file in (Get-ChildItem -LiteralPath $Dir -Filter '*.psd1' -File | Sort-Object Name)) {
        try {
            $mod = Import-PowerShellDataFile -LiteralPath $file.FullName
            Import-Mod $mod
            $script:Mods += $(if ($mod.Name) { [string]$mod.Name } else { $file.BaseName })
        }
        catch { Write-Warning "Mod '$($file.Name)' was not loaded: $($_.Exception.Message)" }
    }
}

# The keys of a section of a mod - none at all if the mod has no such section.
function Get-ModKeys($Section) { if ($Section -is [hashtable]) { @($Section.Keys) } else { @() } }

function Import-Mod([hashtable]$Mod) {
    $soldiers = 'guard', 'officer', 'elite', 'mutant', 'sniper', 'pilot'
    foreach ($kind in (Get-ModKeys $Mod.Enemies)) {
        $spec = $Mod.Enemies[$kind]
        if (-not $script:EnemyDefs.ContainsKey($kind)) {
            if ($spec.BasedOn -notin $soldiers) { throw "enemy '$kind': BasedOn must be one of $($soldiers -join ', ')" }
            if ($kind -notmatch '^[a-z][a-z0-9]*$') { throw "enemy '$kind': names are lower case letters and digits" }
            $script:EnemyDefs[$kind] = $script:EnemyDefs[$spec.BasedOn].Clone()
            $script:Palettes[$kind] = $script:Palettes[$spec.BasedOn].Clone()
            $script:ModKinds += $kind
        }
        foreach ($field in @($spec.Keys)) {
            switch ($field) {
                'BasedOn'  { }
                'Code'     { $c = [char]([string]$spec.Code)[0]; if ($script:EnemyCodes.ContainsKey($c)) { throw "enemy '$kind': the map code '$c' is taken" }; $script:EnemyCodes[$c] = $kind }
                'Replaces' { if (-not $script:EnemyDefs.ContainsKey([string]$spec.Replaces)) { throw "enemy '$kind': there is no '$($spec.Replaces)' to replace" }
                             $script:ModReplace[[string]$spec.Replaces] = @{ By = $kind; Share = $(if ($null -ne $spec.Share) { [double]$spec.Share } else { 0.25 }) } }
                'Share'    { }
                'HP'       { $hp = @($spec.HP | ForEach-Object { [int]$_ }); if ($hp.Count -ne 4) { throw "enemy '$kind': HP needs four numbers, one per difficulty" }; $script:EnemyDefs[$kind].HP = $hp }
                default    { if (-not $script:EnemyDefs[$kind].ContainsKey($field)) { throw "enemy '$kind': there is no field '$field'" }; $script:EnemyDefs[$kind][$field] = $spec[$field] }
            }
        }
    }
    foreach ($kind in (Get-ModKeys $Mod.Palettes)) {
        if (-not $script:Palettes.ContainsKey($kind)) { throw "palette '$kind': no such soldier" }
        foreach ($field in @($Mod.Palettes[$kind].Keys)) { $script:Palettes[$kind][$field] = [string]$Mod.Palettes[$kind][$field] }
    }
    foreach ($kind in (Get-ModKeys $Mod.Voices)) { foreach ($line in @($Mod.Voices[$kind])) { $script:VoiceLines += , @($kind, [string]$line, 0, 2, 'm', $(if ($kind -like '*.die') { 5 } else { 6 })) } }
    foreach ($key in (Get-ModKeys $Mod.Weapons)) {
        $weapon = $script:Weapons | Where-Object Key -eq $key
        if (-not $weapon) { throw "weapon '$key': no such weapon (keys: $(($script:Weapons.Key) -join ', '))" }
        foreach ($field in @($Mod.Weapons[$key].Keys)) { if ($field -notin 'Name', 'Cost') { throw "weapon '$key': only Name and Cost can be changed" }; $weapon[$field] = $Mod.Weapons[$key][$field] }
    }
    $i = 0
    foreach ($level in @($Mod.Difficulties)) { if ($level -and $i -lt 4) { foreach ($field in @($level.Keys)) { if ($script:Difficulties[$i].ContainsKey($field)) { $script:Difficulties[$i][$field] = $level[$field] } } }; $i++ }
    foreach ($style in (Get-ModKeys $Mod.Music)) {
        if (-not $script:MusicStyles.ContainsKey($style)) { throw "music '$style': no such style (styles: $($script:MusicStyles.Keys -join ', '))" }
        foreach ($field in @($Mod.Music[$style].Keys)) { $script:MusicStyles[$style][$field] = $Mod.Music[$style][$field] }
        $script:MUSIC_VERSION = "$($script:MUSIC_VERSION)m"          # modded tracks get their own cache files
    }
}

# Map loading: some of the $Kind at this spot may have been taken over by a mod's newcomer.
function Get-ModdedKind([string]$Kind, [int]$X, [int]$Y) {
    $swap = $script:ModReplace[$Kind]
    if ($swap -and (($X * 37 + $Y * 101) % 100) -lt 100 * $swap.Share) { $swap.By } else { $Kind }
}
