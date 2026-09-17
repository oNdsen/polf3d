# POLF 3D - Copyright (c) 2026 oNdsen. Licensed under the MIT License, see LICENSE.

# Network.ps1 - two players over TCP: co-op through the campaign, or a one-on-one duel.
#
#   ./Start-Polf3D.ps1 -HostGame Coop          (or Duel)      ... and on the other machine:
#   ./Start-Polf3D.ps1 -JoinGame <address of the host>
#
# The HOST owns the world: doors, push-walls, enemies, barrels, projectiles. Several times a second
# it sends what has changed (a snapshot). The CLIENT simulates only its own player; whatever it does
# to the world - shooting somebody, pressing "use", firing a rocket - is sent to the host as a request.
# Both sides tell each other every frame where their player is, and show him as a sprite: the "ghost".
#
# For the enemies on the host to fight two players, the host can step into the PEER CONTEXT: for the
# duration of one actor's update $script:P is swapped for a stand-in of the remote player (the
# "proxy"), and the ghost sprite is moved to where the host's own player stands. All the existing
# code that says "the player" then simply means the other one; damage done to "the player" is sent
# over the wire instead of being applied.
#
# The protocol is lines of text, fields separated by "|":
#   V version/mode   G start a floor   R client is ready   M my player   Z snapshot   B back to the title
#   D damage an actor   U use   P fire a projectile   H you are hit   F you got the frag   S score for you
#   I item taken   J item is back   A item added   T tile changed   W push-wall started
#   Q sound   X message   L floor completed

$script:NET_VERSION = 1
$script:Net = $null               # $null = single player
$script:NetLive = $false          # a floor is being played together right now
$script:NetClient = $false        # ... and this side is the client
$script:NetAsPeer = $false        # host only: inside the peer context
$script:NetScope = 'local'        # who should hear sounds/messages: local | world (both) | peer (only him) | remote (received)
$script:NetFrame = 0

function New-IdleInput { @{ Forward = 0; Strafe = 0; Turn = 0; MouseTurn = 0.0; Run = $false; Sneak = $false; Fire = $false; Use = $false; Weapon = -1 } }

# ---------------------------------------------------------------------------------------------
# Connection
# ---------------------------------------------------------------------------------------------
function Initialize-Network([string]$Role, [string]$Mode, [string]$Address, [int]$Port) {
    $script:Net = @{
        Role = $Role; Mode = $Mode; Address = $Address; Port = $Port
        Listener = $null; Tcp = $null; Stream = $null; Pending = $null; Retry = 0.0
        Connected = $false; Status = ''; Received = 0
        In = [System.Text.StringBuilder]::new(); Out = [System.Text.StringBuilder]::new()
        Bytes = [byte[]]::new(16384); Chars = [char[]]::new(16384); Decoder = [System.Text.Encoding]::UTF8.GetDecoder()
        Serial = 0; PeerReady = $false
        Ghost = $null; Proxy = $null; Home = $null; Anim = $null
        Frags = 0; PeerFrags = 0; PeerHealth = 100; PeerNoise = $false; PeerStep = 0.0
        Sent = @{}; Final = [System.Collections.Generic.HashSet[int]]::new(); Gone = [System.Collections.Generic.List[int]]::new()
        ById = @{}; BaseIds = 0; DoorsSent = ''; StatsSent = ''; SnapTics = 0.0
        Spawns = @(); MySpot = $null; Respawns = [System.Collections.Generic.List[object]]::new()
    }
    # sounds of a player that the other one should hear as well
    $script:NetLoud = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($w in $script:Weapons) { if ($w.Snd) { $null = $script:NetLoud.Add($w.Snd) } }
    foreach ($s in 'knife', 'rocket', 'flame', 'shot_pipe', 'shot_force', 'pain', 'player_die', 'teleport') { $null = $script:NetLoud.Add($s) }
    if ($Role -eq 'host') {
        $script:Net.Listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Any, $Port)
        $script:Net.Listener.Start()
    }
}

function Stop-Network {
    $n = $script:Net
    if (-not $n) { return }
    foreach ($o in $n.Stream, $n.Tcp) { if ($o) { try { $o.Dispose() } catch { } } }
    if ($n.Listener) { try { $n.Listener.Stop() } catch { } }
    $script:Net = $null; $script:NetLive = $false; $script:NetClient = $false
}

# One line for the title screen.
function Get-NetStatus {
    $n = $script:Net
    if (-not $n) { return '' }
    $what = if ($n.Mode -eq 'duel') { '1 vs 1 duel' } else { 'co-op' }
    if ($n.Role -eq 'host') {
        if ($n.Connected) { return "NETWORK  $what - player 2 has joined - Enter starts the game" }
        return "NETWORK  hosting a $what game on port $($n.Port) - waiting for player 2 ...  $($n.Status)"
    }
    if ($n.Connected) { return "NETWORK  $what - connected to $($n.Address) - the host starts the game" }
    "NETWORK  looking for $($n.Address):$($n.Port) ...  $($n.Status)"
}

