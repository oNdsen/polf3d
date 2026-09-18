# POLF 3D - Copyright (c) 2026 oNdsen. Licensed under the MIT License, see LICENSE.

# Player.ps1 - movement and collision, "use", weapons, picking things up, taking damage.

$script:WALK_SPEED = 0.055        # tiles per tic
$script:RUN_SPEED  = 0.095
$script:SNEAK_SPEED = 0.026       # slow - but nobody hears you coming
$script:BACK_FACTOR = 0.67        # walking backwards is slower
$script:WALK_TURN  = 1.9          # degrees per tic
$script:RUN_TURN   = 3.2

function New-OwnedList([bool]$All) {
    $owned = [bool[]]::new($script:Weapons.Count)
    for ($i = 0; $i -lt $owned.Length; $i++) { $owned[$i] = $All -or $i -le 1 }
    , $owned
}

function New-Player {
    $script:P = @{
        X = 0.0; Y = 0.0; Angle = 0.0; Area = -1
        Health = 100; Ammo = (Get-AmmoCount $script:START_AMMO); Lives = 3; Score = 0; NextExtra = $script:EXTRA_LIFE_POINTS
        KeyGold = $false; KeySilver = $false
        Weapon = 1; ChosenWeapon = 1
        Owned = New-OwnedList $false                              # knife and pistol from the start
        Charges = 0; Rockets = 0; Knives = 0; SudoTics = 0.0
        AttackFrame = -1; AttackTics = 0.0; WeaponFrame = 0
        Running = $false; Sneaking = $false; UseHeld = $false; FireHeld = $false
        Privilege = 50.0                                          # pays for the abilities (Abilities.ps1)
        FaceTimer = 0.0; FaceLook = 0; GrinTics = 0.0; PainTics = 0.0; RageTics = 0.0; LookHold = 0.0; FaceKey = ''
        Cheated = [bool]($script:GodMode -or $script:InfiniteAmmo -or $script:OneHitKill)      # marks the high score entry
        RunTics = 0.0; RunInvalid = $false                       # speedrun clock over all floors, deaths included
    }
}

# ---------------------------------------------------------------------------------------------
# Cheats.  F6 give all | F7 infinite ammo | F8 god mode | F11 one-hit kill (cuts BOTH ways)
# ... or type the code words GIVEALL, NOLIMIT, ROOT, ONEHIT while playing.
# ---------------------------------------------------------------------------------------------
$script:CheatCodes = @{ GIVEALL = 'GiveAll'; NOLIMIT = 'Ammo'; ROOT = 'God'; ONEHIT = 'OneHit' }

function Invoke-Cheat([string]$Name) {
    $p = $script:P
    if ($script:NetLive -and $script:Net.Mode -eq 'duel') { Show-Message 'No cheating in a duel!'; return }
    $onOff = { param($flag) if ($flag) { 'ON' } else { 'OFF' } }
    switch ($Name) {
        'GiveAll' {
            $p.Owned = New-OwnedList $true
            $p.Ammo = $script:MAX_AMMO; $p.Charges = [Math]::Max($p.Charges, 9); $p.Rockets = 20; $p.Knives = 20; $p.Health = 100
            $p.KeyGold = $true; $p.KeySilver = $true
            if ($p.AttackFrame -lt 0) { $p.Weapon = 3; $p.ChosenWeapon = 3 }
            Show-Message 'CHEAT: all weapons, ammo, charges and keys'
        }
        'Ammo'   { $script:InfiniteAmmo = -not $script:InfiniteAmmo; Show-Message "CHEAT: infinite ammo $(& $onOff $script:InfiniteAmmo)" }
        'God'    { $script:GodMode = -not $script:GodMode; Show-Message "CHEAT: god mode $(& $onOff $script:GodMode)" }
        'OneHit' { $script:OneHitKill = -not $script:OneHitKill; Show-Message "CHEAT: one-hit kill $(& $onOff $script:OneHitKill) - cuts BOTH ways!" }
        default  { return }
    }
    $p.Cheated = $true
    Start-Sfx 'sudo'
    $script:HudDirty = $true
}

