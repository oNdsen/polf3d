# POLF 3D - Copyright (c) 2026 oNdsen. Licensed under the MIT License, see LICENSE.

# Network.ps1 - up to four players over TCP: co-op through the campaign, or a deathmatch.
#
#   ./Start-Polf3D.ps1 -HostGame Coop          (or Duel / Deathmatch)      ... and on the other machines:
#   ./Start-Polf3D.ps1 -JoinGame <address of the host> -PlayerName Anna
#
# A star: every guest talks to the HOST only. The host owns the world - doors, push-walls, enemies,
# barrels, projectiles - and several times a second sends everybody what has changed (a snapshot). A
# GUEST simulates only its own player; whatever it does to the world - shooting somebody, pressing
# "use", firing a rocket - is sent to the host as a request. Every player tells the host every frame
# where he is, the host passes that on, and everybody shows the others as sprites: the "ghosts".
# Players have slots: 0 is the host, 1..3 the guests, each with a coat of its own colour.
#
# For the enemies on the host to fight several players, the host can step into a PEER CONTEXT: for the
# duration of one actor's update $script:P is swapped for a stand-in of one remote player (his "proxy"),
# and that player's ghost is moved to where the host's own player stands. All the existing code that
# says "the player" then simply means that guest; damage done to "the player" goes over the wire.
#
# The host can throw people out: F1 opens the player list - K kicks, B bans the address (kept in
# saves/banned.json), U lifts a ban. A guest who was kicked or refused does not come back by himself.
#
# The protocol is lines of text, fields separated by "|". <s> is a slot.
#   host -> guest   V version|mode|your slot      N refused or kicked: why      G start a floor (with the roster)
#                   Z snapshot   M <s> a player's state   O <s> has left   C frags   H you are hit   S score for you
#                   I item taken   J item is back   A item added   T tile changed   W push-wall started
#                   Q <s> sound   X message   L floor completed   B back to the title
#   guest -> host   V version|name   R ready   M my state   D damage an actor   K I hit player <s>   F <s> killed me
#                   U use   P fire a projectile   I item taken   Q sound   B I am leaving the floor

$script:NET_VERSION = 2
$script:Net = $null               # $null = single player
$script:NetLive = $false          # a floor is being played together right now
$script:NetClient = $false        # ... and this side is a guest
$script:NetAsPeer = $false        # host only: inside a peer context
$script:NetScope = 'local'        # who should hear sounds/messages: local | world (all) | peer (only him) | remote (received)
$script:NetFrame = 0

function New-IdleInput { @{ Forward = 0; Strafe = 0; Turn = 0; MouseTurn = 0.0; Run = $false; Sneak = $false; Fire = $false; Use = $false; Weapon = -1 } }

function Get-NetSafeName([string]$Name, [string]$Default) {
    $clean = ($Name -replace '[^A-Za-z0-9_ \-]', '').Trim()
    if ($clean.Length -gt 12) { $clean = $clean.Substring(0, 12) }
    if ($clean) { $clean } else { $Default }
}

# ---------------------------------------------------------------------------------------------
# Setting up
# ---------------------------------------------------------------------------------------------
function Initialize-Network([string]$Role, [string]$Mode, [string]$Address, [int]$Port, [int]$MaxPlayers = 4, [string]$Name = '') {
    $script:Net = @{
        Role = $Role; Mode = $Mode; Address = $Address; Port = $Port; MaxPlayers = [Math]::Max(2, [Math]::Min(4, $MaxPlayers))
        Name = Get-NetSafeName $Name $(if ($Role -eq 'host') { 'Host' } else { 'Guest' }); Slot = 0
        # a guest's one connection
        Tcp = $null; Stream = $null; Pending = $null; Retry = 0.0; Refused = $false
        In = [System.Text.StringBuilder]::new(); Out = [System.Text.StringBuilder]::new(); Decoder = [System.Text.Encoding]::UTF8.GetDecoder()
        Bytes = [byte[]]::new(16384); Chars = [char[]]::new(16384)
        # the host's connections
        Listener = $null; Guests = [System.Collections.Generic.List[hashtable]]::new(); Bans = [System.Collections.Generic.List[string]]::new()
        Connected = $false; Status = ''; Received = 0
        # the floor in play
        Serial = 0; Roster = @(); Players = @{}; Names = @{}; Frags = @{}; Ctx = 0; Home = $null
        Sent = @{}; Final = [System.Collections.Generic.HashSet[int]]::new(); Gone = [System.Collections.Generic.List[int]]::new()
        ById = @{}; BaseIds = 0; DoorsSent = ''; StatsSent = ''; SnapTics = 0.0
        Spawns = @(); MySpot = $null; Respawns = [System.Collections.Generic.List[object]]::new()
        Panel = @{ Row = 0; Return = 'title' }
    }
    # sounds of a player that the others should hear as well
    $script:NetLoud = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($w in $script:Weapons) { if ($w.Snd) { $null = $script:NetLoud.Add($w.Snd) } }
    foreach ($s in 'knife', 'rocket', 'flame', 'shot_pipe', 'shot_force', 'pain', 'player_die', 'teleport') { $null = $script:NetLoud.Add($s) }
    # the other players: one coat per slot (painted now - a single player game never needs them)
    foreach ($slot in 0..3) { if (-not $script:Spr["peer$slot.s"]) { Add-SoldierSprites "peer$slot" } }
    if ($Role -eq 'host') {
        Import-NetBans
        $script:Net.Listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Any, $Port)
        $script:Net.Listener.Start()
    }
}

function Stop-Network {
    $n = $script:Net
    if (-not $n) { return }
    foreach ($g in @($n.Guests)) { foreach ($o in $g.Stream, $g.Tcp) { if ($o) { try { $o.Dispose() } catch { } } } }
    foreach ($o in $n.Stream, $n.Tcp) { if ($o) { try { $o.Dispose() } catch { } } }
    if ($n.Listener) { try { $n.Listener.Stop() } catch { } }
    $script:Net = $null; $script:NetLive = $false; $script:NetClient = $false
}

function Get-NetModeName { if ($script:Net.Mode -eq 'duel') { 'deathmatch' } else { 'co-op' } }

# One line for the title screen.
function Get-NetStatus {
    $n = $script:Net
    if (-not $n) { return '' }
    $what = Get-NetModeName
    if ($n.Role -eq 'host') {
        if ($n.Guests.Count) { return "NETWORK  $what - joined: $(($n.Guests | ForEach-Object Name) -join ', ') ($($n.Guests.Count + 1)/$($n.MaxPlayers)) - Enter starts, F1 players" }
        return "NETWORK  hosting a $what game on port $($n.Port) - waiting for players ...  $($n.Status)"
    }
    if ($n.Connected) { return "NETWORK  $what - connected to $($n.Address) as '$($n.Name)' - the host starts the game  $($n.Status)" }
    if ($n.Refused) { return "NETWORK  $($n.Status)" }
    "NETWORK  looking for $($n.Address):$($n.Port) ...  $($n.Status)"
}

