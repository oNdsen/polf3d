# POLF 3D - Copyright (c) 2026 oNdsen. Licensed under the MIT License, see LICENSE.

# Defs.ps1 - constants, data classes and the data-driven tables (enemies, states, weapons, items).
# Counterpart of the original's central header: everything else builds on these definitions.

# ---------------------------------------------------------------------------------------------
# Units: positions in tiles (double), time in "tics" (1/70 s), the classic 70 Hz game clock;
# speeds are tiles per tic.
# ---------------------------------------------------------------------------------------------
$script:Copyright    = '(c) 2026 oNdsen - MIT License'
$script:TICRATE      = 70.0
$script:MAXTICS      = 10.0          # longest simulated step per frame
$script:PLAYER_RADIUS = 0.34
$script:MIN_ACTOR_DIST = 0.85        # enemies never get closer than this (per axis)
$script:DOOR_OPEN_TICS = 64.0        # time to slide fully open
$script:DOOR_STAY_TICS = 300.0       # open doors close again after this
$script:PUSHWALL_TICS_PER_TILE = 128.0
$script:EXTRA_LIFE_POINTS = 40000
$script:START_AMMO   = 8
$script:MAX_AMMO     = 99

# 8 directions, counter-clockwise starting east (y grows to the south)
$script:DIR_NONE = 8
$script:DirDX = [int[]](1, 1, 0, -1, -1, -1, 0, 1, 0)
$script:DirDY = [int[]](0, -1, -1, -1, 0, 1, 1, 1, 0)

$script:Rng = [System.Random]::new()
function Get-Rnd { $script:Rng.Next(256) }     # 0..255, the classic random byte

# ---------------------------------------------------------------------------------------------
# Data classes (pure data holders; all behaviour lives in functions)
# ---------------------------------------------------------------------------------------------
class Actor {
    [string]$Kind
    [hashtable]$Def
    [string]$State
    [double]$Tics
    [double]$X
    [double]$Y
    [int]$TX                  # tile the actor occupies / walks towards (reserved in ActorAt)
    [int]$TY
    [int]$Dir = 8
    [int]$PathDir = 8         # patrol route direction, survives being blocked
    [double]$Dist             # remaining distance to the centre of (TX,TY)
    [int]$WaitDoor = -1       # >= 0: standing in front of this door until it is open
    [double]$Speed
    [int]$HP
    [int]$Area
    [bool]$Active
    [bool]$Shootable
    [bool]$Visible
    [bool]$AttackMode
    [bool]$FirstAttack
    [bool]$Ambush
    [bool]$Corpse
    [double]$React            # reaction countdown after noticing the player
    [int]$ScreenX             # filled by the renderer, used for aiming
    [double]$Depth
    [double]$VX               # projectiles only: velocity in tiles per tic
    [double]$VY
}

class Door {
    [int]$X
    [int]$Y
    [bool]$Vertical           # true: door plane runs north-south (blocks east-west travel)
    [int]$Lock                # 0 none, 1 gold, 2 silver, 3 lift
    [string]$Action = 'closed'   # closed | opening | open | closing
    [double]$Open             # 0 = closed .. 1 = fully open
    [double]$Timer
    [int]$Area1
    [int]$Area2
    [int]$TexId
}

class Static {
    [int]$X
    [int]$Y
    [int[]]$Sprite
    [bool]$Block
    [string]$Item             # $null for decoration
    [bool]$Removed
}

# ---------------------------------------------------------------------------------------------
# Wall textures: id -> name. Map cell codes -> id.
# ---------------------------------------------------------------------------------------------
$script:WallNames = @(
    $null, 'stone', 'stone_banner', 'stone_pic', 'blue', 'blue_cell', 'wood', 'wood_pic', 'wood_shield',
    'brick', 'brick_banner', 'steel', 'switch_off', 'switch_on', 'jamb',
    'door', 'door_gold', 'door_silver', 'door_lift',
    'moss', 'moss_vines', 'tech', 'tech_lights'          # appended: ids of the older textures stay stable
)
$script:TEX_SWITCH_OFF = 12
$script:TEX_SWITCH_ON  = 13
$script:TEX_JAMB       = 14
$script:TEX_DOOR       = 15      # + lock (0..3)