# Collects typed letters and fires a cheat when the tail of the buffer spells a code word.
function Add-CheatKey([int]$KeyCode) {
    if ($KeyCode -lt 65 -or $KeyCode -gt 90) { return }
    $buf = "$($script:CheatBuffer)$([char]$KeyCode)"
    if ($buf.Length -gt 12) { $buf = $buf.Substring($buf.Length - 12) }
    $script:CheatBuffer = $buf
    foreach ($code in $script:CheatCodes.Keys) {
        if ($buf.EndsWith($code)) { $script:CheatBuffer = ''; Invoke-Cheat $script:CheatCodes[$code]; return }
    }
}

# After death the player restarts the level with the basic kit (score and lives persist).
function Reset-PlayerForLevel {
    $p = $script:P
    $p.X = $script:StartX; $p.Y = $script:StartY; $p.Angle = $script:StartAngle
    $p.Area = $script:AreaOf[[int][Math]::Floor($p.Y) * $script:MapW + [int][Math]::Floor($p.X)]
    $p.AttackFrame = -1; $p.WeaponFrame = 0; $p.KeyGold = $false; $p.KeySilver = $false
    $p.UseHeld = $true; $p.FireHeld = $true
    Update-AreaByPlayer
}

function Reset-PlayerKit {
    $p = $script:P
    $p.Health = 100; $p.Ammo = Get-AmmoCount $script:START_AMMO
    $p.Weapon = 1; $p.ChosenWeapon = 1
    $p.Owned = New-OwnedList $false
    $p.Charges = 0; $p.Rockets = 0; $p.Knives = 0; $p.SudoTics = 0.0
}

function Show-Message([string]$Text) {
    if ($script:Predicting) { return }
    if ($script:NetLive -and $script:NetScope -in 'world', 'peer') {
        # network game: meant for one guest only, or for everybody
        if ($script:NetScope -eq 'peer') { Send-NetPeer "X|$Text"; return }
        Send-NetMessage "X|$Text"
    }
    $script:Message = $Text
    $script:MessageUntil = $script:Clock.Elapsed.TotalSeconds + 2.5
}

function Add-Score([int]$Points) {
    if ($script:NetAsPeer) { Send-NetPeer "S|$Points"; return }         # earned by a guest
    $p = $script:P
    $p.Score += $Points
    while ($p.Score -ge $p.NextExtra) {
        $p.NextExtra += $script:EXTRA_LIFE_POINTS
        if ($p.Lives -lt 9) { $p.Lives++ }
        Start-Sfx 'oneup'
    }
    $script:HudDirty = $true
}

# ---------------------------------------------------------------------------------------------
# Collision
# ---------------------------------------------------------------------------------------------
function Test-PlayerSpot([double]$X, [double]$Y) {
    $r = $script:PLAYER_RADIUS; $w = $script:MapW
    [int]$xl = [Math]::Floor($X - $r); [int]$xh = [Math]::Floor($X + $r)
    [int]$yl = [Math]::Floor($Y - $r); [int]$yh = [Math]::Floor($Y + $r)
    for ($ty = $yl; $ty -le $yh; $ty++) {
        for ($tx = $xl; $tx -le $xh; $tx++) {
            $idx = $ty * $w + $tx
            $t = $script:Tiles[$idx]
            if ($t -eq 0) { if ($script:StaticBlock[$idx]) { return $false }; continue }
            if ($t -ge $script:TILE_DOOR_BASE -and $t -lt $script:TILE_PUSHWALL -and $script:Doors[$t - $script:TILE_DOOR_BASE].Action -eq 'open') { continue }
            return $false
        }
    }
    if ($script:NoClipActors) { return $true }
    $min = $script:MIN_ACTOR_DIST
    foreach ($a in $script:Actors) {
        if ($a.Shootable -and [Math]::Abs($X - $a.X) -lt $min -and [Math]::Abs($Y - $a.Y) -lt $min) {
            # already overlapping (e.g. after a respawn)? then at least allow moving apart
            if ([Math]::Abs($script:P.X - $a.X) -lt $min -and [Math]::Abs($script:P.Y - $a.Y) -lt $min) { continue }
            return $false
        }
    }
    $true
}

