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
# how far the player's footsteps carry, in tiles: sneaking is silent
$script:NOISE_WALK   = 2.5
$script:NOISE_RUN    = 6.0
$script:NOISE_DOOR   = 5.0
$script:START_AMMO   = 8
$script:MAX_AMMO     = 99

# 8 directions, counter-clockwise starting east (y grows to the south)
$script:DIR_NONE = 8
$script:DirDX = [int[]](1, 1, 0, -1, -1, -1, 0, 1, 0)
$script:DirDY = [int[]](0, -1, -1, -1, 0, 1, 1, 1, 0)

$script:Rng = [System.Random]::new()            # game logic - re-seeded at every floor start so demos can be replayed
$script:FxRng = [System.Random]::new()          # cosmetics only (camera shake), never touches the simulation
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
    [double]$AlertTics        # how long the "!" above the head is still shown
    [int]$ScreenX             # filled by the renderer, used for aiming
    [double]$Depth
    [double]$VX               # projectiles only: velocity in tiles per tic
    [double]$VY
    [int]$NetId               # network games: the same actor carries the same id on both machines (0 = local only)
    [double]$NX               # ... where the host says it is (the client glides there)
    [double]$NY
    [int]$PeerSlot            # ... a player's ghost: whose; a projectile: which guest fired it (0 = none)
    [double]$Stun             # Suspend-Enemy (the console): frozen for this many tics
    [bool]$Hacked             # a turret that answers to the player (Set-Turret -Owner Me)
    [double]$Cool             # cameras and turrets: countdown to the next sweep, shot or loss of interest
}

class Door {
    [int]$X
    [int]$Y
    [bool]$Vertical           # true: door plane runs north-south (blocks east-west travel)
    [int]$Lock                # 0 none, 1 gold, 2 silver, 3 lift, 4 remote (opened by a lever)
    [int]$Channel             # remote doors: the lever number that opens them
    [bool]$Unlocked           # remote doors: the lever has been pulled
    [string]$Action = 'closed'   # closed | opening | open | closing
    [double]$Open             # 0 = closed .. 1 = fully open
    [double]$Timer
    [int]$Area1
    [int]$Area2
    [int]$TexId
    [double]$Jam              # Lock-Door (the console): nobody opens it for this many tics
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
    'moss', 'moss_vines', 'tech', 'tech_lights',         # appended: ids of the older textures stay stable
    'lever_off', 'lever_on', 'door_remote',
    'stone_cracked', 'blue_cracked', 'wood_cracked', 'brick_cracked', 'steel_cracked', 'moss_cracked', 'tech_cracked',
    'stone_window', 'blue_window', 'wood_window', 'brick_window', 'steel_window', 'moss_window', 'tech_window',
    'secret_switch_off', 'secret_switch_on',
    # PowerShell everywhere: consoles, posters, error screens, neon prompts, graffiti
    'stone_console', 'blue_console', 'wood_console', 'brick_console', 'steel_console', 'moss_console', 'tech_console',
    'stone_poster', 'wood_poster', 'brick_poster', 'steel_error', 'tech_error', 'tech_neon', 'steel_neon', 'brick_graffiti', 'stone_graffiti'
)
$script:TEX_SECRET_OFF = 40       # the hidden lift switch that leads to a bonus floor
$script:TEX_SECRET_ON  = 41
# windows: '=' + texture letter. Solid to walk into, open to eyes, ears and bullets.
$script:WindowCodes = @{ [char]'S' = 33; [char]'B' = 34; [char]'W' = 35; [char]'R' = 36; [char]'M' = 37; [char]'G' = 38; [char]'T' = 39 }
# breakable walls: '!' + texture letter. Only explosions bring them down.
$script:BreakCodes = @{ [char]'S' = 26; [char]'B' = 27; [char]'W' = 28; [char]'R' = 29; [char]'M' = 30; [char]'G' = 31; [char]'T' = 32 }
$script:TEX_LEVER_OFF   = 23
$script:TEX_LEVER_ON    = 24
$script:TEX_DOOR_REMOTE = 25
$script:TEX_SWITCH_OFF = 12
$script:TEX_SWITCH_ON  = 13
$script:TEX_JAMB       = 14
$script:TEX_DOOR       = 15      # + lock (0..3)