$script:WallCodes = [hashtable]::new([StringComparer]::Ordinal)      # map codes are case sensitive
foreach ($wc in @('SS', 1), @('Sb', 2), @('Sp', 3), @('BB', 4), @('Bc', 5), @('WW', 6), @('Wp', 7), @('Ws', 8),
                 @('RR', 9), @('Rb', 10), @('MM', 11), @('MX', 12), @('GG', 19), @('Gv', 20), @('TT', 21), @('Tl', 22)) { $script:WallCodes[$wc[0]] = $wc[1] }
# secret push-walls: '?' + texture letter (lower case = decorated variant)
$script:PushCodes = @{
    [char]'S' = 1; [char]'s' = 2; [char]'B' = 4; [char]'b' = 5
    [char]'W' = 6; [char]'w' = 7; [char]'R' = 9; [char]'r' = 10; [char]'M' = 11
    [char]'G' = 19; [char]'g' = 20; [char]'T' = 21; [char]'t' = 22
}
$script:DoorCodes = @{ [char]'D' = 0; [char]'G' = 1; [char]'S' = 2; [char]'L' = 3 }

# tile values in the Tiles array
$script:TILE_DOOR_BASE = 100     # 100 + door index
$script:TILE_PUSHWALL  = 200     # the (single) push-wall that is currently moving

# ---------------------------------------------------------------------------------------------
# Items ("+x" cells) and decoration ("*x" cells)
# ---------------------------------------------------------------------------------------------
$script:ItemCodes = @{
    [char]'d' = 'dogfood'; [char]'f' = 'food'; [char]'h' = 'medkit'
    [char]'a' = 'clip'; [char]'m' = 'mgun'; [char]'c' = 'chaingun'
    [char]'g' = 'key_gold'; [char]'s' = 'key_silver'
    [char]'1' = 'coins'; [char]'2' = 'goblet'; [char]'3' = 'chest'; [char]'4' = 'crown'
    [char]'u' = 'oneup'
    [char]'p' = 'pipeline'; [char]'r' = 'forcegun'; [char]'z' = 'charge'; [char]'q' = 'sudo'
}
$script:TreasureItems = @('coins', 'goblet', 'chest', 'crown', 'oneup')

# code -> @(sprite name, blocking)
$script:DecoCodes = @{
    [char]'l' = @('lamp_ceiling', $false); [char]'h' = @('chandelier', $false)
    [char]'L' = @('lamp_floor', $true);    [char]'t' = @('table', $true)
    [char]'b' = @('barrel', $true);        [char]'p' = @('plant', $true)
    [char]'a' = @('armor', $true);         [char]'c' = @('column', $true)
    [char]'f' = @('flag', $true);          [char]'x' = @('crates', $true)
    [char]'v' = @('vat', $true);           [char]'s' = @('bones', $false)
    [char]'u' = @('puddle', $false);       [char]'k' = @('guard.dead', $false)
    [char]'B' = @('bed', $true);           [char]'m' = @('console', $true)
    [char]'g' = @('stalagmite', $true)
}

# ---------------------------------------------------------------------------------------------
# Enemies. Speeds in tiles per tic. Shoot = list of @(sprite, tics, fireAtEnd)
# ---------------------------------------------------------------------------------------------
$script:EnemyCodes = @{
    [char]'g' = 'guard'; [char]'d' = 'dog'; [char]'e' = 'elite'
    [char]'o' = 'officer'; [char]'m' = 'mutant'; [char]'b' = 'boss'; [char]'u' = 'uber'
}