# Try the full move; if blocked slide along the wall on one axis.
function Move-Player([double]$DX, [double]$DY) {
    $p = $script:P
    $steps = [int][Math]::Ceiling([Math]::Max([Math]::Abs($DX), [Math]::Abs($DY)) / 0.25)
    if ($steps -lt 1) { return }
    $sx = $DX / $steps; $sy = $DY / $steps
    for ($i = 0; $i -lt $steps; $i++) {
        if (Test-PlayerSpot ($p.X + $sx) ($p.Y + $sy)) { $p.X += $sx; $p.Y += $sy }
        elseif (Test-PlayerSpot ($p.X + $sx) $p.Y) { $p.X += $sx }
        elseif (Test-PlayerSpot $p.X ($p.Y + $sy)) { $p.Y += $sy }
        else { break }
    }
    $area = $script:AreaOf[[int][Math]::Floor($p.Y) * $script:MapW + [int][Math]::Floor($p.X)]
    if ($area -ge 0 -and $area -ne $p.Area) { $p.Area = $area; Update-AreaByPlayer }
}

# ---------------------------------------------------------------------------------------------
# Use: doors, push-walls, the lift switch - always the tile straight ahead (N/E/S/W)
# ---------------------------------------------------------------------------------------------
function Invoke-Use {
    $p = $script:P
    $quad = [int][Math]::Floor((($p.Angle + 45.0) % 360.0) / 90.0) % 4          # 0 E, 1 N, 2 W, 3 S
    $dx = (1, 0, -1, 0)[$quad]; $dy = (0, -1, 0, 1)[$quad]
    $tx = [int][Math]::Floor($p.X) + $dx; $ty = [int][Math]::Floor($p.Y) + $dy
    if ($script:TerminalAt[$ty * $script:MapW + $tx] -and -not $script:NetLive) { Open-Console ($ty * $script:MapW + $tx); return }      # a terminal: log on
    if ($script:NetClient) { Send-NetMessage "U|$tx|$ty|$dx|$dy"; return }      # the world belongs to the host
    Invoke-UseAt $tx $ty $dx $dy
}

function Invoke-UseAt([int]$tx, [int]$ty, [int]$dx, [int]$dy) {
    if ($tx -lt 0 -or $ty -lt 0 -or $tx -ge $script:MapW -or $ty -ge $script:MapH) { return }
    $idx = $ty * $script:MapW + $tx
    $t = $script:Tiles[$idx]
    if ($script:PushTex[$idx] -ne 0) { Start-PushWall $tx $ty $dx $dy }
    elseif ($t -eq $script:TEX_LEVER_OFF) { Invoke-Lever $idx }
    elseif ($t -eq $script:TEX_SWITCH_OFF) {
        Set-MapTile $idx $script:TEX_SWITCH_ON
        Start-Sfx 'level_done'
        $script:LevelDone = $true
    }
    elseif ($t -eq $script:TEX_SECRET_OFF) {
        Set-MapTile $idx $script:TEX_SECRET_ON
        Start-Sfx 'level_done'
        $script:LevelDone = $true; $script:SecretExit = $true         # this lift goes somewhere else ...
    }
    elseif ($t -ge $script:TILE_DOOR_BASE -and $t -lt $script:TILE_PUSHWALL) { Invoke-DoorUse ($t - $script:TILE_DOOR_BASE) }
}

# ---------------------------------------------------------------------------------------------
# Weapons
# ---------------------------------------------------------------------------------------------
function Get-AimedTargets {
    # Whoever the renderer saw at the screen centre last frame, nearest first: the crosshair is on his body,
    # or at least close to him (a little help with aiming at distant targets).
    $cx = $script:ViewW / 2; $tol = $script:ViewW / 10
    $list = foreach ($a in $script:Actors) {
        if ($a.Shootable -and $a.Visible -and [Math]::Abs($a.ScreenX - $cx) -lt [Math]::Max($tol, $script:BODY_HALF * $script:ProjH / [Math]::Max(0.2, $a.Depth))) { $a }
    }
    @($list | Sort-Object Depth)
}