# May the game be started from the title screen? (In a network game only by the host, and only with a guest.)
function Test-NetStart { -not $script:Net -or ($script:Net.Role -eq 'host' -and $script:Net.Connected) }

function Connect-NetPeer {
    $n = $script:Net
    if ($n.Role -eq 'host') {
        if (-not $n.Listener.Pending()) { return }
        $n.Tcp = $n.Listener.AcceptTcpClient()
    }
    else {
        $now = $script:Clock.Elapsed.TotalSeconds
        if (-not $n.Pending) {
            if ($now -lt $n.Retry) { return }
            $n.Tcp = [System.Net.Sockets.TcpClient]::new()
            $n.Pending = $n.Tcp.ConnectAsync($n.Address, $n.Port)
        }
        if (-not $n.Pending.IsCompleted) { return }
        $failed = $n.Pending.IsFaulted -or $n.Pending.IsCanceled
        $n.Pending = $null
        if ($failed) { $n.Tcp.Dispose(); $n.Tcp = $null; $n.Retry = $now + 2.0; $n.Status = '(no answer yet)'; return }
    }
    $n.Tcp.NoDelay = $true; $n.Tcp.SendTimeout = 3000
    $n.Stream = $n.Tcp.GetStream()
    $null = $n.In.Clear(); $null = $n.Out.Clear()
    $n.Connected = $true; $n.Status = ''; $n.PeerReady = $false
    if ($n.Role -eq 'host') { Send-NetMessage "V|$($script:NET_VERSION)|$($n.Mode)" }
}

function Disconnect-NetPeer([string]$Why) {
    $n = $script:Net
    foreach ($o in $n.Stream, $n.Tcp) { if ($o) { try { $o.Dispose() } catch { } } }
    $n.Stream = $null; $n.Tcp = $null; $n.Pending = $null
    $n.Connected = $false; $n.PeerReady = $false
    $n.Retry = $script:Clock.Elapsed.TotalSeconds + 2.0
    $n.Status = "($Why)"
    $wasLive = $script:NetLive
    $script:NetLive = $false; $script:NetClient = $false; $script:NetAsPeer = $false; $script:NetScope = 'local'
    if ($wasLive -or $script:Mode -eq 'done') { Set-Mode 'title' }
}

function Send-NetMessage([string]$Line) {
    $n = $script:Net
    if ($n -and $n.Connected) { $null = $n.Out.Append($Line).Append("`n") }
}

function Send-NetQueue {
    $n = $script:Net
    if ($n.Out.Length -eq 0) { return }
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($n.Out.ToString())
    $null = $n.Out.Clear()
    $n.Stream.Write($bytes, 0, $bytes.Length)
}

function Receive-NetMessages {
    $n = $script:Net
    $socket = $n.Tcp.Client
    if ($socket.Poll(0, [System.Net.Sockets.SelectMode]::SelectRead) -and $socket.Available -eq 0) { throw 'the other player has left' }
    while ($n.Stream.DataAvailable) {
        $read = $n.Stream.Read($n.Bytes, 0, $n.Bytes.Length)
        if ($read -le 0) { throw 'the other player has left' }
        $count = $n.Decoder.GetChars($n.Bytes, 0, $read, $n.Chars, 0)
        $null = $n.In.Append($n.Chars, 0, $count)
    }
    if ($n.In.Length -eq 0) { return }
    $text = $n.In.ToString()
    $last = $text.LastIndexOf("`n")
    if ($last -lt 0) { return }
    $null = $n.In.Clear(); $null = $n.In.Append($text.Substring($last + 1))
    foreach ($line in $text.Substring(0, $last).Split("`n")) {
        if ($line) { $n.Received++; Invoke-NetMessage $line }
    }
}

# Once per frame, whatever the game mode.
function Update-Network([double]$Tics) {
    $n = $script:Net
    if (-not $n) { return }
    try {
        if (-not $n.Connected) { Connect-NetPeer; if (-not $n.Connected) { return } }
        Receive-NetMessages
        if ($script:NetLive) {
            Send-NetPlayerState
            if (-not $script:NetClient -and $n.PeerReady) {
                $n.SnapTics += $Tics
                if ($n.SnapTics -ge 3.5) { $n.SnapTics = 0.0; Send-NetSnapshot }
                Update-NetRespawns
            }
        }
        Send-NetQueue
    }
    catch {
        $e = $_.Exception
        while ($e.InnerException) { $e = $e.InnerException }
        Disconnect-NetPeer $(if ($e -is [System.Net.Sockets.SocketException] -or $e -is [System.IO.IOException]) { 'the connection was lost' } else { $e.Message })
    }
}