$script:EnemyDefs = @{
    guard = @{
        HP = @(25, 25, 25, 25); Points = 100; Patrol = 0.0078; Chase = 0.0234
        ReactBase = 1; ReactDiv = 4; Doors = $true; Pain = $true; Rotates = $true
        Accuracy = 1.0; Drop = 'clip_small'; AlertSnd = 'alert_guard'; ShotSnd = 'shot_enemy'; DieSnd = 'die_a'
        Shoot = @(, @('aim', 20, $false)) + @(, @('aim', 20, $true)) + @(, @('fire', 20, $false))
        DieTics = 15
    }
    officer = @{
        HP = @(50, 50, 50, 50); Points = 400; Patrol = 0.0078; Chase = 0.039
        ReactBase = 2; ReactDiv = 0; Doors = $true; Pain = $true; Rotates = $true
        Accuracy = 1.0; Drop = 'clip_small'; AlertSnd = 'alert_officer'; ShotSnd = 'shot_enemy'; DieSnd = 'die_b'
        Shoot = @(, @('aim', 6, $false)) + @(, @('aim', 20, $true)) + @(, @('fire', 10, $false))
        DieTics = 11
    }
    elite = @{
        HP = @(100, 100, 100, 100); Points = 500; Patrol = 0.0078; Chase = 0.0312
        ReactBase = 1; ReactDiv = 6; Doors = $true; Pain = $true; Rotates = $true
        Accuracy = 1.5; Drop = 'mgun_or_clip'; AlertSnd = 'alert_elite'; ShotSnd = 'shot_elite'; DieSnd = 'die_b'
        Shoot = @(, @('aim', 20, $false)) + @(, @('aim', 20, $true)) + @(, @('fire', 10, $false)) +
                @(, @('aim', 10, $true)) + @(, @('fire', 10, $false)) + @(, @('aim', 10, $true)) +
                @(, @('fire', 10, $false)) + @(, @('aim', 10, $true)) + @(, @('fire', 10, $false))
        DieTics = 15
    }
    mutant = @{
        HP = @(45, 55, 55, 65); Points = 700; Patrol = 0.0078; Chase = 0.0234
        ReactBase = 1; ReactDiv = 6; Doors = $true; Pain = $true; Rotates = $true
        Accuracy = 1.0; Drop = 'clip_small'; AlertSnd = $null; ShotSnd = 'shot_enemy'; DieSnd = 'die_c'
        Shoot = @(, @('aim', 6, $true)) + @(, @('fire', 20, $false)) + @(, @('aim', 10, $true)) + @(, @('fire', 20, $false))
        DieTics = 7
    }
    dog = @{
        HP = @(1, 1, 1, 1); Points = 200; Patrol = 0.0229; Chase = 0.0458
        ReactBase = 1; ReactDiv = 8; Doors = $false; Pain = $false; Rotates = $true
        Accuracy = 1.0; Drop = $null; AlertSnd = 'alert_dog'; ShotSnd = 'bite'; DieSnd = 'die_dog'
        Shoot = @()      # dogs bite instead (own state chain)
        DieTics = 15
    }
    boss = @{
        HP = @(850, 950, 1050, 1200); Points = 5000; Patrol = 0.0078; Chase = 0.0234
        ReactBase = 1; ReactDiv = 0; Doors = $true; Pain = $false; Rotates = $false
        Accuracy = 1.5; Drop = 'key_gold'; AlertSnd = 'alert_boss'; ShotSnd = 'shot_boss'; DieSnd = 'die_boss'
        Shoot = @(, @('aim', 30, $false)) + @(, @('fire', 10, $true)) + @(, @('aim', 10, $true)) +
                @(, @('fire', 10, $true)) + @(, @('aim', 10, $true)) + @(, @('fire', 10, $true)) +
                @(, @('aim', 10, $true)) + @(, @('aim', 10, $false))
        DieTics = 15
    }
    # The super boss, phase 1: a walking war machine - bursts of gunfire, then a salvo of rockets.
    uber = @{
        HP = @(1100, 1300, 1500, 1800); Points = 10000; Patrol = 0.0078; Chase = 0.0195
        ReactBase = 1; ReactDiv = 0; Doors = $false; Pain = $false; Rotates = $false
        Accuracy = 1.5; Drop = $null; AlertSnd = 'alert_uber'; ShotSnd = 'shot_boss'; DieSnd = 'die_uber'
        Shoot = @(, @('aim', 30, $false)) + @(, @('fire', 8, $true)) + @(, @('aim', 8, $true)) + @(, @('fire', 8, $true)) +
                @(, @('aim', 8, $true)) + @(, @('aim', 25, $false)) + @(, @('rocket', 12, 'Rocket')) + @(, @('aim', 12, $false)) +
                @(, @('rocket', 12, 'Rocket')) + @(, @('aim', 12, $false)) + @(, @('rocket', 12, 'Rocket')) + @(, @('aim', 20, $false))
        DieTics = 20; DieAction = 'SpawnPilot'
    }
    # ... phase 2: the pilot bails out - little armour, but fast and trigger-happy.
    pilot = @{
        HP = @(250, 300, 400, 500); Points = 5000; Patrol = 0.0078; Chase = 0.05
        ReactBase = 1; ReactDiv = 0; Doors = $true; Pain = $false; Rotates = $true
        Accuracy = 1.5; Drop = 'crown'; AlertSnd = 'alert_officer'; ShotSnd = 'shot_elite'; DieSnd = 'die_b'
        Shoot = @(, @('aim', 8, $false)) + @(, @('aim', 6, $true)) + @(, @('fire', 6, $false)) + @(, @('aim', 6, $true)) +
                @(, @('fire', 6, $false)) + @(, @('aim', 6, $true)) + @(, @('fire', 6, $false))
        DieTics = 12
    }
}