# Is any part of the target's body really in view within $Tolerance pixels of the crosshair? This is the test the
# renderer uses to clip sprites - the wall distance of every screen column - so whatever can be seen can be hit.
# (A line from the player to the CENTRE of the target is not good enough: past the frame of an open door one often
# sees, and aims at, no more than a shoulder.)
$script:BODY_HALF = 0.22                                          # half the width of a body, in tiles
function Test-TargetExposed([Actor]$a, [double]$Tolerance) {
    if ($a.Depth -le 0.2) { return $true }
    $zbuf = $script:ZBuf; $cx = $script:ViewW / 2
    $half = $script:BODY_HALF * $script:ProjH / $a.Depth
    $from = [int][Math]::Max(0, [Math]::Max($a.ScreenX - $half, $cx - $Tolerance))
    $to = [int][Math]::Min($script:ViewW - 1, [Math]::Min($a.ScreenX + $half, $cx + $Tolerance))
    for ($x = $from; $x -le $to; $x++) { if ($zbuf[$x] -ge $a.Depth) { return $true } }
    $false
}

function Invoke-GunAttack {
    $script:MadeNoise = $true
    $script:MuzzleFlash = 4.0                                    # lights up the room for a moment
    Start-Sfx $script:Weapons[$script:P.Weapon].Snd
    foreach ($a in (Get-AimedTargets)) {
        if (-not (Test-TargetExposed $a ($script:ViewW / 10))) { continue }
        $dist = [Math]::Max([Math]::Abs([Math]::Floor($a.X) - [Math]::Floor($script:P.X)), [Math]::Abs([Math]::Floor($a.Y) - [Math]::Floor($script:P.Y)))
        $r = Get-Rnd
        if ($dist -lt 2) { $damage = $r / 4 }
        elseif ($dist -lt 4) { $damage = $r / 6 }
        else {
            if (((Get-Rnd) / 12) -lt $dist) { break }           # long shots may simply miss
            $damage = $r / 6
        }
        Invoke-ActorDamage $a ([int][Math]::Floor($damage))
        return
    }
    $wall = Find-WallPoint                                       # nobody hit: the bullet strikes sparks off a wall
    if ($wall) { Add-Effect 'puff' $wall[0] $wall[1] }
}

function Invoke-KnifeAttack {
    Start-Sfx 'knife'
    $targets = Get-AimedTargets
    if ($targets.Count -eq 0 -or $targets[0].Depth -gt 1.5) { return }
    Invoke-ActorDamage $targets[0] ((Get-Rnd) -shr 4) 'knife'
}

# Pipeline-Kanone: the beam passes through everybody standing in the line of fire.
function Invoke-BeamAttack {
    $script:MadeNoise = $true
    Start-Sfx 'shot_pipe'
    $script:BeamFlash = 10.0
    foreach ($a in (Get-AimedTargets)) {
        if (Test-TargetExposed $a ($script:ViewW / 10)) { Invoke-ActorDamage $a (60 + ((Get-Rnd) -shr 2)) 'beam' }
    }
}

# Force-Blaster: Remove-Item -Recurse -Force on everything in sight.
function Invoke-BlastAttack {
    $script:MadeNoise = $true
    Start-Sfx 'shot_force'
    $script:ForceFlash = 24.0
    foreach ($a in @($script:Actors)) {
        if ($a.Shootable -and $a.Visible -and (Test-TargetExposed $a $script:ViewW)) { Invoke-ActorDamage $a (150 + (Get-Rnd)) 'blast' }
    }
}

# Can the weapon fire at all right now?
function Get-ResourceCount([string]$Res) {
    switch ($Res) { 'ammo' { $script:P.Ammo } 'charges' { $script:P.Charges } 'rockets' { $script:P.Rockets } 'knives' { $script:P.Knives } default { 0 } }
}

function Test-WeaponReady([int]$Index) {
    if (-not $script:P.Owned[$Index]) { return $false }
    $w = $script:Weapons[$Index]
    $script:InfiniteAmmo -or $w.Res -eq 'none' -or (Get-ResourceCount $w.Res) -ge $w.Cost
}