$script:WallCodes = [hashtable]::new([StringComparer]::Ordinal)      # map codes are case sensitive
foreach ($wc in @('SS', 1), @('Sb', 2), @('Sp', 3), @('BB', 4), @('Bc', 5), @('WW', 6), @('Wp', 7), @('Ws', 8),
                 @('RR', 9), @('Rb', 10), @('MM', 11), @('MX', 12), @('GG', 19), @('Gv', 20), @('TT', 21), @('Tl', 22), @('MY', 40),
                 # second letter: t = PowerShell console, h = poster ("help"), e = error screen, n = neon prompt, g = graffiti
                 @('St', 42), @('Bt', 43), @('Wt', 44), @('Rt', 45), @('Mt', 46), @('Gt', 47), @('Tt', 48),
                 @('Sh', 49), @('Wh', 50), @('Rh', 51), @('Me', 52), @('Te', 53), @('Tn', 54), @('Mn', 55), @('Rg', 56), @('Sg', 57)) { $script:WallCodes[$wc[0]] = $wc[1] }
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
    [char]'l' = 'launcher'; [char]'o' = 'rockets'; [char]'t' = 'flamer'; [char]'j' = 'tknives'
    [char]'b' = 'vest'; [char]'k' = 'keycard'
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
    [char]'e' = @('barrel_red', $true)     # explosive - spawned as a shootable actor, see Map.ps1
    [char]'r' = @('rack', $true);          [char]'T' = @('crt', $true)       # server rack, a desk with a PowerShell terminal
}

# ---------------------------------------------------------------------------------------------
# Enemies. Speeds in tiles per tic. Shoot = list of @(sprite, tics, fireAtEnd)
# ---------------------------------------------------------------------------------------------
$script:EnemyCodes = @{
    [char]'g' = 'guard'; [char]'d' = 'dog'; [char]'e' = 'elite'
    [char]'o' = 'officer'; [char]'m' = 'mutant'; [char]'b' = 'boss'; [char]'u' = 'uber'
    [char]'s' = 'sniper'; [char]'h' = 'shield'; [char]'k' = 'bot'
    [char]'c' = 'camera'; [char]'t' = 'turret'; [char]'x' = 'bsod'
    [char]'y' = 'bug'; [char]'n' = 'engineer'; [char]'a' = 'auditor'
}

