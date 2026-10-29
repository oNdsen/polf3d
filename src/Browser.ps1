# POLF 3D - Copyright (c) 2026 oNdsen. Licensed under the MIT License, see LICENSE.
#
# Browser.ps1 - the server browser. [J] on the title screen lists the games hosted on the local network and joins one,
# takes an address by hand, or hosts a game itself.
#
# Finding needs no server in between: the browser sends one UDP datagram, "POLF3D?", to the broadcast address of every
# network this computer is on (and to this computer itself), on the game's port. A host listens on that port for UDP
# as well as TCP and answers with one line:
#     POLF3D!|1|<version>|<name>|<mode>|<players>|<max players>|<state>|<port>
# Routers do not pass broadcasts on, so this finds the games on the local network and nothing beyond it; a game over
# the internet is joined by its address (A), with the port open in the host's router.

$script:Search = $null

# A UDP socket. A datagram that reached a closed port elsewhere makes Windows report an error on the next Receive -
# SIO_UDP_CONNRESET switches that off, so that one machine without a game does not end the search.
function New-NetUdp([int]$Port) {
    $udp = [System.Net.Sockets.UdpClient]::new($Port)
    try { $null = $udp.Client.IOControl([int]-1744830452, [byte[]]@(0, 0, 0, 0), $null) } catch { }
    $udp
}