# Pays for one shot of the weapon in hand. Returns $false if the player cannot afford it.
function Use-WeaponResource {
    $p = $script:P; $w = $script:Weapons[$p.Weapon]
    if ($script:InfiniteAmmo -or $w.Res -eq 'none') { return $true }
    if ((Get-ResourceCount $w.Res) -lt $w.Cost) { return $false }
    switch ($w.Res) { 'ammo' { $p.Ammo -= $w.Cost } 'charges' { $p.Charges -= $w.Cost } 'rockets' { $p.Rockets -= $w.Cost } 'knives' { $p.Knives -= $w.Cost } }
    $script:HudDirty = $true
    $true
}

# Flamethrower: short range, wide cone, burns everybody in it - shields do not help.
function Invoke-FlameAttack {
    $script:MadeNoise = $true
    $script:MuzzleFlash = 3.0
    Start-Sfx 'flame'
    $p = $script:P; $rad = $p.Angle * [Math]::PI / 180.0
    $dx = [Math]::Cos($rad); $dy = - [Math]::Sin($rad)
    foreach ($d in 0.9, 1.9) {
        $side = ($script:Rng.NextDouble() - 0.5) * 0.5
        Add-Effect 'flame' ($p.X + $dx * $d - $dy * $side) ($p.Y + $dy * $d + $dx * $side)
    }
    $cx = $script:ViewW / 2; $tol = $script:ViewW / 4
    foreach ($a in @($script:Actors)) {
        if ($a.Shootable -and $a.Visible -and $a.Depth -lt 3.6 -and [Math]::Abs($a.ScreenX - $cx) -lt $tol -and (Test-TargetExposed $a $tol)) {
            Invoke-ActorDamage $a (6 + ((Get-Rnd) -shr 4)) 'flame'
        }
    }
}

# Falls back to the best weapon that still has something to shoot with.
function Select-UsableWeapon {
    $p = $script:P
    if (Test-WeaponReady $p.ChosenWeapon) { $p.Weapon = $p.ChosenWeapon; return }
    foreach ($i in 3, 2, 1) { if (Test-WeaponReady $i) { $p.Weapon = $i; return } }
    $p.Weapon = 0
}

function Update-Attack([double]$Tics, [bool]$Trigger) {
    $p = $script:P
    if ($p.AttackFrame -lt 0) { return }
    $frames = $script:Weapons[$p.Weapon].Frames
    $p.AttackTics -= $Tics
    while ($p.AttackTics -le 0) {
        $cur = $frames[$p.AttackFrame]
        $action = $cur[1]
        if ($action -eq 'end') {
            $p.AttackFrame = -1; $p.WeaponFrame = 0
            Select-UsableWeapon
            $script:HudDirty = $true
            return
        }
        if ($action -eq 'knife') { Invoke-KnifeAttack }
        elseif ($action -eq 'repeat') { if ($Trigger -and (Test-WeaponReady $p.Weapon)) { $p.AttackFrame -= 2 } }
        elseif ($action -ne 'none') {
            # every other action fires something - if the player can pay for it
            if (Use-WeaponResource) {
                if ($action -ne 'throw') { $script:Run.Shots++ }
                if ($action -like '*repeat' -and $Trigger) { $p.AttackFrame -= 2 }
                switch -Wildcard ($action) {
                    'fire*'  { Invoke-GunAttack }
                    'beam'   { Invoke-BeamAttack }
                    'blast'  { Invoke-BlastAttack }
                    'flame*' { Invoke-FlameAttack }
                    'launch' { $script:MadeNoise = $true; Start-Sfx 'rocket'; Add-PlayerProjectile 'procket' }
                    'throw'  { Start-Sfx 'knife'; Add-PlayerProjectile 'tknife' }          # silent: no noise
                }
            }
            elseif ($action -notlike 'fire*' -and $action -notlike 'flame*') { Start-Sfx 'noway' }
        }
        $p.AttackTics += $cur[0]
        $p.AttackFrame++
        $p.WeaponFrame = $frames[$p.AttackFrame][2]
    }
}

# ---------------------------------------------------------------------------------------------
# Items
# ---------------------------------------------------------------------------------------------
function Add-Health([int]$Points) { $script:P.Health = [Math]::Min(100, $script:P.Health + $Points) }

# Clips and the start kit are worth more on the easier difficulties.
function Get-AmmoCount([int]$Rounds) { [int][Math]::Round($Rounds * $script:Difficulties[$script:Difficulty].Ammo) }