# ---------------------------------------------------------------------------------------------
# Starting a floor together
# ---------------------------------------------------------------------------------------------
function Get-MapHash([string]$Path) {
    $text = (Get-Content -LiteralPath $Path -Raw) -replace "`r", ''
    [BitConverter]::ToString([System.Security.Cryptography.SHA1]::HashData([System.Text.Encoding]::UTF8.GetBytes($text))).Replace('-', '').Substring(0, 8)
}

# The free floor tile nearest to (X,Y) that is not that tile itself: where the guest starts in co-op.
function Find-NetFreeSpot([double]$X, [double]$Y) {
    $cx = [int][Math]::Floor($X); $cy = [int][Math]::Floor($Y); $w = $script:MapW
    foreach ($r in 1..4) {
        for ($dy = - $r; $dy -le $r; $dy++) {
            for ($dx = - $r; $dx -le $r; $dx++) {
                if ([Math]::Max([Math]::Abs($dx), [Math]::Abs($dy)) -ne $r) { continue }
                $tx = $cx + $dx; $ty = $cy + $dy
                if ($tx -lt 1 -or $ty -lt 1 -or $tx -ge $w - 1 -or $ty -ge $script:MapH - 1) { continue }
                $idx = $ty * $w + $tx
                if ($script:Tiles[$idx] -eq 0 -and -not $script:StaticBlock[$idx] -and $null -eq $script:ActorAt[$idx] -and
                    $script:AreaOf[$idx] -eq $script:AreaOf[$cy * $w + $cx]) { return @(($tx + 0.5), ($ty + 0.5)) }
            }
        }
    }
    @($X, $Y)
}

# The spawn spot farthest away from (X,Y); with $Pick > 1 a random one of the $Pick farthest.
function Find-NetSpawn([double]$X, [double]$Y, [int]$Pick = 1) {
    $far = @($script:Net.Spawns | Sort-Object { - ([Math]::Abs($_[0] - $X) + [Math]::Abs($_[1] - $Y)) } | Select-Object -First $Pick)
    $far[$script:FxRng.Next($far.Count)]
}

function Move-NetPlayer([double]$X, [double]$Y) {
    $p = $script:P
    $p.X = $X; $p.Y = $Y
    $p.Area = $script:AreaOf[[int][Math]::Floor($Y) * $script:MapW + [int][Math]::Floor($X)]
    Update-AreaByPlayer
}

function Set-NetDuelKit {
    $p = $script:P
    $p.Owned[2] = $true; $p.Ammo = 40; $p.Weapon = 2; $p.ChosenWeapon = 2
    $script:HudDirty = $true
}

# Called by Start-Level on both sides once the map is loaded (from the same file with the same seed,
# so both start with identical actors that carry identical ids).
function Initialize-NetLevel([bool]$KeepPlayer, [bool]$KeepKit) {
    $n = $script:Net; $w = $script:MapW
    $isHost = $n.Role -eq 'host'
    $spots = [System.Collections.Generic.List[object]]::new()
    $spots.Add(@($script:StartX, $script:StartY))

    if ($n.Mode -eq 'duel') {
        # no monsters in a duel - but where they stood is where the players respawn
        for ($i = $script:Actors.Count - 1; $i -ge 0; $i--) {
            $a = $script:Actors[$i]
            if ($a.Def.Inert) { continue }
            $spots.Add(@(([Math]::Floor($a.X) + 0.5), ([Math]::Floor($a.Y) + 0.5)))
            $idx = $a.TY * $w + $a.TX
            if ($script:ActorAt[$idx] -eq $a) { $script:ActorAt[$idx] = $null }
            $script:Actors.RemoveAt($i)
        }
        $script:Stats.KillTotal = 0
        foreach ($d in $script:Doors) { if ($d.Lock -in 1, 2) { $d.Lock = 0; $d.TexId = $script:TEX_DOOR } }      # nobody is left to drop a key
        if (-not $KeepKit) { Set-NetDuelKit }
        if (-not $KeepPlayer) { $n.Frags = 0; $n.PeerFrags = 0 }
    }
    $n.Spawns = $spots.ToArray()

    $hostSpot = @($script:StartX, $script:StartY)
    $guestSpot = if ($n.Mode -eq 'duel') { Find-NetSpawn $script:StartX $script:StartY } else { Find-NetFreeSpot $script:StartX $script:StartY }
    $mine, $his = if ($isHost) { $hostSpot, $guestSpot } else { $guestSpot, $hostSpot }
    $n.MySpot = $mine
    Move-NetPlayer $mine[0] $mine[1]

    # the other player: a sprite here ...
    $g = [Actor]::new()
    $g.Kind = 'peer'; $g.Def = $script:MiscDefs.peer; $g.State = 'peer.stand'
    $g.X = $his[0]; $g.Y = $his[1]; $g.NX = $g.X; $g.NY = $g.Y
    $g.TX = [int][Math]::Floor($g.X); $g.TY = [int][Math]::Floor($g.Y)
    $g.Dir = [int]($script:StartAngle / 45.0) % 8
    $g.Area = $script:AreaOf[$g.TY * $w + $g.TX]
    $g.Shootable = $true; $g.Active = $true
    $script:Actors.Add($g)
    $n.Ghost = $g
    $n.Anim = @{ Fire = 0.0; Pain = 0.0; Walk = 0.0; Still = 99.0; Dead = $false; Die = 0.0 }

    # ... and, on the host, a stand-in for $script:P while the enemies deal with him
    $me = $script:P
    New-Player
    $n.Proxy = $script:P
    $script:P = $me
    $n.Proxy.X = $g.X; $n.Proxy.Y = $g.Y; $n.Proxy.Area = $g.Area; $n.Proxy.Angle = $script:StartAngle
    $n.Home = $me

    $n.ById = @{}
    foreach ($a in $script:Actors) { if ($a.NetId -gt 0) { $n.ById[$a.NetId] = $a } }
    $n.BaseIds = $script:NextNetId
    $n.Sent = @{}; $n.Final.Clear(); $n.Gone.Clear(); $n.Respawns.Clear()
    $n.DoorsSent = ''; $n.StatsSent = ''; $n.SnapTics = 0.0
    $n.PeerHealth = 100; $n.PeerNoise = $false; $n.PeerStep = 0.0
    $me.RunInvalid = $true                                        # no speedrun records from network games

    if ($isHost) {
        $n.Serial++; $n.PeerReady = $false
        $bonus = if ($script:BonusMap) { Split-Path $script:BonusMap -Leaf } else { '' }
        Send-NetMessage "G|$($n.Serial)|$($script:LevelIndex)|$bonus|$($script:Difficulty)|$($script:LevelSeed)|$([int]$KeepPlayer)|$([int]$KeepKit)|$(Get-MapHash $script:MapFile)"
    }
    else { Send-NetMessage "R|$($n.Serial)" }
    $script:NetLive = $true; $script:NetClient = -not $isHost
    $script:NetAsPeer = $false; $script:NetScope = 'local'
    Update-AreaByPlayer
}