$script:EnemyDefs = @{
    guard = @{
        HP = @(15, 20, 25, 25); Points = 100; Patrol = 0.0078; Chase = 0.0234
        ReactBase = 1; ReactDiv = 4; Doors = $true; Pain = $true; Rotates = $true
        Accuracy = 1.0; Drop = 'clip_small'; AlertSnd = 'alert_guard'; ShotSnd = 'shot_enemy'; DieSnd = 'die_a'
        Shoot = @(, @('aim', 20, $false)) + @(, @('aim', 20, $true)) + @(, @('fire', 20, $false))
        DieTics = 15
    }
    officer = @{
        HP = @(30, 40, 50, 50); Points = 400; Patrol = 0.0078; Chase = 0.039
        ReactBase = 2; ReactDiv = 0; Doors = $true; Pain = $true; Rotates = $true
        Accuracy = 1.0; Drop = 'clip_small'; AlertSnd = 'alert_officer'; ShotSnd = 'shot_enemy'; DieSnd = 'die_b'
        Shoot = @(, @('aim', 6, $false)) + @(, @('aim', 20, $true)) + @(, @('fire', 10, $false))
        DieTics = 11
    }
    elite = @{
        HP = @(55, 80, 100, 100); Points = 500; Patrol = 0.0078; Chase = 0.0312
        ReactBase = 1; ReactDiv = 6; Doors = $true; Pain = $true; Rotates = $true
        Accuracy = 1.5; Drop = 'mgun_or_clip'; AlertSnd = 'alert_elite'; ShotSnd = 'shot_elite'; DieSnd = 'die_b'
        Shoot = @(, @('aim', 20, $false)) + @(, @('aim', 20, $true)) + @(, @('fire', 10, $false)) +
                @(, @('aim', 10, $true)) + @(, @('fire', 10, $false)) + @(, @('aim', 10, $true)) +
                @(, @('fire', 10, $false)) + @(, @('aim', 25, $false))
        DieTics = 15
    }
    mutant = @{
        HP = @(30, 45, 55, 65); Points = 700; Patrol = 0.0078; Chase = 0.0234
        ReactBase = 1; ReactDiv = 6; Doors = $true; Pain = $true; Rotates = $true
        Accuracy = 1.0; Drop = 'clip_small'; AlertSnd = $null; ShotSnd = 'shot_enemy'; DieSnd = 'die_c'
        Shoot = @(, @('aim', 10, $true)) + @(, @('fire', 20, $false)) + @(, @('aim', 15, $true)) + @(, @('fire', 25, $false))
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
        HP = @(350, 600, 900, 1200); Points = 5000; Patrol = 0.0078; Chase = 0.0234
        ReactBase = 1; ReactDiv = 0; Doors = $true; Pain = $false; Rotates = $false
        Accuracy = 1.5; Drop = 'key_gold'; AlertSnd = 'alert_boss'; ShotSnd = 'shot_boss'; DieSnd = 'die_boss'
        Shoot = @(, @('aim', 35, $false)) + @(, @('fire', 10, $true)) + @(, @('aim', 10, $false)) +
                @(, @('fire', 10, $true)) + @(, @('aim', 10, $false)) + @(, @('fire', 10, $true)) +
                @(, @('aim', 35, $false))
        DieTics = 15
    }
    # Sniper: fragile and slow, but takes his time to aim and then hits hard at ANY distance. Never shouts.
    sniper = @{
        HP = @(15, 25, 30, 30); Points = 600; Patrol = 0.0078; Chase = 0.012
        ReactBase = 1; ReactDiv = 6; Doors = $true; Pain = $true; Rotates = $true
        Accuracy = 1.0; Marksman = $true; Drop = 'clip_small'; AlertSnd = $null; ShotSnd = 'shot_sniper'; DieSnd = 'die_a'
        Shoot = @(, @('aim', 60, $false)) + @(, @('aim', 10, $true)) + @(, @('fire', 25, $false))
        DieTics = 12
    }
    # Shield bearer: bullets and blades glance off the shield. He is only vulnerable from behind,
    # while he lowers the shield to shoot - or to anything that does not care (beam, blast, explosions).
    shield = @{
        HP = @(45, 65, 80, 80); Points = 500; Patrol = 0.0078; Chase = 0.0195
        ReactBase = 1; ReactDiv = 6; Doors = $true; Pain = $false; Rotates = $true
        Accuracy = 1.0; Shield = $true; Drop = 'clip_small'; AlertSnd = 'alert_elite'; ShotSnd = 'shot_enemy'; DieSnd = 'die_b'
        Shoot = @(, @('aim', 25, $false)) + @(, @('aim', 12, $true)) + @(, @('fire', 12, $false)) + @(, @('aim', 12, $false))
        DieTics = 15
    }
    # Kamikaze bot: rolls at you at speed and blows itself up - shooting it has the same effect. No doors.
    bot = @{
        HP = @(10, 15, 20, 20); Points = 300; Patrol = 0.02; Chase = 0.06
        ReactBase = 1; ReactDiv = 8; Doors = $false; Pain = $false; Rotates = $false
        Accuracy = 1.0; Drop = $null; AlertSnd = 'bot_beep'; ShotSnd = $null; DieSnd = $null
        Shoot = @(); ChaseThink = 'BotChase'; DieScream = 'Explode'; BlastRadius = 1.9; BlastDamage = 75
        DieTics = 4
    }
    # The bug: small, quick, zig-zags and bites. Fix it with a blade, a bullet or fire and it is gone - blow it up and
    # there are two smaller ones ("fix one, get two").
    bug = @{
        HP = @(8, 12, 16, 16); Points = 150; Patrol = 0.02; Chase = 0.05; SplitInto = 'buglet'
        ReactBase = 1; ReactDiv = 8; Doors = $false; Pain = $false; Rotates = $false
        Accuracy = 1.0; Drop = $null; AlertSnd = 'bug_chirp'; ShotSnd = 'bite'; DieSnd = 'bug_squish'
        Shoot = @(); ChaseThink = 'DogChase'; Leaps = $true
        DieTics = 8
    }
    buglet = @{
        HP = @(3, 4, 5, 5); Points = 50; Patrol = 0.03; Chase = 0.065
        ReactBase = 1; ReactDiv = 8; Doors = $false; Pain = $false; Rotates = $false
        Accuracy = 1.0; Drop = $null; AlertSnd = 'bug_chirp'; ShotSnd = 'bite'; DieSnd = 'bug_squish'
        Shoot = @(); ChaseThink = 'DogChase'; Leaps = $true
        DieTics = 8
    }
    # The engineer: a poor shot, but he keeps the house running - repairs sentry guns and cameras that have been
    # destroyed, takes hacked sentry guns back and patches up whoever stands near him. Always the first target.
    engineer = @{
        HP = @(25, 35, 45, 45); Points = 300; Patrol = 0.0078; Chase = 0.0234
        ReactBase = 1; ReactDiv = 4; Doors = $true; Pain = $true; Rotates = $true
        Accuracy = 0.8; Drop = 'clip_small'; AlertSnd = 'alert_guard'; ShotSnd = 'shot_enemy'; DieSnd = 'die_a'
        Shoot = @(, @('aim', 24, $false)) + @(, @('aim', 20, $true)) + @(, @('fire', 20, $false))
        ChaseThink = 'EngineerChase'
        DieTics = 15
    }
    # The auditor: unarmed. When he sees the player he runs for the nearest terminal - and if he gets there, his report
    # raises the building's execution policy by a whole level. Carries a keycard, always.
    auditor = @{
        HP = @(20, 30, 40, 40); Points = 800; Patrol = 0.0078; Chase = 0.047
        ReactBase = 1; ReactDiv = 0; Doors = $true; Pain = $true; Rotates = $true
        Accuracy = 1.0; Drop = 'keycard'; AlertSnd = 'alert_officer'; ShotSnd = $null; DieSnd = 'die_b'
        Shoot = @(); ChaseThink = 'AuditorChase'
        DieTics = 12
    }
    # Security camera: harmless by itself, but what it sees heats up the building's execution policy - fast.
    # It sweeps a quarter turn to either side. Does not count as a kill; the console switches it off quietly.
    camera = @{
        HP = @(8, 10, 12, 12); Points = 200; Patrol = 0.0; Chase = 0.0; NoCount = $true; Machine = $true
        ReactBase = 1; ReactDiv = 8; Doors = $false; Pain = $false; Rotates = $false
        Accuracy = 1.0; Drop = $null; AlertSnd = 'bot_beep'; ShotSnd = $null; DieSnd = 'clang'
        Shoot = @(); StandThink = 'CameraStand'; ChaseThink = 'CameraChase'
        DieTics = 5
    }
    # Sentry gun: never moves, fires bursts at whatever it has been told to. Set-Turret -Owner Me changes who that is.
    turret = @{
        HP = @(35, 50, 65, 65); Points = 400; Patrol = 0.0; Chase = 0.0; NoCount = $true; Machine = $true
        ReactBase = 1; ReactDiv = 8; Doors = $false; Pain = $false; Rotates = $false
        Accuracy = 1.0; Drop = 'clip_small'; AlertSnd = 'bot_beep'; ShotSnd = 'shot_elite'; DieSnd = $null
        Shoot = @(, @('aim', 16, $false)) + @(, @('fire', 6, $true)) + @(, @('aim', 6, $false)) + @(, @('fire', 6, $true)) +
                @(, @('aim', 6, $false)) + @(, @('fire', 6, $true)) + @(, @('aim', 24, $false))
        ChaseThink = 'TurretChase'; DieScream = 'Explode'; BlastRadius = 1.3; BlastDamage = 25
        DieTics = 5
    }
    # The super boss, phase 1: a walking war machine - bursts of gunfire, then a salvo of rockets.
    uber = @{
        HP = @(550, 950, 1400, 1800); Points = 10000; Patrol = 0.0078; Chase = 0.0195
        ReactBase = 1; ReactDiv = 0; Doors = $false; Pain = $false; Rotates = $false
        Accuracy = 1.5; Drop = $null; AlertSnd = 'alert_uber'; ShotSnd = 'shot_boss'; DieSnd = 'die_uber'
        Shoot = @(, @('aim', 30, $false)) + @(, @('fire', 8, $true)) + @(, @('aim', 8, $false)) + @(, @('fire', 8, $true)) +
                @(, @('aim', 8, $false)) + @(, @('fire', 8, $true)) + @(, @('aim', 30, $false)) + @(, @('rocket', 12, 'Rocket')) + @(, @('aim', 12, $false)) +
                @(, @('rocket', 12, 'Rocket')) + @(, @('aim', 12, $false)) + @(, @('rocket', 12, 'Rocket')) + @(, @('aim', 20, 'Jam'))
        DieTics = 20; DieAction = 'SpawnPilot'
    }
    # The last one: BLUE SCREEN. A monitor on a tangle of cables. Bursts, a rocket - and the crash: the picture tears and
    # the player's controls hang for most of a second. When it dies, everything that depended on it stands still.
    bsod = @{
        HP = @(700, 1200, 1700, 2200); Points = 20000; Patrol = 0.0078; Chase = 0.026; Machine = $true
        ReactBase = 1; ReactDiv = 0; Doors = $false; Pain = $false; Rotates = $false
        Accuracy = 1.5; Drop = $null; AlertSnd = 'alert_uber'; ShotSnd = 'shot_boss'; DieSnd = 'die_uber'
        Shoot = @(, @('aim', 25, $false)) + @(, @('glitch', 22, 'Glitch')) + @(, @('aim', 10, $false)) + @(, @('fire', 8, $true)) + @(, @('aim', 6, $false)) +
                @(, @('fire', 8, $true)) + @(, @('aim', 6, $false)) + @(, @('fire', 8, $true)) + @(, @('aim', 20, $false)) + @(, @('rocket', 12, 'Rocket')) + @(, @('aim', 25, $false))
        DieTics = 22; DieAction = 'Halt'
    }
    # ... phase 2: the pilot bails out - little armour, but fast and trigger-happy.
    pilot = @{
        HP = @(140, 250, 380, 500); Points = 5000; Patrol = 0.0078; Chase = 0.05
        ReactBase = 1; ReactDiv = 0; Doors = $true; Pain = $false; Rotates = $true
        Accuracy = 1.5; Drop = 'crown'; AlertSnd = 'alert_officer'; ShotSnd = 'shot_elite'; DieSnd = 'die_b'
        Shoot = @(, @('aim', 12, $false)) + @(, @('aim', 8, $true)) + @(, @('fire', 8, $false)) + @(, @('aim', 8, $true)) +
                @(, @('fire', 8, $false)) + @(, @('aim', 8, $true)) + @(, @('fire', 8, $false)) + @(, @('aim', 30, $false))
        DieTics = 12
    }
}