function Add-Ammo([int]$Count) {
    $p = $script:P
    $p.Ammo = [Math]::Min($script:MAX_AMMO, $p.Ammo + $Count)
    if ($p.AttackFrame -lt 0) { Select-UsableWeapon }           # the knife was only a stopgap
}

function Add-Weapon([int]$Index) {
    $p = $script:P
    switch ($script:Weapons[$Index].Key) {                      # every weapon comes with a little to shoot
        'forcegun' { $p.Charges = [Math]::Min(9, $p.Charges + 1) }
        'launcher' { $p.Rockets = [Math]::Min(20, $p.Rockets + 2) }
        'tknife'   { $p.Knives = [Math]::Min(20, $p.Knives + 5) }
        'flamer'   { Add-Ammo 12 }
        default    { Add-Ammo 6 }
    }
    if (-not $p.Owned[$Index]) {
        $p.Owned[$Index] = $true
        $p.ChosenWeapon = $Index
        if ($p.AttackFrame -lt 0) { $p.Weapon = $Index }
    }
    $p.GrinTics = 100
}

# Returns $false if the player has no use for the item right now (it stays on the floor).
function Invoke-Pickup([string]$Item) {
    $p = $script:P
    switch ($Item) {
        'dogfood'    { if ($p.Health -ge 100) { return $false }; Add-Health 4;  Start-Sfx 'pickup' }
        'food'       { if ($p.Health -ge 100) { return $false }; Add-Health 10; Start-Sfx 'pickup' }
        'medkit'     { if ($p.Health -ge 100) { return $false }; Add-Health 25; Start-Sfx 'pickup' }
        'clip'       { if ($p.Ammo -ge $script:MAX_AMMO) { return $false }; Add-Ammo (Get-AmmoCount 8); Start-Sfx 'ammo' }
        'clip_small' { if ($p.Ammo -ge $script:MAX_AMMO) { return $false }; Add-Ammo (Get-AmmoCount 4); Start-Sfx 'ammo' }
        'mgun'       { Add-Weapon 2; Start-Sfx 'weapon'; Show-Message 'Machine gun!' }
        'chaingun'   { Add-Weapon 3; Start-Sfx 'weapon'; Show-Message 'Chain gun!' }
        'pipeline'   { Add-Weapon 4; Start-Sfx 'weapon'; Show-Message 'PIPELINE CANNON!  Pierces everything in the line of fire' }
        'forcegun'   { Add-Weapon 5; Start-Sfx 'weapon'; Show-Message 'FORCE-BLASTER!  Remove-Item -Recurse -Force' }
        'launcher'   { Add-Weapon 6; Start-Sfx 'weapon'; Show-Message 'ROCKET LAUNCHER!  Mind the blast radius' }
        'rockets'    { if ($p.Rockets -ge 20) { return $false }; $p.Rockets = [Math]::Min(20, $p.Rockets + 3); Start-Sfx 'ammo'; if ($p.AttackFrame -lt 0) { Select-UsableWeapon } }
        'flamer'     { Add-Weapon 7; Start-Sfx 'weapon'; Show-Message 'FLAMETHROWER!  Short range, no mercy' }
        'tknives'    { if ($p.Owned[8] -and $p.Knives -ge 20) { return $false }; Add-Weapon 8; Start-Sfx 'ammo'; Show-Message 'Throwing knives - silent and deadly from behind' }
        'charge'     { $p.Charges++; Start-Sfx 'ammo'; Show-Message 'Force charge' ; if ($p.AttackFrame -lt 0) { Select-UsableWeapon } }
        'sudo'       { $p.SudoTics = $script:SUDO_TICS; Start-Sfx 'sudo'; Show-Message 'SUDO!  Double damage dealt, half damage taken' }
        'key_gold'   { $p.KeyGold = $true;   Start-Sfx 'key'; Show-Message 'Gold key' }
        'key_silver' { $p.KeySilver = $true; Start-Sfx 'key'; Show-Message 'Silver key' }
        'coins'      { Add-Score 100;  $script:Stats.Treasures++; Start-Sfx 'treasure' }
        'goblet'     { Add-Score 500;  $script:Stats.Treasures++; Start-Sfx 'treasure' }
        'chest'      { Add-Score 1000; $script:Stats.Treasures++; Start-Sfx 'treasure' }
        'crown'      { Add-Score 5000; $script:Stats.Treasures++; Start-Sfx 'treasure' }
        'oneup'      {
            Add-Health 99; Add-Ammo 25
            if ($p.Lives -lt 9) { $p.Lives++ }
            $script:Stats.Treasures++; Start-Sfx 'oneup'; Show-Message 'Extra life!'
        }
    }
    if ($Item -notin 'dogfood', 'food', 'medkit', 'clip', 'clip_small', 'rockets', 'charge', 'coins', 'goblet', 'chest') { Add-TranscriptLine "picked up: $Item" 'VERBOSE' }
    $script:BonusFlash = 18.0
    $script:HudDirty = $true
    $true
}