# things that live in the actor list without being enemies
$script:MiscDefs = @{
    rocket = @{ Speed = 0.12; Rotates = $false; Doors = $false; Pain = $false }
}

# ---------------------------------------------------------------------------------------------
# State machine. A state = { Sprite, Rot, Tics, Think, Action, Next }
#   Think  : called every frame while the state is active
#   Action : called once when the state's tics run out, before switching to Next
#   Tics 0 : state never runs out on its own
# The chains are generated per enemy from the definitions above.
# ---------------------------------------------------------------------------------------------
$script:States = @{}

function Add-State {
    param([string]$Name, [string]$Sprite, [bool]$Rot, [double]$Tics, [string]$Think, [string]$Action, [string]$Next)
    $script:States[$Name] = @{ Name = $Name; Sprite = $Sprite; Rot = $Rot; Tics = $Tics; Think = $Think; Action = $Action; Next = $Next }
}

function Initialize-States {
    $script:States = @{}
    foreach ($kind in $script:EnemyDefs.Keys) {
        $def = $script:EnemyDefs[$kind]
        $rot = [bool]$def.Rotates
        $chaseThink = if ($kind -eq 'dog') { 'DogChase' } else { 'Chase' }

        Add-State "$kind.stand" "$kind.s" $rot 0 'Stand' $null "$kind.stand"

        # walking: four frames, the 1st and 3rd followed by a short think-less hold
        $frames = @(
            @('1', 'w1', 20, 10, '1s'), @('1s', 'w1', 5, 3, '2'), @('2', 'w2', 15, 8, '3'),
            @('3', 'w3', 20, 10, '3s'), @('3s', 'w3', 5, 3, '4'), @('4', 'w4', 15, 8, '1')
        )
        foreach ($f in $frames) {
            $hold = $f[0].EndsWith('s')
            Add-State "$kind.path$($f[0])"  "$kind.$($f[1])" $rot $f[2] $(if ($hold) { $null } else { 'Path' }) $null "$kind.path$($f[4])"
            Add-State "$kind.chase$($f[0])" "$kind.$($f[1])" $rot $f[3] $(if ($hold) { $null } else { $chaseThink }) $null "$kind.chase$($f[4])"
        }

        if ($def.Pain) { Add-State "$kind.pain" "$kind.pain" $false 10 $null $null "$kind.chase1" }

        $i = 1
        foreach ($s in $def.Shoot) {
            $next = if ($i -lt $def.Shoot.Count) { "$kind.shoot$($i + 1)" } else { "$kind.chase1" }
            $act = if ($s[2] -is [string]) { $s[2] } elseif ($s[2]) { 'Shoot' } else { $null }
            Add-State "$kind.shoot$i" "$kind.$($s[0])" $false $s[1] $null $act $next
            $i++
        }

        $t = $def.DieTics
        Add-State "$kind.die1" "$kind.die1" $false $t $null 'DeathScream' "$kind.die2"
        Add-State "$kind.die2" "$kind.die2" $false $t $null $null "$kind.die3"
        Add-State "$kind.die3" "$kind.die3" $false $t $null $def.DieAction "$kind.dead"
        Add-State "$kind.dead" "$kind.dead" $false 0 $null $null "$kind.dead"
    }

    # the dog's leap
    Add-State 'dog.jump1' 'dog.jump1' $false 10 $null $null   'dog.jump2'
    Add-State 'dog.jump2' 'dog.jump2' $false 10 $null 'Bite'  'dog.jump3'
    Add-State 'dog.jump3' 'dog.jump3' $false 10 $null $null   'dog.jump4'
    Add-State 'dog.jump4' 'dog.jump1' $false 10 $null $null   'dog.jump5'
    Add-State 'dog.jump5' 'dog.w1'    $true  10 $null $null   'dog.chase1'      # dog.w1 has four views

    # rockets: fly until something is hit, then three frames of explosion, then gone
    Add-State 'rocket.fly'   'rocket'       $false 0 'Projectile' $null 'rocket.fly'
    Add-State 'rocket.boom1' 'rocket.boom1' $false 6 $null $null 'rocket.boom2'
    Add-State 'rocket.boom2' 'rocket.boom2' $false 6 $null $null 'rocket.boom3'
    Add-State 'rocket.boom3' 'rocket.boom3' $false 6 $null 'Remove' 'rocket.boom3'
}