# Who the bosses are in this building. Shown over their health bar once they have noticed you.
$script:BossNames = @{
    boss  = 'LEGACY.BAT  -  runs as SYSTEM, nobody dares to touch it'
    uber  = 'THE PRINTER  -  PC LOAD LETTER'
    pilot = 'THE PRINTER DRIVER  -  unsigned'
    bsod  = 'BLUE SCREEN  -  :(  your admin ran into a problem'
}

# things that live in the actor list without being enemies
$script:MiscDefs = @{
    rocket = @{ Speed = 0.09; Rotates = $false; Doors = $false; Pain = $false }
    # the player's own projectiles
    procket = @{ Speed = 0.16; Rotates = $false; Doors = $false; Pain = $false; BlastRadius = 1.9; BlastDamage = 120 }
    tknife  = @{ Speed = 0.22; Rotates = $false; Doors = $false; Pain = $false }
    fx = @{ Rotates = $false; Doors = $false; Pain = $false }      # short-lived effects: blood, sparks
    drone = @{ Rotates = $false; Doors = $false; Pain = $false; Speed = 0.07; Capacity = 6; Life = 2100.0 }      # Start-Job: a background job with rotors
    peer = @{ Rotates = $true; Doors = $false; Pain = $false; Points = 0 }      # the other player of a network game
    # explosive barrel: an "inert" actor - it can be shot, but never thinks, scores or counts as a kill
    barrel = @{ Inert = $true; HP = 15; Rotates = $false; Doors = $false; Pain = $false; Points = 0; BlastRadius = 2.2; BlastDamage = 90 }
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
        $chaseThink = if ($def.ChaseThink) { $def.ChaseThink } elseif ($kind -eq 'dog') { 'DogChase' } else { 'Chase' }

        Add-State "$kind.stand" "$kind.s" $rot 0 $(if ($def.StandThink) { $def.StandThink } else { 'Stand' }) $null "$kind.stand"

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
        Add-State "$kind.die1" "$kind.die1" $false $t $null $(if ($def.DieScream) { $def.DieScream } else { 'DeathScream' }) "$kind.die2"
        Add-State "$kind.die2" "$kind.die2" $false $t $null $null "$kind.die3"
        Add-State "$kind.die3" "$kind.die3" $false $t $null $def.DieAction "$kind.dead"
        Add-State "$kind.dead" "$kind.dead" $false 0 $null $null "$kind.dead"
    }

    # THE PRINTER's paper jam: it stands there blinking, takes triple damage - and prints reinforcements
    Add-State 'uber.jam1' 'uber.jam' $false 90 $null $null 'uber.jam2'
    Add-State 'uber.jam2' 'uber.s'   $false 20 $null $null 'uber.jam3'
    Add-State 'uber.jam3' 'uber.jam' $false 90 $null $null 'uber.jam4'
    Add-State 'uber.jam4' 'uber.s'   $false 20 $null $null 'uber.jam5'
    Add-State 'uber.jam5' 'uber.jam' $false 60 $null $null 'uber.chase1'

    # the bugs leap like the dog does
    foreach ($k in 'bug', 'buglet') {
        Add-State "$k.jump1" "$k.jump" $false 8 $null $null   "$k.jump2"
        Add-State "$k.jump2" "$k.jump" $false 8 $null 'Bite'  "$k.jump3"
        Add-State "$k.jump3" "$k.s"    $false 12 $null $null  "$k.chase1"
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

    # Start-Job's drone: two frames of rotor, thinking in both
    Add-State 'drone.fly1' 'drone.a' $false 4 'Drone' $null 'drone.fly2'
    Add-State 'drone.fly2' 'drone.b' $false 4 'Drone' $null 'drone.fly1'

    # effects: three frames each, then gone
    Add-State 'procket.fly' 'rocket' $false 0 'PlayerProjectile' $null 'procket.fly'
    Add-State 'tknife.fly'  'tknife' $false 0 'PlayerProjectile' $null 'tknife.fly'
    foreach ($fx in 'blood', 'puff', 'flame') {
        Add-State "fx.${fx}1" "fx.${fx}1" $false 5 $null $null "fx.${fx}2"
        Add-State "fx.${fx}2" "fx.${fx}2" $false 5 $null $null "fx.${fx}3"
        Add-State "fx.${fx}3" "fx.${fx}3" $false 5 $null 'Remove' "fx.${fx}3"
    }

    # -WhatIf: the ghosts that show where everybody will be (see Abilities.ps1)
    foreach ($mark in 'dot', 'ghost', 'threat') { Add-State "whatif.$mark" "whatif.$mark" $false 0 $null $null "whatif.$mark" }

    # the other players of a network game (one coat per slot): they never think, Network.ps1 picks the frame
    foreach ($peer in 'peer0', 'peer1', 'peer2', 'peer3') {
        Add-State "$peer.stand" "$peer.s" $true 0 $null $null "$peer.stand"
        foreach ($i in 1..4) { Add-State "$peer.w$i" "$peer.w$i" $true 0 $null $null "$peer.w$i" }
        foreach ($pose in 'fire', 'pain', 'die1', 'die2', 'die3', 'dead') { Add-State "$peer.$pose" "$peer.$pose" $false 0 $null $null "$peer.$pose" }
    }

    # explosive barrels: a short fuse (so chain reactions ripple through a room), then the blast
    Add-State 'barrel.idle' 'barrel_red' $false 0 $null $null 'barrel.idle'
    Add-State 'barrel.fuse' 'barrel_red' $false 5 $null 'Explode' 'rocket.boom1'
}