function Update-Pickups {
    if ($script:P.Health -le 0) { return }                        # network games go on while one player lies dead
    $px = $script:P.X; $py = $script:P.Y
    for ($i = 0; $i -lt $script:Items.Count; $i++) {
        $s = $script:Items[$i]
        if ($s.Removed) { continue }
        if ([Math]::Abs($px - ($s.X + 0.5)) -lt 0.6 -and [Math]::Abs($py - ($s.Y + 0.5)) -lt 0.6) {
            if (Invoke-Pickup $s.Item) { $s.Removed = $true; if ($script:NetLive) { Register-NetPickup $i $true } }
        }
    }
}

# ---------------------------------------------------------------------------------------------
# Damage taken
# ---------------------------------------------------------------------------------------------
function Invoke-PlayerDamage([int]$Points, [Actor]$Attacker) {
    if ($script:Predicting) { return }                           # -WhatIf: nobody gets hurt in a forecast
    if ($script:NetAsPeer) { Send-NetPeer "H|$Points|$(if ($Attacker) { $Attacker.NetId } else { 0 })"; return }         # it hit a guest
    $p = $script:P
    if ($p.Health -le 0) { return }                              # already dead
    $Points = [int][Math]::Floor($Points * $script:Difficulties[$script:Difficulty].DamageScale)
    if ($p.SudoTics -gt 0) { $Points = [int][Math]::Floor($Points / 2) }
    if ($script:OneHitKill) { $Points = 999 }                    # the cheat cuts both ways: every hit is fatal
    if ($Points -le 0) { return }
    $before = $p.Health
    if (-not $script:GodMode) { $p.Health -= $Points }
    if ($p.Health -lt $script:Run.MinHealth) { $script:Run.MinHealth = $p.Health }
    if ($before -gt 25 -and $p.Health -le 25 -and $p.Health -gt 0) { Add-TranscriptLine "health is down to $($p.Health)" 'WARNING' }
    # the red flash and the jolt follow what the hit really cost (god mode: a token), and the flash never outlasts a second
    $felt = if ($script:GodMode) { 6 } else { [Math]::Min($Points, $before) }
    $script:DamageFlash = [Math]::Min(60.0, $script:DamageFlash + $felt)
    $script:Shake = [Math]::Min(14.0, $script:Shake + $felt / 2.0)
    $p.GrinTics = 0
    $p.PainTics = 22.0                                           # the face in the status bar winces ...
    if ($Attacker) {                                             # ... and then looks to where it came from
        $to = [Math]::Atan2(- ($Attacker.Y - $p.Y), $Attacker.X - $p.X) * 180.0 / [Math]::PI
        $side = (($to - $p.Angle + 540.0) % 360.0) - 180.0
        $p.FaceLook = if ($side -gt 20) { -1 } elseif ($side -lt -20) { 1 } else { 0 }
        $p.LookHold = 90.0
    }
    $script:HudDirty = $true
    if ($p.Health -le 0) {
        $p.Health = 0
        $script:Killer = $Attacker
        $script:PlayerDied = $true
        Add-TranscriptLine "killed by $(if ($Attacker) { "a $($Attacker.Kind)" } else { 'the building itself' })" 'ERROR'
        if ($script:NetLive -and $Attacker -and $Attacker.Kind -eq 'peer') { Register-NetFrag $Attacker.PeerSlot }
        Start-Sfx 'player_die'
    }
    else { Start-Sfx 'pain' }
}