# Back on his feet after a death: no lives in a network game, the floor goes on.
function Reset-NetPlayer {
    $n = $script:Net; $p = $script:P
    Reset-PlayerKit
    if ($n.Mode -eq 'duel') { Set-NetDuelKit; $spot = Find-NetSpawn $n.Ghost.NX $n.Ghost.NY 3 } else { $spot = $n.MySpot }
    $p.AttackFrame = -1; $p.WeaponFrame = 0; $p.UseHeld = $true; $p.FireHeld = $true
    $p.Angle = $script:StartAngle
    Move-NetPlayer $spot[0] $spot[1]
    Reset-ScreenEffects
    $script:PlayerDied = $false; $script:Killer = $null; $script:ShowWeapon = $true; $script:HudDirty = $true
}

# ---------------------------------------------------------------------------------------------
# The peer context (host only)
# ---------------------------------------------------------------------------------------------
function Enter-PeerContext {
    $n = $script:Net; $g = $n.Ghost
    $n.Home = $script:P; $n.HomeStep = $script:StepNoise
    $n.GhostX = $g.X; $n.GhostY = $g.Y
    $g.X = $n.Home.X; $g.Y = $n.Home.Y                          # the ghost stands in for the host's own player
    $n.Proxy.KeyGold = $n.Home.KeyGold; $n.Proxy.KeySilver = $n.Home.KeySilver      # keys are shared
    $script:P = $n.Proxy
    $script:StepNoise = $n.PeerStep
    $script:NetAsPeer = $true
}

function Exit-PeerContext {
    $n = $script:Net; $g = $n.Ghost
    $n.PeerStep = $script:StepNoise
    $script:P = $n.Home; $script:StepNoise = $n.HomeStep
    $g.X = $n.GhostX; $g.Y = $n.GhostY
    $script:NetAsPeer = $false
}

# Runs something the remote player asked for: as him, and with sounds and messages going to him only.
function Invoke-InPeerContext([scriptblock]$NetAction) {
    Enter-PeerContext
    $script:NetScope = 'peer'
    try { & $NetAction } finally { $script:NetScope = 'local'; Exit-PeerContext }
}

# Should this actor deal with the remote player this frame (instead of the host's own)?
function Test-PeerTarget([Actor]$a) {
    if ($a.FromPeer) { return $true }
    $n = $script:Net
    if ($n.Mode -ne 'coop' -or $a.Kind -eq 'peer' -or $a.Def.Inert) { return $false }
    if ($a.Corpse -and $a.Kind -ne 'rocket') { return $false }
    $his = $n.Proxy; $mine = $script:P
    if ($his.Health -le 0) { return $false }
    if ($mine.Health -le 0) { return $true }
    if (-not $a.AttackMode) { return ($script:NetFrame % 2) -eq 1 }          # not alerted yet: look out for both in turn
    ([Math]::Abs($his.X - $a.X) + [Math]::Abs($his.Y - $a.Y)) -lt ([Math]::Abs($mine.X - $a.X) + [Math]::Abs($mine.Y - $a.Y))
}