# May the game be started from the title screen? (In a network game only by the host, and only with a guest.)
function Test-NetStart { -not $script:Net -or ($script:Net.Role -eq 'host' -and $script:Net.Connected) }

# ---------------------------------------------------------------------------------------------
# The ban list (host)
# ---------------------------------------------------------------------------------------------
function Get-NetBanPath { Join-Path $script:SaveDir 'banned.json' }

function Import-NetBans {
    $n = $script:Net; $n.Bans.Clear()
    $path = Get-NetBanPath
    if (Test-Path -LiteralPath $path) { try { foreach ($b in @(Get-Content -LiteralPath $path -Raw | ConvertFrom-Json)) { if ($b) { $n.Bans.Add([string]$b) } } } catch { } }
}

function Export-NetBans {
    try {
        $null = New-Item -ItemType Directory -Path $script:SaveDir -Force
        ConvertTo-Json -InputObject @($script:Net.Bans) | Set-Content -LiteralPath (Get-NetBanPath) -Encoding utf8
    }
    catch { }
}

# ---------------------------------------------------------------------------------------------
# Connections
# ---------------------------------------------------------------------------------------------
# Host: somebody knocks. Banned addresses and a full house are turned away with a reason.
function Add-NetGuest {
    $n = $script:Net
    while ($n.Listener.Pending()) {
        $tcp = $n.Listener.AcceptTcpClient()
        $tcp.NoDelay = $true; $tcp.SendTimeout = 3000
        $address = "$(([System.Net.IPEndPoint]$tcp.Client.RemoteEndPoint).Address)"
        $refuse = if ($n.Bans.Contains($address)) { 'You are banned from this game' } elseif ($n.Guests.Count + 1 -ge $n.MaxPlayers) { "The game is full ($($n.MaxPlayers) players)" } else { $null }
        if ($refuse) {
            try { $bytes = [System.Text.Encoding]::UTF8.GetBytes("N|$refuse`n"); $tcp.GetStream().Write($bytes, 0, $bytes.Length) } catch { }
            $tcp.Dispose()
            $n.Status = "(turned away $address`: $refuse)"
            continue
        }
        $slot = 1; while ($n.Guests | Where-Object Slot -eq $slot) { $slot++ }
        $guest = @{
            Slot = $slot; Name = "Player $($slot + 1)"; Address = $address; Tcp = $tcp; Stream = $tcp.GetStream()
            In = [System.Text.StringBuilder]::new(); Out = [System.Text.StringBuilder]::new(); Decoder = [System.Text.Encoding]::UTF8.GetDecoder()
            InLevel = $false; Ready = $false
        }
        $n.Guests.Add($guest); $n.Connected = $true; $n.Status = ''
        Send-NetTo $guest "V|$($script:NET_VERSION)|$($n.Mode)|$slot"
        if ($script:NetLive) { Send-NetTo $guest 'X|The game is under way - you are in from the next floor.' }
    }
}

# Host: a guest goes - by himself, by a lost connection, or because the host says so.
function Remove-NetGuest([hashtable]$Guest, [string]$Why, [switch]$Tell, [switch]$Ban) {
    $n = $script:Net
    if (-not $n.Guests.Contains($Guest)) { return }
    if ($Tell) { try { $bytes = [System.Text.Encoding]::UTF8.GetBytes("N|$Why`n"); $Guest.Stream.Write($bytes, 0, $bytes.Length) } catch { } }
    foreach ($o in $Guest.Stream, $Guest.Tcp) { if ($o) { try { $o.Dispose() } catch { } } }
    $null = $n.Guests.Remove($Guest)
    $n.Connected = $n.Guests.Count -gt 0
    if ($Ban -and -not $n.Bans.Contains($Guest.Address)) { $n.Bans.Add($Guest.Address); Export-NetBans }
    Remove-NetPlayer $Guest.Slot
    Send-NetMessage "O|$($Guest.Slot)|$Why"
    $note = "$($Guest.Name) is out: $Why"
    $n.Status = "($note)"
    if ($script:NetLive) { $script:NetScope = 'remote'; try { Show-Message $note } finally { $script:NetScope = 'local' } }
}

# Everybody: a player's ghost leaves the floor.
function Remove-NetPlayer([int]$Slot) {
    $n = $script:Net
    $pl = $n.Players[$Slot]
    if (-not $pl) { return }
    $g = $pl.Ghost
    $idx = $g.TY * $script:MapW + $g.TX
    if ($script:ActorAt -and $idx -ge 0 -and $idx -lt $script:ActorAt.Length -and $script:ActorAt[$idx] -eq $g) { $script:ActorAt[$idx] = $null }
    $null = $script:Actors.Remove($g)
    $n.Players.Remove($Slot)
    if ($script:NetLive -and -not $script:NetClient) { Update-AreaByPlayer }
    $script:HudDirty = $true
}

# Guest: find the host. Keeps trying every two seconds - unless the host has said no.
function Connect-NetHost {
    $n = $script:Net
    if ($n.Refused) { return }
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
    $n.Tcp.NoDelay = $true; $n.Tcp.SendTimeout = 3000
    $n.Stream = $n.Tcp.GetStream()
    $null = $n.In.Clear(); $null = $n.Out.Clear()
    $n.Connected = $true; $n.Status = ''
}

# Guest: the connection to the host is gone.
function Disconnect-NetHost([string]$Why) {
    $n = $script:Net
    foreach ($o in $n.Stream, $n.Tcp) { if ($o) { try { $o.Dispose() } catch { } } }
    $n.Stream = $null; $n.Tcp = $null; $n.Pending = $null; $n.Connected = $false
    $n.Retry = $script:Clock.Elapsed.TotalSeconds + 2.0
    $n.Status = "($Why)"
    $wasLive = $script:NetLive
    $script:NetLive = $false; $script:NetClient = $false; $script:NetAsPeer = $false; $script:NetScope = 'local'
    if ($wasLive -or $script:Mode -in 'done', 'players') { Set-Mode 'title' }
}

# Guest: to the host.  Host: to every guest who is on the floor.
function Send-NetMessage([string]$Line) {
    $n = $script:Net
    if (-not $n) { return }
    if ($n.Role -eq 'host') { foreach ($g in $n.Guests) { if ($g.InLevel) { $null = $g.Out.Append($Line).Append("`n") } } }
    elseif ($n.Connected) { $null = $n.Out.Append($Line).Append("`n") }
}

function Send-NetTo([hashtable]$Guest, [string]$Line) { if ($Guest) { $null = $Guest.Out.Append($Line).Append("`n") } }