# ---------------------------------------------------------------------------------------------
# Per-frame update. $In = @{ Forward; Strafe; Turn (-1..1 each); MouseTurn (degrees); Run; Fire; Use; Weapon (-1 or 0..5) }
# ---------------------------------------------------------------------------------------------
function Update-Player([double]$Tics, [hashtable]$In) {
    $p = $script:P
    $p.Sneaking = [bool]$In.Sneak
    $p.Running = [bool]$In.Run -and -not $p.Sneaking
    $script:StepNoise = 0.0                                      # how far this frame's footsteps and doors can be heard

    if ($In.Weapon -ge 0 -and $p.AttackFrame -lt 0 -and (Test-WeaponReady $In.Weapon)) {
        $p.Weapon = $In.Weapon; $p.ChosenWeapon = $In.Weapon; $script:HudDirty = $true
    }
    if ($p.SudoTics -gt 0) {
        $before = [Math]::Ceiling($p.SudoTics / 70)
        $p.SudoTics = [Math]::Max(0.0, $p.SudoTics - $Tics)
        if ([Math]::Ceiling($p.SudoTics / 70) -ne $before) { $script:HudDirty = $true }
    }

    if ($In.Use) { if (-not $p.UseHeld) { $p.UseHeld = $true; Invoke-Use } } else { $p.UseHeld = $false }

    if ($In.Fire) {
        if (-not $p.FireHeld -and $p.AttackFrame -lt 0) {
            $p.FireHeld = $true
            $frames = $script:Weapons[$p.Weapon].Frames
            $p.AttackFrame = 0; $p.AttackTics = $frames[0][0]; $p.WeaponFrame = $frames[0][2]
        }
    }
    else { $p.FireHeld = $false }

    $turn = if ($p.Running) { $script:RUN_TURN } else { $script:WALK_TURN }
    $p.Angle = ($p.Angle - $In.Turn * $turn * $Tics - $In.MouseTurn + 720.0) % 360.0

    $speed = $(if ($p.Sneaking) { $script:SNEAK_SPEED } elseif ($p.Running) { $script:RUN_SPEED } else { $script:WALK_SPEED }) * $Tics
    $rad = $p.Angle * [Math]::PI / 180.0
    $fx = [Math]::Cos($rad); $fy = - [Math]::Sin($rad)          # y grows southwards
    $fwd = $In.Forward; if ($fwd -lt 0) { $fwd *= $script:BACK_FACTOR }
    $dx = ($fx * $fwd - $fy * $In.Strafe) * $speed
    $dy = ($fy * $fwd + $fx * $In.Strafe) * $speed
    if ($dx -ne 0 -or $dy -ne 0) {
        Move-Player $dx $dy
        $steps = if ($p.Sneaking) { 0.0 } elseif ($p.Running) { $script:NOISE_RUN } else { $script:NOISE_WALK }
        if ($steps -gt $script:StepNoise) { $script:StepNoise = $steps }
    }

    Update-Attack $Tics ([bool]$In.Fire)
    Update-Pickups

    # the face in the status bar glances around at random
    $p.FaceTimer += $Tics
    if ($p.GrinTics -gt 0) { $p.GrinTics -= $Tics; if ($p.GrinTics -le 0) { $script:HudDirty = $true } }
    if ($p.PainTics -gt 0) { $p.PainTics -= $Tics }
    if ($p.LookHold -gt 0) { $p.LookHold -= $Tics }
    $p.RageTics = if ($In.Fire -and $p.AttackFrame -ge 0) { [Math]::Min(200.0, $p.RageTics + $Tics) } else { [Math]::Max(0.0, $p.RageTics - 3 * $Tics) }      # holding the trigger
    if ($p.FaceTimer -gt (Get-Rnd)) { $p.FaceTimer = 0; $look = $script:Rng.Next(3) - 1; if ($p.LookHold -le 0) { $p.FaceLook = $look } }
    if ((Get-FaceKey) -ne $p.FaceKey) { $script:HudDirty = $true }
}