# Host: an explosion also reaches the player who is not "$script:P" at the moment.
function Invoke-NetBlast([double]$X, [double]$Y, [double]$Radius, [double]$Damage, [Actor]$Owner) {
    $n = $script:Net
    $other = if ($script:NetAsPeer) { $n.Home } else { $n.Proxy }
    $dx = $other.X - $X; $dy = $other.Y - $Y
    $d = [Math]::Sqrt($dx * $dx + $dy * $dy)
    if ($d -ge $Radius -or $other.Health -le 0) { return }
    $points = [int]($Damage * 0.6 * (1 - $d / $Radius))
    if ($script:NetAsPeer) {
        $blamed = if ($script:NetBlastByPlayer) { $n.Ghost } else { $Owner }
        $scope = $script:NetScope
        Exit-PeerContext; $script:NetScope = 'local'
        try { Invoke-PlayerDamage $points $blamed } finally { $script:NetScope = $scope; Enter-PeerContext }
    }
    else { Send-NetMessage "H|$points|$(if ($script:NetBlastByPlayer) { 'P' } elseif ($Owner) { $Owner.NetId } else { 0 })" }
}

# Somebody hit the ghost. Only in a duel does that hurt - and never by an explosion (see Invoke-NetBlast).
function Invoke-PeerDamage([Actor]$Ghost, [int]$Damage, [string]$Source) {
    $n = $script:Net
    if ($n.Mode -ne 'duel' -or $Source -eq 'explosion' -or $Damage -le 0) { return }
    if ($script:NetAsPeer) {
        # here the ghost stands in for the host's own player: the guest's knife or rocket has found him
        $scope = $script:NetScope
        Exit-PeerContext; $script:NetScope = 'local'
        try { Invoke-PlayerDamage $Damage $n.Ghost } finally { $script:NetScope = $scope; Enter-PeerContext }
        return
    }
    if ($script:P.SudoTics -gt 0) { $Damage *= 2 }
    Add-HitEffect $Ghost
    Send-NetMessage "H|$Damage|P"
}

# ---------------------------------------------------------------------------------------------
# Every frame: my player -> the other side; the ghost's animation
# ---------------------------------------------------------------------------------------------
function Send-NetPlayerState {
    $p = $script:P
    $flags = [int]$p.Running + 2 * [int]$p.Sneaking + 4 * [int][bool]$script:MadeNoise + 8 * [int]($p.Health -le 0) + 16 * [int]($p.SudoTics -gt 0)
    Send-NetMessage "M|$([Math]::Round($p.X, 3))|$([Math]::Round($p.Y, 3))|$([Math]::Round($p.Angle, 1))|$flags|$($p.Health)|$($script:StepNoise)|$($p.Area)"
}

function Update-NetGhost([double]$Tics) {
    $n = $script:Net; $g = $n.Ghost; $an = $n.Anim
    if (-not $g) { return }
    $dx = $g.NX - $g.X; $dy = $g.NY - $g.Y
    $moved = 0.0
    if ([Math]::Abs($dx) + [Math]::Abs($dy) -gt 2.5) { $g.X = $g.NX; $g.Y = $g.NY }        # teleporter or respawn
    else {
        $k = [Math]::Min(1.0, $Tics * 0.35)
        $g.X += $dx * $k; $g.Y += $dy * $k
        $moved = [Math]::Sqrt($dx * $dx + $dy * $dy) * $k
    }
    $tx = [int][Math]::Floor($g.X); $ty = [int][Math]::Floor($g.Y)
    if ($tx -ne $g.TX -or $ty -ne $g.TY) {
        $old = $g.TY * $script:MapW + $g.TX
        if ($script:ActorAt[$old] -eq $g) { $script:ActorAt[$old] = $null }
        $g.TX = $tx; $g.TY = $ty
        $area = $script:AreaOf[$ty * $script:MapW + $tx]
        if ($area -ge 0) { $g.Area = $area }
    }
    if ($an.Dead) {
        $an.Die += $Tics
        $g.State = if ($an.Die -lt 9) { 'peer.die1' } elseif ($an.Die -lt 18) { 'peer.die2' } elseif ($an.Die -lt 27) { 'peer.die3' } else { 'peer.dead' }
        return
    }
    if ($an.Fire -gt 0) { $an.Fire -= $Tics; $g.State = 'peer.fire'; return }
    if ($an.Pain -gt 0) { $an.Pain -= $Tics; $g.State = 'peer.pain'; return }
    if ($moved -gt 0.003) {
        $an.Walk += $moved; $an.Still = 0.0
        $g.State = "peer.w$(1 + [int][Math]::Floor($an.Walk * 2.4) % 4)"
    }
    else {
        $an.Still += $Tics
        if ($an.Still -gt 8) { $g.State = 'peer.stand' }
    }
}