# Host: to everybody on the floor but one (what a guest reports, the others must hear).
function Send-NetExcept([int]$Slot, [string]$Line) { foreach ($g in $script:Net.Guests) { if ($g.InLevel -and $g.Slot -ne $Slot) { $null = $g.Out.Append($Line).Append("`n") } } }

# Host, inside a peer context: to the guest whose turn it is.
function Send-NetPeer([string]$Line) { Send-NetTo (Get-NetGuest $script:Net.Ctx) $Line }

function Get-NetGuest([int]$Slot) { foreach ($g in $script:Net.Guests) { if ($g.Slot -eq $Slot) { return $g } }; $null }

# Reads what has arrived on one connection and hands the complete lines to Invoke-NetMessage.
function Read-NetStream($Tcp, $Stream, [System.Text.StringBuilder]$Buffer, $Decoder, [hashtable]$From) {
    $n = $script:Net
    $socket = $Tcp.Client
    if ($socket.Poll(0, [System.Net.Sockets.SelectMode]::SelectRead) -and $socket.Available -eq 0) { throw [System.IO.IOException]::new('gone') }
    while ($Stream.DataAvailable) {
        $read = $Stream.Read($n.Bytes, 0, $n.Bytes.Length)
        if ($read -le 0) { throw [System.IO.IOException]::new('gone') }
        $count = $Decoder.GetChars($n.Bytes, 0, $read, $n.Chars, 0)
        $null = $Buffer.Append($n.Chars, 0, $count)
    }
    if ($Buffer.Length -eq 0) { return }
    if ($Buffer.Length -gt 400000) { throw 'too much at once' }
    $text = $Buffer.ToString()
    $last = $text.LastIndexOf("`n")
    if ($last -lt 0) { return }
    $null = $Buffer.Clear(); $null = $Buffer.Append($text.Substring($last + 1))
    foreach ($line in $text.Substring(0, $last).Split("`n")) {
        if ($line) { $n.Received++; Invoke-NetMessage $line $From; if ($From -and -not $n.Guests.Contains($From)) { return } }
    }
}

function Write-NetStream($Stream, [System.Text.StringBuilder]$Buffer) {
    if ($Buffer.Length -eq 0) { return }
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Buffer.ToString())
    $null = $Buffer.Clear()
    $Stream.Write($bytes, 0, $bytes.Length)
}

function Get-NetErrorText($ErrorRecord) {
    $e = $ErrorRecord.Exception
    while ($e.InnerException) { $e = $e.InnerException }
    if ($e -is [System.Net.Sockets.SocketException] -or $e -is [System.IO.IOException] -or $e -is [System.ObjectDisposedException]) { 'the connection was lost' } else { $e.Message }
}

# Once per frame, whatever the game mode.
function Update-Network([double]$Tics) {
    $n = $script:Net
    if (-not $n) { return }
    if ($n.Role -eq 'host') {
        try { Add-NetGuest } catch { $n.Status = "($(Get-NetErrorText $_))" }
        foreach ($g in @($n.Guests)) { try { Read-NetStream $g.Tcp $g.Stream $g.In $g.Decoder $g } catch { Remove-NetGuest $g (Get-NetErrorText $_) } }
        if ($script:NetLive) {
            Send-NetPlayerState
            $waiting = @($n.Guests | Where-Object { $_.InLevel -and -not $_.Ready }).Count
            if (-not $waiting) {
                $n.SnapTics += $Tics
                if ($n.SnapTics -ge 3.5) { $n.SnapTics = 0.0; Send-NetSnapshot }
                Update-NetRespawns
            }
        }
        foreach ($g in @($n.Guests)) { try { Write-NetStream $g.Stream $g.Out } catch { Remove-NetGuest $g (Get-NetErrorText $_) } }
        return
    }
    try {
        if (-not $n.Connected) { Connect-NetHost; if (-not $n.Connected) { return } }
        Read-NetStream $n.Tcp $n.Stream $n.In $n.Decoder $null
        if (-not $n.Connected) { return }
        if ($script:NetLive) { Send-NetPlayerState }
        Write-NetStream $n.Stream $n.Out
    }
    catch { Disconnect-NetHost (Get-NetErrorText $_) }
}

# ---------------------------------------------------------------------------------------------
# Starting a floor together
# ---------------------------------------------------------------------------------------------
function Get-MapHash([string]$Path) {
    $text = (Get-Content -LiteralPath $Path -Raw) -replace "`r", ''
    [BitConverter]::ToString([System.Security.Cryptography.SHA1]::HashData([System.Text.Encoding]::UTF8.GetBytes($text))).Replace('-', '').Substring(0, 8)
}

# The $Count free floor tiles nearest to (X,Y) in the same room, that tile itself not included: where guests start in co-op.
function Find-NetFreeSpots([double]$X, [double]$Y, [int]$Count) {
    $cx = [int][Math]::Floor($X); $cy = [int][Math]::Floor($Y); $w = $script:MapW
    $found = [System.Collections.Generic.List[object]]::new()
    foreach ($r in 1..5) {
        for ($dy = - $r; $dy -le $r; $dy++) {
            for ($dx = - $r; $dx -le $r; $dx++) {
                if ([Math]::Max([Math]::Abs($dx), [Math]::Abs($dy)) -ne $r) { continue }
                $tx = $cx + $dx; $ty = $cy + $dy
                if ($tx -lt 1 -or $ty -lt 1 -or $tx -ge $w - 1 -or $ty -ge $script:MapH - 1) { continue }
                $idx = $ty * $w + $tx
                if ($script:Tiles[$idx] -eq 0 -and -not $script:StaticBlock[$idx] -and $null -eq $script:ActorAt[$idx] -and
                    $script:AreaOf[$idx] -eq $script:AreaOf[$cy * $w + $cx]) { $found.Add(@(($tx + 0.5), ($ty + 0.5))); if ($found.Count -ge $Count) { return $found.ToArray() } }
            }
        }
    }
    while ($found.Count -lt $Count) { $found.Add(@($X, $Y)) }
    $found.ToArray()
}