# ---------------------------------------------------------------------------------------------
# Weapons. Each attack frame = @(tics, action, picture)
#   none | knife | fire | repeat (loop back while trigger held) | firerepeat | beam | blast | end
# Cost = bullets per shot. The two special weapons are POLF3D's own invention:
#   Pipeline - "|" passes everything along: the beam pierces EVERY enemy in the line of fire
#   Force    - "Remove-Item -Recurse -Force": wipes the whole field of view, fed by rare charges
# ---------------------------------------------------------------------------------------------
$script:Weapons = @(
    @{ Name = 'Knife';           Short = 'KNIFE';   Key = 'knife';    Snd = 'knife';       Cost = 0; Frames = @(@(6, 'none', 1), @(6, 'knife', 2), @(6, 'none', 3), @(6, 'end', 4)) }
    @{ Name = 'Pistol';          Short = 'PISTOL';  Key = 'pistol';   Snd = 'shot_pistol'; Cost = 1; Frames = @(@(6, 'none', 1), @(6, 'fire', 2), @(6, 'none', 3), @(6, 'end', 4)) }
    @{ Name = 'Machine gun';     Short = 'MG';      Key = 'mgun';     Snd = 'shot_mgun';   Cost = 1; Frames = @(@(6, 'none', 1), @(6, 'fire', 2), @(6, 'repeat', 3), @(6, 'end', 4)) }
    @{ Name = 'Chain gun';       Short = 'CHAIN';   Key = 'chaingun'; Snd = 'shot_chain';  Cost = 1; Frames = @(@(6, 'none', 1), @(6, 'fire', 2), @(6, 'firerepeat', 3), @(6, 'end', 4)) }
    @{ Name = 'Pipeline Cannon'; Short = 'PIPE |';  Key = 'pipeline'; Snd = 'shot_pipe';   Cost = 4; Frames = @(@(8, 'none', 1), @(8, 'beam', 2), @(12, 'none', 3), @(8, 'end', 4)) }
    @{ Name = 'Force Blaster';   Short = '-FORCE';  Key = 'forcegun'; Snd = 'shot_force';  Cost = 0; Frames = @(@(14, 'none', 1), @(10, 'blast', 2), @(16, 'none', 3), @(12, 'end', 4)) }
)
$script:WEAPON_PIPELINE = 4
$script:WEAPON_FORCE = 5
$script:SUDO_TICS = 1400.0        # the "sudo" power-up lasts 20 seconds

$script:Difficulties = @(
    @{ Name = 'Intern (-WhatIf)';          DamageScale = 0.25 }
    @{ Name = 'Sysadmin';                  DamageScale = 0.6 }
    @{ Name = 'Senior Engineer';           DamageScale = 1.0 }
    @{ Name = 'root (-Force -Confirm:$false)'; DamageScale = 1.3 }
)