# ---------------------------------------------------------------------------------------------
# Host -> client: what has changed in the world
# ---------------------------------------------------------------------------------------------
function Send-NetSnapshot {
    $n = $script:Net
    $sb = [System.Text.StringBuilder]::new()
    foreach ($a in $script:Actors) {
        $id = $a.NetId
        if ($id -le 0 -or $n.Final.Contains($id)) { continue }
        $flags = [int]$a.Shootable + 2 * [int]$a.AttackMode + 4 * [int]$a.Corpse + 8 * [int]($a.AlertTics -gt 0) + 16 * [int]($a.React -gt 0)
        $entry = "$($a.State),$([Math]::Round($a.X, 2)),$([Math]::Round($a.Y, 2)),$($a.Dir),$flags"
        if ($n.Sent[$id] -eq $entry) { continue }
        $n.Sent[$id] = $entry
        if ($a.Corpse -and $a.State.EndsWith('.dead')) { $null = $n.Final.Add($id) }       # nothing will ever change again
        if ($sb.Length) { $null = $sb.Append(';') }
        $null = $sb.Append($id).Append(',').Append($entry)
    }
    $doors = @(foreach ($d in $script:Doors) { [int]($d.Open * 100) * 8 + (@('closed', 'opening', 'open', 'closing').IndexOf($d.Action)) * 2 + [int]$d.Unlocked }) -join ','
    $doorPart = if ($doors -ne $n.DoorsSent) { $n.DoorsSent = $doors; $doors } else { '' }
    $st = $script:Stats
    $stats = "$($st.Kills)|$($st.Secrets)|$($st.Treasures)"
    $gone = $n.Gone -join ','
    $n.Gone.Clear()
    if ($sb.Length -eq 0 -and -not $doorPart -and -not $gone -and $stats -eq $n.StatsSent) { return }
    $n.StatsSent = $stats
    Send-NetMessage "Z|$stats|$doorPart|$($sb.ToString())|$gone"
}

# Duel: what has been picked up comes back after a while. The host keeps the clock.
function Update-NetRespawns {
    $n = $script:Net
    if ($n.Respawns.Count -eq 0) { return }
    $now = $script:Stats.Tics
    for ($i = $n.Respawns.Count - 1; $i -ge 0; $i--) {
        $r = $n.Respawns[$i]
        if ($now -lt $r.At) { continue }
        $script:Items[$r.Index].Removed = $false
        Send-NetMessage "J|$($r.Index)"
        $n.Respawns.RemoveAt($i)
    }
}

# An item has been taken (by whom does not matter). Called on the side that picked it up and, through
# the I message, on the other one.
function Register-NetPickup([int]$Index, [bool]$Mine) {
    $n = $script:Net
    if ($Mine) { Send-NetMessage "I|$Index" }
    else {
        $s = $script:Items[$Index]
        $s.Removed = $true
        switch ($s.Item) {
            'key_gold'   { $script:P.KeyGold = $true; Show-Message 'Your partner found the gold key'; $script:HudDirty = $true }
            'key_silver' { $script:P.KeySilver = $true; Show-Message 'Your partner found the silver key'; $script:HudDirty = $true }
            default      { if ($s.Item -in $script:TreasureItems -and -not $script:NetClient) { $script:Stats.Treasures++ } }
        }
    }
    if ($n.Mode -eq 'duel' -and -not $script:NetClient) { $n.Respawns.Add(@{ Index = $Index; At = $script:Stats.Tics + 70 * 25 }) }
}

function Get-NetActor([int]$Id) {
    if ($Id -le 0) { return $null }
    if ($script:NetClient) { return $script:Net.ById[$Id] }
    foreach ($a in $script:Actors) { if ($a.NetId -eq $Id) { return $a } }
    $null
}

# ---------------------------------------------------------------------------------------------
# Client: the actors are puppets, moved by the snapshots
# ---------------------------------------------------------------------------------------------
function Update-ClientActors([double]$Tics) {
    $k = [Math]::Min(1.0, $Tics * 0.35)
    foreach ($a in $script:Actors) {
        if ($a.NetId -gt 0) {
            $dx = $a.NX - $a.X; $dy = $a.NY - $a.Y
            if ([Math]::Abs($dx) + [Math]::Abs($dy) -gt 2.5) { $a.X = $a.NX; $a.Y = $a.NY } else { $a.X += $dx * $k; $a.Y += $dy * $k }
            $a.TX = [int][Math]::Floor($a.X); $a.TY = [int][Math]::Floor($a.Y)
        }
        elseif ($a.Kind -ne 'peer') { Update-Actor $a $Tics }      # effects born here (sparks, flames) live here
    }
    if ($script:NewActors.Count) {
        foreach ($new in $script:NewActors) { $script:Actors.Add($new) }
        $script:NewActors.Clear()
    }
    for ($i = $script:Actors.Count - 1; $i -ge 0; $i--) {
        if ($script:Actors[$i].State -eq 'gone') { $script:Actors.RemoveAt($i) }
    }
}