# ---------------------------------------------------------------------------------------------
# Weapons. Each attack frame = @(tics, action, picture)
#   none | knife | fire | repeat (loop back while trigger held) | firerepeat | beam | blast |
#   launch | flame | flamerepeat | throw | end
# Cost = bullets per shot. The two special weapons are POLF3D's own invention:
#   Pipeline - "|" passes everything along: the beam pierces EVERY enemy in the line of fire
#   Force    - "Remove-Item -Recurse -Force": wipes the whole field of view, fed by rare charges
# ---------------------------------------------------------------------------------------------
# Res = what a shot consumes (none | ammo | charges | rockets | knives), Cost = how much of it.
$script:Weapons = @(
    @{ Name = 'Knife';           Key = 'knife';    Snd = 'knife';       Res = 'none';    Cost = 0; Frames = @(@(6, 'none', 1), @(6, 'knife', 2), @(6, 'none', 3), @(6, 'end', 4)) }
    @{ Name = 'Pistol';          Key = 'pistol';   Snd = 'shot_pistol'; Res = 'ammo';    Cost = 1; Frames = @(@(6, 'none', 1), @(6, 'fire', 2), @(6, 'none', 3), @(6, 'end', 4)) }
    @{ Name = 'Machine gun';     Key = 'mgun';     Snd = 'shot_mgun';   Res = 'ammo';    Cost = 1; Frames = @(@(6, 'none', 1), @(6, 'fire', 2), @(6, 'repeat', 3), @(6, 'end', 4)) }
    @{ Name = 'Chain gun';       Key = 'chaingun'; Snd = 'shot_chain';  Res = 'ammo';    Cost = 1; Frames = @(@(6, 'none', 1), @(6, 'fire', 2), @(6, 'firerepeat', 3), @(6, 'end', 4)) }
    @{ Name = 'Pipeline Cannon'; Key = 'pipeline'; Snd = 'shot_pipe';   Res = 'ammo';    Cost = 4; Frames = @(@(8, 'none', 1), @(8, 'beam', 2), @(12, 'none', 3), @(8, 'end', 4)) }
    @{ Name = 'Force Blaster';   Key = 'forcegun'; Snd = 'shot_force';  Res = 'charges'; Cost = 1; Frames = @(@(14, 'none', 1), @(10, 'blast', 2), @(16, 'none', 3), @(12, 'end', 4)) }
    @{ Name = 'Rocket launcher'; Key = 'launcher'; Snd = 'rocket';      Res = 'rockets'; Cost = 1; Frames = @(@(10, 'none', 1), @(10, 'launch', 2), @(22, 'none', 3), @(10, 'end', 4)) }
    @{ Name = 'Flamethrower';    Key = 'flamer';   Snd = 'flame';       Res = 'ammo';    Cost = 1; Frames = @(@(3, 'none', 1), @(4, 'flame', 2), @(4, 'flamerepeat', 3), @(4, 'end', 4)) }
    @{ Name = 'Throwing knives'; Key = 'tknife';   Snd = 'knife';       Res = 'knives';  Cost = 1; Frames = @(@(5, 'none', 1), @(5, 'throw', 2), @(8, 'none', 3), @(6, 'end', 4)) }
)
$script:WEAPON_PIPELINE = 4
$script:WEAPON_FORCE = 5
$script:WEAPON_LAUNCHER = 6
$script:WEAPON_FLAMER = 7
$script:WEAPON_TKNIFE = 8
$script:ResourceMax = @{ ammo = 99; charges = 9; rockets = 20; knives = 20 }
$script:SUDO_TICS = 1400.0        # the "sudo" power-up lasts 20 seconds

# What the difficulty changes:
#   DamageScale  the damage the player takes          Aim    the enemies' chance to hit
#   React        how long enemies need to react        Ammo   what clips (and the start kit) are worth
#   Thin         the share of ordinary enemies that stay at home (bosses always show up)
#   Hear         how many tiles away gunfire still wakes enemies up (in rooms connected to the player's)
# ... plus the hit points of every enemy (the HP tables above) and the @spawn reinforcements of the maps.
$script:Difficulties = @(
    @{ Name = 'Intern (-WhatIf)';              DamageScale = 0.2;  Aim = 0.55; React = 2.5; Ammo = 2.0; Thin = 0.35; Hear = 10 }
    @{ Name = 'Sysadmin';                      DamageScale = 0.33; Aim = 0.7;  React = 1.6; Ammo = 1.5; Thin = 0.2;  Hear = 13 }
    @{ Name = 'Senior Engineer';               DamageScale = 0.6;  Aim = 0.85; React = 1.0; Ammo = 1.0; Thin = 0.08; Hear = 18 }
    @{ Name = 'root (-Force -Confirm:$false)'; DamageScale = 1.0;  Aim = 1.0;  React = 0.7; Ammo = 1.0; Thin = 0.0;  Hear = 99 }
)