# The spawn spot farthest away from everybody in $Others (a list of x,y pairs); with $Pick > 1 a random one of the best.
function Find-NetSpawn([object[]]$Others, [int]$Pick = 1) {
    $ranked = @($script:Net.Spawns | Sort-Object {
            $spot = $_; $near = 1e9
            foreach ($o in $Others) { $d = [Math]::Abs($spot[0] - $o[0]) + [Math]::Abs($spot[1] - $o[1]); if ($d -lt $near) { $near = $d } }
            - $near
        } | Select-Object -First $Pick)
    $ranked[$script:FxRng.Next($ranked.Count)]
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

# Puts another player onto the floor: his ghost and, on the host, his proxy.
function Add-NetPlayer([int]$Slot, [string]$Name, [double]$X, [double]$Y) {
    $n = $script:Net; $w = $script:MapW
    $g = [Actor]::new()
    $g.Kind = 'peer'; $g.Def = $script:MiscDefs.peer; $g.State = "peer$Slot.stand"; $g.PeerSlot = $Slot
    $g.X = $X; $g.Y = $Y; $g.NX = $X; $g.NY = $Y
    $g.TX = [int][Math]::Floor($X); $g.TY = [int][Math]::Floor($Y)
    $g.Dir = [int]($script:StartAngle / 45.0) % 8
    $g.Area = $script:AreaOf[$g.TY * $w + $g.TX]
    $g.Shootable = $true; $g.Active = $true
    $script:Actors.Add($g)
    $pl = @{ Slot = $Slot; Name = $Name; Ghost = $g; Health = 100; Proxy = $null; Noise = $false; Step = 0.0
        Anim = @{ Fire = 0.0; Pain = 0.0; Walk = 0.0; Still = 99.0; Dead = $false; Die = 0.0 } }
    if ($n.Role -eq 'host') {
        # a stand-in for $script:P while the enemies deal with him
        $me = $script:P
        New-Player
        $pl.Proxy = $script:P
        $script:P = $me
        $pl.Proxy.X = $X; $pl.Proxy.Y = $Y; $pl.Proxy.Area = $g.Area; $pl.Proxy.Angle = $script:StartAngle
    }
    $n.Players[$Slot] = $pl; $n.Names[$Slot] = $Name
    if (-not $n.Frags.ContainsKey($Slot)) { $n.Frags[$Slot] = 0 }
}

# Called by Start-Level on every machine once the map is loaded (from the same file with the same seed,
# so all start with identical actors that carry identical ids).
function Initialize-NetLevel([bool]$KeepPlayer, [bool]$KeepKit) {
    $n = $script:Net; $w = $script:MapW
    $isHost = $n.Role -eq 'host'
    $spots = [System.Collections.Generic.List[object]]::new()
    $spots.Add(@($script:StartX, $script:StartY))

    if ($n.Mode -eq 'duel') {
        # no monsters in a deathmatch - but where they stood is where the players respawn
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
    }
    $n.Spawns = $spots.ToArray()
    $n.Players = @{}; $n.Names = @{}
    if (-not $KeepPlayer) { $n.Frags = @{} }

    if ($isHost) {
        # the host decides who is in and where everybody starts
        $n.Slot = 0; $n.Serial++
        $guests = @($n.Guests)
        $roster = [System.Collections.Generic.List[hashtable]]::new()
        $roster.Add(@{ Slot = 0; Name = $n.Name; X = $script:StartX; Y = $script:StartY })
        $near = Find-NetFreeSpots $script:StartX $script:StartY $guests.Count
        for ($i = 0; $i -lt $guests.Count; $i++) {
            $spot = if ($n.Mode -eq 'duel') { Find-NetSpawn @($roster | ForEach-Object { , @($_.X, $_.Y) }) } else { $near[$i] }
            $roster.Add(@{ Slot = $guests[$i].Slot; Name = $guests[$i].Name; X = $spot[0]; Y = $spot[1] })
        }
        $n.Roster = $roster.ToArray()
    }
    foreach ($entry in $n.Roster) {
        if ($null -eq $entry.X) { $entry.X = $script:StartX; $entry.Y = $script:StartY }
        if ($entry.Slot -eq $n.Slot) { $n.MySpot = @($entry.X, $entry.Y); $n.Names[$n.Slot] = $entry.Name; if (-not $n.Frags.ContainsKey($n.Slot)) { $n.Frags[$n.Slot] = 0 }; Move-NetPlayer $entry.X $entry.Y }
        else { Add-NetPlayer $entry.Slot $entry.Name $entry.X $entry.Y }
    }
    $n.Home = $script:P; $n.Ctx = 0

    $n.ById = @{}
    foreach ($a in $script:Actors) { if ($a.NetId -gt 0) { $n.ById[$a.NetId] = $a } }
    $n.BaseIds = $script:NextNetId
    $n.Sent = @{}; $n.Final.Clear(); $n.Gone.Clear(); $n.Respawns.Clear()
    $n.DoorsSent = ''; $n.StatsSent = ''; $n.SnapTics = 0.0
    $script:P.RunInvalid = $true                                  # no speedrun records from network games

    if ($isHost) {
        $bonus = if ($script:BonusMap) { Split-Path $script:BonusMap -Leaf } else { '' }
        $list = ($n.Roster | ForEach-Object { "$($_.Slot):$($_.Name):$($_.X):$($_.Y)" }) -join ','
        foreach ($g in $n.Guests) {
            $g.InLevel = $true; $g.Ready = $false
            Send-NetTo $g "G|$($n.Serial)|$($script:LevelIndex)|$bonus|$($script:Difficulty)|$($script:LevelSeed)|$([int]$KeepPlayer)|$([int]$KeepKit)|$(Get-MapHash $script:MapFile)|$($g.Slot)|$list"
        }
    }
    else { Send-NetMessage "R|$($n.Serial)" }
    $script:NetLive = $true; $script:NetClient = -not $isHost
    $script:NetAsPeer = $false; $script:NetScope = 'local'
    Update-AreaByPlayer
    if ($isHost) { Send-NetScores }
}

# Back on his feet after a death: no lives in a network game, the floor goes on.
function Reset-NetPlayer {
    $n = $script:Net; $p = $script:P
    Reset-PlayerKit
    if ($n.Mode -eq 'duel') { Set-NetDuelKit; $spot = Find-NetSpawn @($n.Players.Values | ForEach-Object { , @($_.Ghost.NX, $_.Ghost.NY) }) 3 } else { $spot = $n.MySpot }
    $p.AttackFrame = -1; $p.WeaponFrame = 0; $p.UseHeld = $true; $p.FireHeld = $true
    $p.Angle = $script:StartAngle
    Move-NetPlayer $spot[0] $spot[1]
    Reset-ScreenEffects
    $script:PlayerDied = $false; $script:Killer = $null; $script:ShowWeapon = $true; $script:HudDirty = $true
}

# ---------------------------------------------------------------------------------------------
# The peer context (host only)
# ---------------------------------------------------------------------------------------------
function Enter-PeerContext([int]$Slot) {
    $n = $script:Net; $pl = $n.Players[$Slot]; $g = $pl.Ghost
    $n.Ctx = $Slot
    $n.Home = $script:P; $n.HomeStep = $script:StepNoise
    $n.GhostX = $g.X; $n.GhostY = $g.Y
    $g.X = $n.Home.X; $g.Y = $n.Home.Y                          # his ghost stands in for the host's own player
    $pl.Proxy.KeyGold = $n.Home.KeyGold; $pl.Proxy.KeySilver = $n.Home.KeySilver      # keys are shared
    $script:P = $pl.Proxy
    $script:StepNoise = $pl.Step
    $script:NetAsPeer = $true
}

function Exit-PeerContext {
    $n = $script:Net; $pl = $n.Players[$n.Ctx]
    $script:P = $n.Home; $script:NetAsPeer = $false
    if ($pl) { $pl.Step = $script:StepNoise; $pl.Ghost.X = $n.GhostX; $pl.Ghost.Y = $n.GhostY }
    $script:StepNoise = $n.HomeStep
    $n.Ctx = 0
}

# Runs something a guest asked for: as him, and with sounds and messages going to him only.
function Invoke-InPeerContext([int]$Slot, [scriptblock]$NetAction) {
    if (-not $script:Net.Players[$Slot]) { return }
    Enter-PeerContext $Slot
    $script:NetScope = 'peer'
    try { & $NetAction } finally { $script:NetScope = 'local'; Exit-PeerContext }
}

# Which player should this actor deal with this frame? 0 = the host's own, otherwise a guest's slot.
function Get-NetTargetSlot([Actor]$a) {
    $n = $script:Net
    if ($a.Kind -eq 'peer') { return 0 }
    if ($a.PeerSlot -gt 0) { return $(if ($n.Players[$a.PeerSlot]) { $a.PeerSlot } else { 0 }) }      # a guest's projectile
    if ($n.Mode -ne 'coop' -or $a.Def.Inert -or $n.Players.Count -eq 0) { return 0 }
    if ($a.Corpse -and $a.Kind -ne 'rocket') { return 0 }
    $mine = $script:P
    if (-not $a.AttackMode -and $a.Kind -ne 'rocket') {
        # not alerted yet: look out for everybody in turn
        $alive = @(if ($mine.Health -gt 0) { 0 }; foreach ($pl in $n.Players.Values) { if ($pl.Proxy.Health -gt 0) { $pl.Slot } })
        if (-not $alive.Count) { return 0 }
        return $alive[$script:NetFrame % $alive.Count]
    }
    $best = 0; $bestD = if ($mine.Health -gt 0) { [Math]::Abs($mine.X - $a.X) + [Math]::Abs($mine.Y - $a.Y) } else { 1e9 }
    foreach ($pl in $n.Players.Values) {
        if ($pl.Proxy.Health -le 0) { continue }
        $d = [Math]::Abs($pl.Proxy.X - $a.X) + [Math]::Abs($pl.Proxy.Y - $a.Y)
        if ($d -lt $bestD) { $bestD = $d; $best = $pl.Slot }
    }
    $best
}

# Host: an explosion also reaches the players who are not "$script:P" at the moment.
function Invoke-NetBlast([double]$X, [double]$Y, [double]$Radius, [double]$Damage, [Actor]$Owner) {
    $n = $script:Net
    $ctx = if ($script:NetAsPeer) { $n.Ctx } else { 0 }
    $blame = if ($script:NetBlastByPlayer) { "P$ctx" } elseif ($Owner) { "$($Owner.NetId)" } else { '0' }
    foreach ($pl in @($n.Players.Values)) {
        if ($pl.Slot -eq $ctx) { continue }
        $dx = $pl.Proxy.X - $X; $dy = $pl.Proxy.Y - $Y; $d = [Math]::Sqrt($dx * $dx + $dy * $dy)
        if ($d -lt $Radius -and $pl.Proxy.Health -gt 0) { Send-NetTo (Get-NetGuest $pl.Slot) "H|$([int]($Damage * 0.6 * (1 - $d / $Radius)))|$blame" }
    }
    if ($script:NetAsPeer) {
        $own = $n.Home
        $dx = $own.X - $X; $dy = $own.Y - $Y; $d = [Math]::Sqrt($dx * $dx + $dy * $dy)
        if ($d -lt $Radius -and $own.Health -gt 0) {
            $points = [int]($Damage * 0.6 * (1 - $d / $Radius))
            $blamed = if ($script:NetBlastByPlayer) { $n.Players[$ctx].Ghost } else { $Owner }
            $scope = $script:NetScope
            Exit-PeerContext; $script:NetScope = 'local'
            try { Invoke-PlayerDamage $points $blamed } finally { $script:NetScope = $scope; Enter-PeerContext $ctx }
        }
    }
}

# Somebody hit a ghost. Only in a deathmatch does that hurt - and never by an explosion (see Invoke-NetBlast).
function Invoke-PeerDamage([Actor]$Ghost, [int]$Damage, [string]$Source) {
    $n = $script:Net
    if ($n.Mode -ne 'duel' -or $Source -eq 'explosion' -or $Damage -le 0) { return }
    $victim = $Ghost.PeerSlot
    if ($script:NetClient) {
        if ($script:P.SudoTics -gt 0) { $Damage *= 2 }
        Add-HitEffect $Ghost
        Send-NetMessage "K|$victim|$Damage"                        # the host passes it on
        return
    }
    if ($script:NetAsPeer -and $victim -eq $n.Ctx) {
        # here the ghost stands in for the host's own player: a guest's knife or rocket has found him
        $ctx = $n.Ctx; $scope = $script:NetScope
        Exit-PeerContext; $script:NetScope = 'local'
        try { Invoke-PlayerDamage $Damage $n.Players[$ctx].Ghost } finally { $script:NetScope = $scope; Enter-PeerContext $ctx }
        return
    }
    $by = if ($script:NetAsPeer) { $n.Ctx } else { 0 }
    if (-not $script:NetAsPeer) { if ($script:P.SudoTics -gt 0) { $Damage *= 2 }; Add-HitEffect $Ghost }
    Send-NetTo (Get-NetGuest $victim) "H|$Damage|P$by"
}

# This player has been killed by the player in $Killer's slot.
function Register-NetFrag([int]$Killer) {
    if ($script:NetClient) { Send-NetMessage "F|$Killer" } else { Add-NetFrag $Killer 0 }
}

# Host: keeps the score and tells everybody.
function Add-NetFrag([int]$Killer, [int]$Victim) {
    $n = $script:Net
    if ($Killer -eq $Victim) { return }
    $n.Frags[$Killer] = [int]$n.Frags[$Killer] + 1
    Send-NetScores
    $text = "$($n.Names[$Killer]) got $($n.Names[$Victim])"
    Send-NetMessage "X|$text"
    $script:NetScope = 'remote'; try { Show-Message $text } finally { $script:NetScope = 'local' }
    $script:HudDirty = $true
}

function Send-NetScores { Send-NetMessage "C|$(($script:Net.Frags.Keys | Sort-Object | ForEach-Object { "$_`:$($script:Net.Frags[$_])" }) -join ',')" }

# ---------------------------------------------------------------------------------------------
# Every frame: my player -> the others; the ghosts' animation
# ---------------------------------------------------------------------------------------------
function Send-NetPlayerState {
    $p = $script:P
    $flags = [int]$p.Running + 2 * [int]$p.Sneaking + 4 * [int][bool]$script:MadeNoise + 8 * [int]($p.Health -le 0) + 16 * [int]($p.SudoTics -gt 0)
    Send-NetMessage "M|$($script:Net.Slot)|$([Math]::Round($p.X, 3))|$([Math]::Round($p.Y, 3))|$([Math]::Round($p.Angle, 1))|$flags|$($p.Health)|$($script:StepNoise)|$($p.Area)"
}

function Update-NetGhosts([double]$Tics) {
    $k = [Math]::Min(1.0, $Tics * 0.35)
    foreach ($pl in @($script:Net.Players.Values)) {
        $g = $pl.Ghost; $an = $pl.Anim; $prefix = "peer$($pl.Slot)"
        $dx = $g.NX - $g.X; $dy = $g.NY - $g.Y
        $moved = 0.0
        if ([Math]::Abs($dx) + [Math]::Abs($dy) -gt 2.5) { $g.X = $g.NX; $g.Y = $g.NY }        # teleporter or respawn
        else { $g.X += $dx * $k; $g.Y += $dy * $k; $moved = [Math]::Sqrt($dx * $dx + $dy * $dy) * $k }
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
            $g.State = if ($an.Die -lt 9) { "$prefix.die1" } elseif ($an.Die -lt 18) { "$prefix.die2" } elseif ($an.Die -lt 27) { "$prefix.die3" } else { "$prefix.dead" }
        }
        elseif ($an.Fire -gt 0) { $an.Fire -= $Tics; $g.State = "$prefix.fire" }
        elseif ($an.Pain -gt 0) { $an.Pain -= $Tics; $g.State = "$prefix.pain" }
        elseif ($moved -gt 0.003) { $an.Walk += $moved; $an.Still = 0.0; $g.State = "$prefix.w$(1 + [int][Math]::Floor($an.Walk * 2.4) % 4)" }
        else { $an.Still += $Tics; if ($an.Still -gt 8) { $g.State = "$prefix.stand" } }
    }
}

# A player's state has arrived (on the host from that guest, on a guest from the host for anybody).
function Set-NetPlayerState([int]$Slot, [string[]]$f) {
    $n = $script:Net; $pl = $n.Players[$Slot]
    if (-not $pl) { return }
    $g = $pl.Ghost; $an = $pl.Anim
    $g.NX = [double]$f[2]; $g.NY = [double]$f[3]
    $g.Dir = [int][Math]::Round([double]$f[4] / 45.0) % 8
    $flags = [int]$f[5]; $health = [int]$f[6]
    $dead = [bool]($flags -band 8)
    if ($dead -and -not $an.Dead) {
        $an.Dead = $true; $an.Die = 0.0
        $g.Shootable = $false; $g.Corpse = $true
        $idx = $g.TY * $script:MapW + $g.TX
        if ($script:ActorAt[$idx] -eq $g) { $script:ActorAt[$idx] = $null }
    }
    elseif (-not $dead -and $an.Dead) {
        $an.Dead = $false; $g.Shootable = $true; $g.Corpse = $false; $g.State = "peer$Slot.stand"
        $g.X = $g.NX; $g.Y = $g.NY
    }
    if ($health -lt $pl.Health -and -not $dead) { $an.Pain = 8.0 }
    $pl.Health = $health
    if ($pl.Proxy) {
        $px = $pl.Proxy
        $px.X = $g.NX; $px.Y = $g.NY; $px.Angle = [double]$f[4]; $px.Health = $health
        $px.Running = [bool]($flags -band 1); $px.Sneaking = [bool]($flags -band 2)
        $px.SudoTics = if ($flags -band 16) { 1.0 } else { 0.0 }
        if ($flags -band 4) { $pl.Noise = $true }
        $pl.Step = [double]$f[7]
        $area = [int]$f[8]
        if ($area -ge 0 -and $area -ne $px.Area) { $px.Area = $area; Update-AreaByPlayer }
    }
}

# Host, once per frame: did any guest make a noise that the enemies should hear?
function Test-NetNoise {
    $heard = $false
    foreach ($pl in $script:Net.Players.Values) { if ($pl.Noise) { $heard = $true; $pl.Noise = $false } }
    $heard
}

# What the view says about the others.
function Get-NetHudText {
    $n = $script:Net
    if ($n.Mode -eq 'duel') {
        $rows = foreach ($slot in ($n.Names.Keys | Sort-Object)) { "$(if ($slot -eq $n.Slot) { 'you' } else { $n.Names[$slot] }) $([int]$n.Frags[$slot])" }
        return "FRAGS   $($rows -join '   ')"
    }
    $rows = foreach ($pl in ($n.Players.Values | Sort-Object Slot)) { "$($pl.Name) $(if ($pl.Health -le 0) { 'DOWN' } else { "$($pl.Health)%" })" }
    if ($rows) { "WITH   $($rows -join '   ')" } else { 'ALONE' }
}

# ---------------------------------------------------------------------------------------------
# Host -> guests: what has changed in the world
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

# Deathmatch: what has been picked up comes back after a while. The host keeps the clock.
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

# An item has been taken. $Mine: by this player (tell the others); otherwise somebody else took it.
function Register-NetPickup([int]$Index, [bool]$Mine) {
    $n = $script:Net
    if ($Mine) { Send-NetMessage "I|$Index" }
    else {
        $s = $script:Items[$Index]
        $s.Removed = $true
        switch ($s.Item) {
            'key_gold'   { $script:P.KeyGold = $true; Show-Message 'A partner found the gold key'; $script:HudDirty = $true }
            'key_silver' { $script:P.KeySilver = $true; Show-Message 'A partner found the silver key'; $script:HudDirty = $true }
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
# Guest: the actors are puppets, moved by the snapshots
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
# Incoming messages.  $From: on the host the guest who sent the line, on a guest $null (the host).
# ---------------------------------------------------------------------------------------------
function Invoke-NetMessage([string]$Line, [hashtable]$From) {
    $n = $script:Net
    $f = $Line.Split('|')
    if ($From) { Invoke-NetGuestMessage $f $From; return }

    # ---- a guest hears from the host ----
    if ($f[0] -cin 'M', 'Z', 'O', 'H', 'S', 'I', 'J', 'A', 'T', 'W', 'Q', 'L' -and -not $script:NetLive) { return }
    switch -CaseSensitive ($f[0]) {
        'V' {
            if ([int]$f[1] -ne $script:NET_VERSION) { throw "the host speaks protocol version $($f[1]), this game $($script:NET_VERSION)" }
            $n.Mode = $f[2]; $n.Slot = [int]$f[3]
            Send-NetMessage "V|$($script:NET_VERSION)|$($n.Name)"
        }
        'N' {
            # refused, kicked or banned: say why and stay away
            $n.Refused = $true
            Disconnect-NetHost ($f[1..($f.Count - 1)] -join '|')
        }
        'G' {
            if ([int]$f[2] -ge $script:MapFiles.Count) { throw "the host plays floor $([int]$f[2] + 1), which this copy of the game does not have" }
            $n.Serial = [int]$f[1]
            $script:LevelIndex = [int]$f[2]
            $script:BonusMap = if ($f[3]) { Join-Path (Split-Path $script:MapFiles[$script:LevelIndex]) $f[3] } else { $null }
            $script:Difficulty = [int]$f[4]; $script:NextSeed = [int]$f[5]
            $n.Slot = [int]$f[9]
            $n.Roster = @(foreach ($entry in $f[10].Split(',')) { $e = $entry.Split(':'); @{ Slot = [int]$e[0]; Name = $e[1]; X = [double]$e[2]; Y = [double]$e[3] } })
            $keepPlayer = $f[6] -eq '1' -and $null -ne $script:P
            Start-Level $keepPlayer ($keepPlayer -and $f[7] -eq '1')
            Set-Mode 'play'
            if ((Get-MapHash $script:MapFile) -ne $f[8]) { Show-Message 'WARNING: your copy of this map differs from the host''s' }
        }
        'M' { Set-NetPlayerState ([int]$f[1]) $f }
        'O' { $gone = $n.Names[[int]$f[1]]; Remove-NetPlayer ([int]$f[1]); if ($gone) { Show-Message "$gone is out: $($f[2])" } }
        'C' { foreach ($pair in $f[1].Split(',')) { $kv = $pair.Split(':'); if ($kv.Count -eq 2) { $n.Frags[[int]$kv[0]] = [int]$kv[1] } }; $script:HudDirty = $true }
        'Z' { Import-NetSnapshot $f }
        'H' {
            $attacker = if ($f[2] -match '^P(\d+)$') { $pl = $n.Players[[int]$Matches[1]]; if ($pl) { $pl.Ghost } } else { Get-NetActor ([int]$f[2]) }
            Invoke-PlayerDamage ([int]$f[1]) $attacker
        }
        'S' { Add-Score ([int]$f[1]) }
        'I' { $i = [int]$f[1]; if ($i -ge 0 -and $i -lt $script:Items.Count) { Register-NetPickup $i $false } }
        'J' { $i = [int]$f[1]; if ($i -ge 0 -and $i -lt $script:Items.Count) { $script:Items[$i].Removed = $false } }
        'A' { Add-Item $f[1] ([int]$f[2]) ([int]$f[3]) }
        'T' {
            $idx = [int]$f[1]
            $script:Tiles[$idx] = [int]$f[2]
            if ([int]$f[2] -eq 0) { $script:Breakable[$idx] = $false }
            $script:MapBmp = $null
        }
        'W' { Start-PushWall ([int]$f[1]) ([int]$f[2]) ([int]$f[3]) ([int]$f[4]) }
        'Q' {
            $script:NetScope = 'remote'
            try { Start-Sfx $f[2] } finally { $script:NetScope = 'local' }
            $pl = $n.Players[[int]$f[1]]
            if ($pl -and $script:NetLoud.Contains($f[2]) -and $f[2] -notin 'pain', 'player_die', 'teleport') { $pl.Anim.Fire = 8.0 }
        }
        'X' {
            $script:NetScope = 'remote'
            try { Show-Message ($f[1..($f.Count - 1)] -join '|') } finally { $script:NetScope = 'local' }
        }
        'L' {
            $script:SecretExit = $f[1] -eq '1'
            if ($script:Mode -in 'play', 'paused', 'dying', 'players') { Complete-Level }
        }
        'B' { if ($script:Mode -ne 'title') { $script:NetLive = $false; $script:NetClient = $false; Set-Mode 'title' } }
    }
}

# ---- the host hears from a guest ----
function Invoke-NetGuestMessage([string[]]$f, [hashtable]$From) {
    $n = $script:Net; $slot = $From.Slot
    switch -CaseSensitive ($f[0]) {
        'V' {
            if ([int]$f[1] -ne $script:NET_VERSION) { Remove-NetGuest $From "this game speaks protocol version $($script:NET_VERSION), yours $($f[1])" -Tell; return }
            $name = Get-NetSafeName $f[2] $From.Name
            while ($name -eq $n.Name -or ($n.Guests | Where-Object { $_ -ne $From -and $_.Name -eq $name })) { $name = "$name$($slot + 1)" }
            $From.Name = $name
            return
        }
        'R' { if ([int]$f[1] -eq $n.Serial -and $From.InLevel) { $From.Ready = $true }; return }
        'B' { if ($From.InLevel) { $From.InLevel = $false; $From.Ready = $false; Remove-NetPlayer $slot; Send-NetMessage "O|$slot|left the floor" }; return }
    }
    # everything else refers to the floor in play: worthless before he has loaded it, or after it is over
    if (-not $script:NetLive -or -not $From.Ready -or -not $n.Players[$slot]) { return }
    switch -CaseSensitive ($f[0]) {
        'M' { $f[1] = "$slot"; Set-NetPlayerState $slot $f; Send-NetExcept $slot ($f -join '|') }
        'D' {
            $target = Get-NetActor ([int]$f[1])
            if ($target -and $target.Shootable -and $target.Kind -ne 'peer') { Invoke-InPeerContext $slot { Invoke-ActorDamage $target ([int]$f[2]) $f[3] } }
        }
        'K' {
            # he has hit another player
            if ($n.Mode -ne 'duel') { break }
            $victim = [int]$f[1]; $damage = [Math]::Max(0, [Math]::Min(500, [int]$f[2]))
            if ($victim -eq 0) { Invoke-PlayerDamage $damage $n.Players[$slot].Ghost }
            elseif ($victim -ne $slot -and $n.Players[$victim]) { Send-NetTo (Get-NetGuest $victim) "H|$damage|P$slot" }
        }
        'F' { Add-NetFrag ([int]$f[1]) $slot }
        'U' { Invoke-InPeerContext $slot { Invoke-UseAt ([int]$f[1]) ([int]$f[2]) ([int]$f[3]) ([int]$f[4]) } }
        'P' {
            if ($f[1] -notin 'procket', 'tknife') { break }
            $px = $n.Players[$slot].Proxy; $px.X = [double]$f[2]; $px.Y = [double]$f[3]; $px.Angle = [double]$f[4]
            $before = $script:NewActors.Count
            Invoke-InPeerContext $slot { Add-PlayerProjectile $f[1] }
            if ($script:NewActors.Count -gt $before) { $script:NewActors[$script:NewActors.Count - 1].PeerSlot = $slot }
        }
        'I' {
            $i = [int]$f[1]
            if ($i -ge 0 -and $i -lt $script:Items.Count -and -not $script:Items[$i].Removed) { Register-NetPickup $i $false; Send-NetExcept $slot "I|$i" }
        }
        'Q' {
            $script:NetScope = 'remote'
            try { Start-Sfx $f[2] } finally { $script:NetScope = 'local' }
            if ($script:NetLoud.Contains($f[2]) -and $f[2] -notin 'pain', 'player_die', 'teleport') { $n.Players[$slot].Anim.Fire = 8.0 }
            Send-NetExcept $slot "Q|$slot|$($f[2])"
        }
    }
}

# ---------------------------------------------------------------------------------------------
# The player list (F1). On the host it is an admin panel: K kick, B ban, U lift a ban.
# ---------------------------------------------------------------------------------------------
# The rows that can be selected: guests first, then banned addresses.
function Get-NetPanelRows {
    $n = $script:Net
    @(foreach ($g in ($n.Guests | Sort-Object Slot)) { @{ Kind = 'guest'; Guest = $g } }
      foreach ($b in $n.Bans) { @{ Kind = 'ban'; Address = $b } })
}

function Open-NetPanel {
    if (-not $script:Net) { return }
    $script:Net.Panel.Return = $script:Mode
    Set-Mode 'players'
}

function Update-NetPanel([int[]]$Keys) {
    $n = $script:Net; $panel = $n.Panel; $vk = $script:VK
    $rows = @(if ($n.Role -eq 'host') { Get-NetPanelRows })
    if ($panel.Row -ge $rows.Count) { $panel.Row = [Math]::Max(0, $rows.Count - 1) }
    foreach ($k in $Keys) {
        if ($k -in $vk.Esc, $vk.F1) { Set-Mode $panel.Return; $script:HudDirty = $true; return }
        if (-not $rows.Count) { continue }
        $row = $rows[$panel.Row]
        if ($k -eq $vk.Up) { $panel.Row = ($panel.Row + $rows.Count - 1) % $rows.Count }
        elseif ($k -eq $vk.Down) { $panel.Row = ($panel.Row + 1) % $rows.Count }
        elseif ($k -eq $vk.K -and $row.Kind -eq 'guest') { Remove-NetGuest $row.Guest 'kicked by the host' -Tell; return }
        elseif ($k -eq $vk.B -and $row.Kind -eq 'guest') { Remove-NetGuest $row.Guest 'banned by the host' -Tell -Ban; return }
        elseif ($k -eq $vk.U -and $row.Kind -eq 'ban') { $null = $n.Bans.Remove($row.Address); Export-NetBans; return }
    }
}

# The panel as lines of text: @(text, colour, selected) - drawn by the window and by the terminal alike.
function Get-NetPanelLines {
    $n = $script:Net; $isHost = $n.Role -eq 'host'
    $lines = [System.Collections.Generic.List[object]]::new()
    $lines.Add(@("PLAYERS   $(Get-NetModeName) on port $($n.Port)$(if ($isHost) { "   $($n.Guests.Count + 1) of $($n.MaxPlayers)" })", 'FFFFFF', $false)); $lines.Add(@('', 'FFFFFF', $false))
    $lines.Add(@(('{0,-3} {1,-13} {2,-18} {3,-10} {4,6}' -f '#', 'NAME', 'ADDRESS', 'STATE', 'FRAGS'), '8FB0FF', $false))
    if ($isHost) {
        $lines.Add(@(('{0,-3} {1,-13} {2,-18} {3,-10} {4,6}' -f 1, $n.Name, '(this computer)', 'host', [int]$n.Frags[0]), 'C0C8D8', $false))
        $rows = Get-NetPanelRows; $i = 0
        foreach ($row in $rows) {
            if ($row.Kind -ne 'guest') { continue }
            $g = $row.Guest; $pl = $n.Players[$g.Slot]
            $state = if (-not $g.InLevel) { 'in lobby' } elseif (-not $g.Ready) { 'loading' } elseif ($pl -and $pl.Health -le 0) { 'down' } elseif ($pl) { "$($pl.Health) health" } else { 'playing' }
            $lines.Add(@(('{0,-3} {1,-13} {2,-18} {3,-10} {4,6}' -f ($g.Slot + 1), $g.Name, $g.Address, $state, [int]$n.Frags[$g.Slot]), 'FFFFFF', ($i -eq $n.Panel.Row))); $i++
        }
        if (-not $n.Guests.Count) { $lines.Add(@('    nobody has joined yet', '7080A0', $false)) }
        $lines.Add(@('', 'FFFFFF', $false)); $lines.Add(@('BANNED ADDRESSES', '8FB0FF', $false))
        foreach ($row in $rows) { if ($row.Kind -eq 'ban') { $lines.Add(@("    $($row.Address)", 'FF8070', ($i -eq $n.Panel.Row))); $i++ } }
        if (-not $n.Bans.Count) { $lines.Add(@('    none', '7080A0', $false)) }
        $lines.Add(@('', 'FFFFFF', $false)); $lines.Add(@('Up/Down select     K kick     B ban (kick, and the address stays out)     U lift the ban     Esc/F1 back', 'FFE860', $false))
        if ($script:NetLive) { $lines.Add(@('The world does not wait while this is open.', '7080A0', $false)) }
    }
    else {
        foreach ($slot in ($n.Names.Keys | Sort-Object)) {
            $pl = $n.Players[$slot]
            $state = if ($slot -eq $n.Slot) { 'you' } elseif ($pl -and $pl.Health -le 0) { 'down' } elseif ($pl) { "$($pl.Health) health" } else { '' }
            $lines.Add(@(('{0,-3} {1,-13} {2,-18} {3,-10} {4,6}' -f ($slot + 1), $n.Names[$slot], $(if ($slot -eq 0) { $n.Address } else { '' }), $state, [int]$n.Frags[$slot]), $(if ($slot -eq $n.Slot) { 'FFFFFF' } else { 'C0C8D8' }), $false))
        }
        if (-not $n.Names.Count) { $lines.Add(@("    connected: $($n.Connected) - the list fills when the floor starts", '7080A0', $false)) }
        $lines.Add(@('', 'FFFFFF', $false)); $lines.Add(@('Esc/F1 back        (only the host can kick and ban)', 'FFE860', $false))
    }
    $lines
}

function Show-NetPanel {
    $g = $script:BackG; $s = $script:Scale
    Write-HudBar 'F00A1020' 0 0 320 200
    Write-HudBar 'FF2C54C4' 0 0 320 1.5
    $y = 8.0
    foreach ($line in (Get-NetPanelLines)) {
        if ($line[2]) { Write-HudBar 'FF2C54C4' 4 ($y - 0.6) 312 6.6 }
        $g.DrawString($line[0], $script:Fonts.Term, (Get-Brush $line[1]), [single](8 * $s), [single]($y * $s))
        $y += 6.4
    }
}