function Import-NetSnapshot([string[]]$f) {
    $n = $script:Net; $st = $script:Stats
    $st.Kills = [int]$f[1]; $st.Secrets = [int]$f[2]; $st.Treasures = [Math]::Max($st.Treasures, [int]$f[3])
    if ($f[4]) {
        $values = $f[4].Split(','); $actions = 'closed', 'opening', 'open', 'closing'
        for ($i = 0; $i -lt $values.Count -and $i -lt $script:Doors.Count; $i++) {
            $v = [int]$values[$i]; $d = $script:Doors[$i]
            $d.Unlocked = [bool]($v -band 1); $d.Action = $actions[($v -shr 1) -band 3]; $d.Open = ($v -shr 3) / 100.0
        }
    }
    if ($f[5]) {
        foreach ($entry in $f[5].Split(';')) {
            $e = $entry.Split(',')
            $id = [int]$e[0]; $state = $e[1]
            if (-not $script:States.ContainsKey($state)) { continue }
            $a = $n.ById[$id]
            if (-not $a) {
                $kind = $state.Substring(0, $state.IndexOf('.'))
                $a = [Actor]::new()
                $a.Kind = $kind; $a.NetId = $id
                $a.Def = if ($script:EnemyDefs.ContainsKey($kind)) { $script:EnemyDefs[$kind] } else { $script:MiscDefs[$kind] }
                $a.X = [double]$e[2]; $a.Y = [double]$e[3]
                $a.Active = $true; $a.Area = $script:P.Area
                $script:Actors.Add($a); $n.ById[$id] = $a
            }
            $a.State = $state
            $a.NX = [double]$e[2]; $a.NY = [double]$e[3]; $a.Dir = [int]$e[4]
            $flags = [int]$e[5]
            $a.Shootable = [bool]($flags -band 1); $a.AttackMode = [bool]($flags -band 2); $a.Corpse = [bool]($flags -band 4)
            $a.AlertTics = if ($flags -band 8) { 10 } else { 0 }
            $a.React = if ($flags -band 16) { 1 } else { 0 }
        }
    }
    if ($f.Count -gt 6 -and $f[6]) {
        foreach ($id in $f[6].Split(',')) {
            $a = $n.ById[[int]$id]
            if ($a) { $null = $script:Actors.Remove($a); $n.ById.Remove([int]$id) }
        }
    }
}