# Where to ask: the broadcast address of every network this computer is on, the general one, and this computer itself.
# Returns the targets and this computer's own addresses (an answer from one of them is a game on this computer).
function Get-NetSearchTarget {
    $targets = [System.Collections.Generic.List[System.Net.IPAddress]]::new()
    $own = [System.Collections.Generic.HashSet[string]]::new([string[]]@('127.0.0.1'))
    $targets.Add([System.Net.IPAddress]::Broadcast); $targets.Add([System.Net.IPAddress]::Loopback)
    try {
        foreach ($nic in [System.Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces()) {
            if ($nic.OperationalStatus -ne 'Up') { continue }
            foreach ($u in $nic.GetIPProperties().UnicastAddresses) {
                if ($u.Address.AddressFamily -ne 'InterNetwork' -or -not $u.IPv4Mask) { continue }
                $null = $own.Add($u.Address.ToString())
                $ip = $u.Address.GetAddressBytes(); $mask = $u.IPv4Mask.GetAddressBytes(); $b = [byte[]]::new(4)
                for ($i = 0; $i -lt 4; $i++) { $b[$i] = $ip[$i] -bor (255 -bxor $mask[$i]) }
                $broadcast = [System.Net.IPAddress]::new($b)
                if (-not ($targets -contains $broadcast)) { $targets.Add($broadcast) }
            }
        }
    }
    catch { }
    @{ Targets = $targets; Own = $own }
}

# ---- the host's side: an answer to whoever asks ---------------------------------------------------
function Start-NetBeacon {
    # another program on the port: the game is still hosted, it just cannot be found
    try { $script:Net.Beacon = New-NetUdp $script:Net.Port } catch { $script:Net.Beacon = $null }
}

function Get-NetBeaconText {
    $n = $script:Net
    $state = if (-not $script:NetLive) { 'waiting' } elseif ($script:HordeSeed) { 'arena' } else { "floor $($script:LevelIndex + 1)" }
    'POLF3D!|1|{0}|{1}|{2}|{3}|{4}|{5}|{6}' -f $script:PolfVersion, $n.Name, $n.Mode, ($n.Guests.Count + 1), $n.MaxPlayers, $state, $n.Port
}

function Update-NetBeacon {
    $udp = $script:Net.Beacon
    if (-not $udp) { return }
    try {
        while ($udp.Available -gt 0) {
            $from = [System.Net.IPEndPoint]::new([System.Net.IPAddress]::Any, 0)
            $data = $udp.Receive([ref]$from)
            if ($data.Length -ne 7 -or [System.Text.Encoding]::ASCII.GetString($data) -ne 'POLF3D?') { continue }
            $reply = [System.Text.Encoding]::UTF8.GetBytes((Get-NetBeaconText))
            $null = $udp.Send($reply, $reply.Length, $from)
        }
    }
    catch { }
}

# ---- the browser's side ------------------------------------------------------------------------
function Start-NetSearch {
    if (-not $script:Search) { $script:Search = @{ Udp = $null; Own = $null; Found = [ordered]@{}; Sent = -99.0; Row = 0; Typing = $false; Input = ''; Message = '' } }
    $s = $script:Search
    try {
        if (-not $s.Udp) { $s.Udp = New-NetUdp 0; $s.Udp.EnableBroadcast = $true }
        $where = Get-NetSearchTarget; $s.Own = $where.Own
        $probe = [System.Text.Encoding]::ASCII.GetBytes('POLF3D?')
        foreach ($target in $where.Targets) { try { $null = $s.Udp.Send($probe, $probe.Length, [System.Net.IPEndPoint]::new($target, $script:NetPort)) } catch { } }
    }
    catch { $s.Message = "The search did not work: $($_.Exception.Message)" }
    $s.Sent = $script:Clock.Elapsed.TotalSeconds
}

function Update-NetSearch {
    $s = $script:Search
    if (-not $s) { return }
    $now = $script:Clock.Elapsed.TotalSeconds
    if ($s.Udp) {
        try {
            while ($s.Udp.Available -gt 0) {
                $from = [System.Net.IPEndPoint]::new([System.Net.IPAddress]::Any, 0)
                $f = [System.Text.Encoding]::UTF8.GetString($s.Udp.Receive([ref]$from)).Split('|')
                if ($f.Count -lt 9 -or $f[0] -ne 'POLF3D!' -or $f[1] -ne '1') { continue }
                $port = 0; $players = 0; $max = 0
                if (-not [int]::TryParse($f[8], [ref]$port) -or $port -lt 1024 -or $port -gt 65535 -or -not [int]::TryParse($f[5], [ref]$players) -or
                    -not [int]::TryParse($f[6], [ref]$max)) { continue }
                $here = $s.Own -and $s.Own.Contains($from.Address.ToString())
                $key = if ($here) { "here:$port" } else { "$($from.Address):$port" }      # this computer answers on every address it has
                $s.Found[$key] = @{
                    Address = $(if ($here) { '127.0.0.1' } else { $from.Address.ToString() }); Port = $port; Here = $here
                    Version = ($f[2] -replace '[^0-9.]', ''); Name = Get-NetSafeName $f[3] '?'; Mode = $(if ($f[4] -eq 'duel') { 'deathmatch' } else { 'co-op' })
                    Players = [Math]::Max(0, [Math]::Min(9, $players)); Max = [Math]::Max(0, [Math]::Min(9, $max)); State = (Get-NetSafeName $f[7] '')
                    Seen = $now
                }
            }
        }
        catch { }
    }
    foreach ($key in @($s.Found.Keys)) { if ($now - $s.Found[$key].Seen -gt 8) { $s.Found.Remove($key) } }     # gone quiet: gone
    if ($now - $s.Sent -gt 3) { Start-NetSearch }                                                                   # and ask again now and then
}

function Stop-NetSearch {
    if ($script:Search -and $script:Search.Udp) { try { $script:Search.Udp.Dispose() } catch { } }
    $script:Search = $null
}

function Open-NetBrowser {
    Stop-NetSearch; Start-NetSearch
    Set-Mode 'browse'
}

function Join-NetGame([string]$Address, [int]$Port) {
    Stop-NetSearch
    Initialize-Network 'client' 'coop' $Address $Port 4 $script:NetName
    Set-Mode 'title'
}

function Start-NetHost([string]$Mode) {
    try { Initialize-Network 'host' $Mode '' $script:NetPort 4 $script:NetName }
    catch { Stop-Network; $script:Search.Message = "Cannot host on port $($script:NetPort): $($_.Exception.Message)"; return }
    Stop-NetSearch
    Set-Mode 'title'
}

# A key as a character of an address - the same in the window and in the terminal, where only key codes arrive.
function Get-NetAddressChar([int]$Code) {
    if ($Code -ge 48 -and $Code -le 57) { return [string][char]$Code }
    if ($Code -ge 96 -and $Code -le 105) { return [string][char]($Code - 48) }      # the number pad
    if ($Code -ge 65 -and $Code -le 90) { return ([string][char]$Code).ToLowerInvariant() }
    if ($Code -in 190, 110) { return '.' }
    if ($Code -in 189, 109) { return '-' }
    ''
}

function Update-NetBrowser([int[]]$Keys) {
    $s = $script:Search; $vk = $script:VK
    if (-not $s) { Set-Mode 'title'; return }
    Update-NetSearch
    $games = @($s.Found.Values)
    foreach ($h in $Keys) {
        if ($s.Typing) {
            if ($h -eq $vk.Esc) { $s.Typing = $false; $s.Input = '' }
            elseif ($h -eq $vk.Enter) { if ($s.Input) { Join-NetGame $s.Input $script:NetPort; return } }
            elseif ($h -eq 8) { if ($s.Input) { $s.Input = $s.Input.Substring(0, $s.Input.Length - 1) } }
            elseif ($s.Input.Length -lt 60) { $s.Input += Get-NetAddressChar $h }
            continue
        }
        if ($h -eq $vk.Esc) { Stop-NetSearch; Set-Mode 'title'; return }
        elseif ($h -eq $vk.Up) { $s.Row = [Math]::Max(0, $s.Row - 1) }
        elseif ($h -eq $vk.Down) { $s.Row = [Math]::Min([Math]::Max(0, $games.Count - 1), $s.Row + 1) }
        elseif ($h -eq $vk.Enter -and $games.Count) { $g = $games[[Math]::Min($s.Row, $games.Count - 1)]; Join-NetGame $g.Address $g.Port; return }
        elseif ($h -eq $vk.A) { $s.Typing = $true; $s.Input = '' }
        elseif ($h -eq $vk.C) { Start-NetHost 'coop'; return }
        elseif ($h -eq $vk.D) { Start-NetHost 'duel'; return }
        elseif ($h -eq 82) { $s.Found.Clear(); Start-NetSearch }                            # R: search again, from scratch
    }
}

# The screen as lines of text: @(text, colour, selected) - drawn in the window, written in the terminal.
function Get-NetBrowserLines {
    $s = $script:Search; $lines = [System.Collections.Generic.List[object]]::new()
    $row = '{0,-14}{1,-12}{2,-9}{3,-10}{4,-17}{5}'
    $lines.Add(@('PS Shellstein:\> Find-PolfGame', '8FB0FF', $false)); $lines.Add(@('', 'FFFFFF', $false))
    $lines.Add(@("GAMES ON THE NETWORK        port $($script:NetPort)        you play as '$($script:NetName)'", 'FFFFFF', $false)); $lines.Add(@('', 'FFFFFF', $false))
    $lines.Add(@(($row -f 'NAME', 'MODE', 'PLAYERS', 'STATE', 'ADDRESS', 'VERSION'), '8FB0FF', $false))
    $games = @($s.Found.Values)
    for ($i = 0; $i -lt $games.Count; $i++) {
        $g = $games[$i]; $same = $g.Version -eq $script:PolfVersion
        $text = $row -f $g.Name, $g.Mode, "$($g.Players) / $($g.Max)", $g.State, $(if ($g.Here) { 'this computer' } else { $g.Address }), $(if ($same) { $g.Version } else { "$($g.Version) - not yours" })
        $lines.Add(@($text, $(if (-not $same) { '7080A0' } elseif ($g.Players -ge $g.Max) { 'C0C8D8' } else { 'FFFFFF' }), ($i -eq $s.Row -and -not $s.Typing)))
    }
    if (-not $games.Count) {
        $searching = $script:Clock.Elapsed.TotalSeconds - $s.Sent -lt 1.5 -and $s.Sent -gt 0
        $lines.Add(@($(if ($searching) { '    searching ...' } else { '    no game on this network yet - C or D hosts one, and it shows up here for the others' }), '7080A0', $false))
    }
    $lines.Add(@('', 'FFFFFF', $false))
    if ($s.Typing) {
        $cursor = if ([int]($script:Clock.Elapsed.TotalSeconds * 2) % 2) { '_' } else { ' ' }
        $lines.Add(@("Address of the host:  $($s.Input)$cursor", 'FFFFFF', $true))
        $lines.Add(@("Enter joins (port $($script:NetPort))     Backspace     Esc cancels", 'FFE860', $false))
    }
    else {
        $lines.Add(@('[Up/Down] choose    [Enter] join    [A] an address by hand    [R] search again', 'FFE860', $false))
        $lines.Add(@('[C] host co-op    [D] host deathmatch    [Esc] back', 'FFE860', $false))
    }
    if ($s.Message) { $lines.Add(@('', 'FFFFFF', $false)); $lines.Add(@($s.Message, 'FF8070', $false)) }
    $lines.Add(@('', 'FFFFFF', $false))
    $lines.Add(@('Only games on this network show up. Over the internet, join by address - the host opens port', '506080', $false))
    $lines.Add(@("$($script:NetPort) in the router. -PlayerName sets the name the others see.", '506080', $false))
    $lines
}

function Show-NetBrowser {
    $g = $script:BackG; $s = $script:Scale
    Show-Shade 'FF0A1020'
    $g.DrawString('>', $script:Fonts.Giant, (Get-Brush 'FF0F1A36'), [single](196 * $s), [single](44 * $s))      # the title screen's backdrop
    for ($y = 6; $y -lt 236; $y += 4) { Write-HudBar '0CFFFFFF' 0 $y 320 0.4 }
    Write-HudBar '2C54C4' 0 0 320 3; Write-HudBar '2C54C4' 0 237 320 3
    $y = 14.0
    foreach ($line in (Get-NetBrowserLines)) {
        if ($line[2]) { Write-HudBar 'FF2C54C4' 12 ($y - 0.6) 296 6.6 }
        $g.DrawString($line[0], $script:Fonts.Term, (Get-Brush $line[1]), [single](16 * $s), [single]($y * $s))
        $y += 7.0
    }
}