# ---------------------------------------------------------------------------------------------
# Incoming messages
# ---------------------------------------------------------------------------------------------
function Invoke-NetMessage([string]$Line) {
    $n = $script:Net
    $f = $Line.Split('|')
    $isHost = $n.Role -eq 'host'
    # whatever refers to the floor in play is worthless before the guest has loaded it (or after it is over)
    if ($f[0] -cin 'M', 'Z', 'D', 'U', 'P', 'H', 'F', 'S', 'I', 'J', 'A', 'T', 'W', 'Q', 'X', 'L') {
        if (-not $script:NetLive) { return }
        if ($isHost -and -not $n.PeerReady) { return }
    }
    switch -CaseSensitive ($f[0]) {
        'V' {
            if ([int]$f[1] -ne $script:NET_VERSION) { throw "the other side speaks protocol version $($f[1]), this one $($script:NET_VERSION)" }
            if (-not $isHost) { $n.Mode = $f[2]; Send-NetMessage "V|$($script:NET_VERSION)" }
        }
        'G' {
            if ($isHost) { break }
            if ([int]$f[2] -ge $script:MapFiles.Count) { throw "the host plays floor $([int]$f[2] + 1), which this copy of the game does not have" }
            $n.Serial = [int]$f[1]
            $script:LevelIndex = [int]$f[2]
            $script:BonusMap = if ($f[3]) { Join-Path (Split-Path $script:MapFiles[$script:LevelIndex]) $f[3] } else { $null }
            $script:Difficulty = [int]$f[4]; $script:NextSeed = [int]$f[5]
            $keepPlayer = $f[6] -eq '1' -and $null -ne $script:P
            Start-Level $keepPlayer ($keepPlayer -and $f[7] -eq '1')
            Set-Mode 'play'
            if ((Get-MapHash $script:MapFile) -ne $f[8]) { Show-Message 'WARNING: your copy of this map differs from the host''s' }
        }
        'R' { if ($isHost -and [int]$f[1] -eq $n.Serial) { $n.PeerReady = $true } }
        'M' {
            $g = $n.Ghost; $an = $n.Anim
            $g.NX = [double]$f[1]; $g.NY = [double]$f[2]
            $g.Dir = [int][Math]::Round([double]$f[3] / 45.0) % 8
            $flags = [int]$f[4]; $health = [int]$f[5]
            $dead = [bool]($flags -band 8)
            if ($dead -and -not $an.Dead) {
                $an.Dead = $true; $an.Die = 0.0
                $g.Shootable = $false; $g.Corpse = $true
                $idx = $g.TY * $script:MapW + $g.TX
                if ($script:ActorAt[$idx] -eq $g) { $script:ActorAt[$idx] = $null }
            }
            elseif (-not $dead -and $an.Dead) {
                $an.Dead = $false; $g.Shootable = $true; $g.Corpse = $false; $g.State = 'peer.stand'
                $g.X = $g.NX; $g.Y = $g.NY
            }
            if ($health -lt $n.PeerHealth -and -not $dead) { $an.Pain = 8.0 }
            if ($health -ne $n.PeerHealth) { $script:HudDirty = $true }
            $n.PeerHealth = $health
            if ($isHost) {
                $px = $n.Proxy
                $px.X = $g.NX; $px.Y = $g.NY; $px.Angle = [double]$f[3]; $px.Health = $health
                $px.Running = [bool]($flags -band 1); $px.Sneaking = [bool]($flags -band 2)
                $px.SudoTics = if ($flags -band 16) { 1.0 } else { 0.0 }
                if ($flags -band 4) { $n.PeerNoise = $true }
                $n.PeerStep = [double]$f[6]
                $area = [int]$f[7]
                if ($area -ge 0 -and $area -ne $px.Area) { $px.Area = $area; Update-AreaByPlayer }
            }
        }
        'Z' { if (-not $isHost) { Import-NetSnapshot $f } }
        'D' {
            if (-not $isHost) { break }
            $target = Get-NetActor ([int]$f[1])
            if ($target -and $target.Shootable) { Invoke-InPeerContext { Invoke-ActorDamage $target ([int]$f[2]) $f[3] } }
        }
        'U' { if ($isHost) { Invoke-InPeerContext { Invoke-UseAt ([int]$f[1]) ([int]$f[2]) ([int]$f[3]) ([int]$f[4]) } } }
        'P' {
            if (-not $isHost -or $f[1] -notin 'procket', 'tknife') { break }
            $px = $n.Proxy; $px.X = [double]$f[2]; $px.Y = [double]$f[3]; $px.Angle = [double]$f[4]
            Invoke-InPeerContext { Add-PlayerProjectile $f[1] }
            $script:NewActors[$script:NewActors.Count - 1].FromPeer = $true
        }
        'H' {
            $attacker = if ($f[2] -eq 'P') { $n.Ghost } else { Get-NetActor ([int]$f[2]) }
            Invoke-PlayerDamage ([int]$f[1]) $attacker
        }
        'F' { $n.Frags++; Show-Message 'You got him!'; $script:HudDirty = $true }
        'S' { Add-Score ([int]$f[1]) }
        'I' { $i = [int]$f[1]; if ($i -ge 0 -and $i -lt $script:Items.Count) { Register-NetPickup $i $false } }
        'J' { $i = [int]$f[1]; if ($i -ge 0 -and $i -lt $script:Items.Count) { $script:Items[$i].Removed = $false } }
        'A' { if (-not $isHost) { Add-Item $f[1] ([int]$f[2]) ([int]$f[3]) } }
        'T' {
            if ($isHost) { break }
            $idx = [int]$f[1]
            $script:Tiles[$idx] = [int]$f[2]
            if ([int]$f[2] -eq 0) { $script:Breakable[$idx] = $false }
            $script:MapBmp = $null
        }
        'W' { if (-not $isHost) { Start-PushWall ([int]$f[1]) ([int]$f[2]) ([int]$f[3]) ([int]$f[4]) } }
        'Q' {
            $script:NetScope = 'remote'
            try { Start-Sfx $f[1] } finally { $script:NetScope = 'local' }
            if ($script:NetLoud.Contains($f[1]) -and $f[1] -notin 'pain', 'player_die', 'teleport') { $n.Anim.Fire = 8.0 }
        }
        'X' {
            $script:NetScope = 'remote'
            try { Show-Message ($f[1..($f.Count - 1)] -join '|') } finally { $script:NetScope = 'local' }
        }
        'L' {
            if ($isHost) { break }
            $script:SecretExit = $f[1] -eq '1'
            if ($script:Mode -in 'play', 'paused', 'dying') { Complete-Level }
        }
        'B' { if ($script:Mode -ne 'title') { $script:NetLive = $false; $script:NetClient = $false; Set-Mode 'title' } }
    }
}
