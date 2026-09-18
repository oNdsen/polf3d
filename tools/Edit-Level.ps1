# POLF 3D - Copyright (c) 2026 oNdsen. Licensed under the MIT License, see LICENSE.

<#
.SYNOPSIS
    A point-and-click editor for POLF 3D maps.
.DESCRIPTION
    Pick a tile on the left, paint with the left mouse button, erase to floor with the right one,
    pick up the tile under the cursor with the middle one. Enemies, the player start and patrol
    waypoints take their direction (and, for enemies, their behaviour) from the two boxes below
    the palette. "Validate" runs tools/Test-Level.ps1 on the saved file, "Play" starts the game
    on it.
.PARAMETER Map
    The map to open. Without it the editor starts with an empty 32x24 map.
.EXAMPLE
    ./tools/Edit-Level.ps1 ./maps/level1.map
#>
[CmdletBinding()]
param(
    [string]$Map,
    [Parameter(DontShow)][string]$SelfTestOut            # test aid: load, paint one cell, save here, exit
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms, System.Drawing

$script:Cell = 18
$script:Path = $null
$script:W = 32; $script:H = 24
$script:Grid = $null
$script:Dirty = $false

# ---- palette: code, description, kind (tile | dir = needs a direction | enemy = direction + behaviour) ----------
$script:Palette = @(
    @('..', 'Floor', 'tile'), @('P^', 'Player start', 'dir'),
    @('SS', 'Wall: stone', 'tile'), @('Sb', 'Wall: stone, banner', 'tile'), @('Sp', 'Wall: stone, picture', 'tile'),
    @('BB', 'Wall: blue stone', 'tile'), @('Bc', 'Wall: blue stone, cell', 'tile'),
    @('WW', 'Wall: wood', 'tile'), @('Wp', 'Wall: wood, portrait', 'tile'), @('Ws', 'Wall: wood, shield', 'tile'),
    @('RR', 'Wall: brick', 'tile'), @('Rb', 'Wall: brick, banner', 'tile'), @('MM', 'Wall: steel', 'tile'),
    @('GG', 'Wall: mossy rock', 'tile'), @('Gv', 'Wall: mossy rock, vines', 'tile'), @('TT', 'Wall: tech', 'tile'), @('Tl', 'Wall: tech, console', 'tile'),
    @('St', 'Wall: stone, PS console', 'tile'), @('Bt', 'Wall: blue stone, PS console', 'tile'), @('Wt', 'Wall: wood, PS console', 'tile'), @('Rt', 'Wall: brick, PS console', 'tile'),
    @('Mt', 'Wall: steel, PS console', 'tile'), @('Gt', 'Wall: mossy rock, dead console', 'tile'), @('Tt', 'Wall: tech, PS console', 'tile'),
    @('Sh', 'Wall: stone, Get-Help poster', 'tile'), @('Wh', 'Wall: wood, Get-Help poster', 'tile'), @('Rh', 'Wall: brick, Get-Help poster', 'tile'),
    @('Me', 'Wall: steel, error screen', 'tile'), @('Te', 'Wall: tech, error screen', 'tile'), @('Mn', 'Wall: steel, neon prompt', 'tile'), @('Tn', 'Wall: tech, neon prompt', 'tile'),
    @('Rg', 'Wall: brick, graffiti', 'tile'), @('Sg', 'Wall: stone, graffiti', 'tile'),
    @('MX', 'Lift switch (exit)', 'tile'), @('MY', 'Secret lift switch (bonus floor)', 'tile'),
    @('DD', 'Door', 'tile'), @('DG', 'Door: gold lock', 'tile'), @('DS', 'Door: silver lock', 'tile'), @('DL', 'Door: lift', 'tile'),
    @('D1', 'Remote door 1', 'tile'), @('X1', 'Lever 1', 'tile'), @('D2', 'Remote door 2', 'tile'), @('X2', 'Lever 2', 'tile'),
    @('?S', 'Push-wall: stone', 'tile'), @('?s', 'Push-wall: stone, banner', 'tile'), @('?W', 'Push-wall: wood', 'tile'), @('?w', 'Push-wall: wood, portrait', 'tile'),
    @('?B', 'Push-wall: blue', 'tile'), @('?R', 'Push-wall: brick', 'tile'), @('?M', 'Push-wall: steel', 'tile'), @('?G', 'Push-wall: moss', 'tile'), @('?T', 'Push-wall: tech', 'tile'),
    @('!S', 'Cracked wall: stone', 'tile'), @('!M', 'Cracked wall: steel', 'tile'), @('!T', 'Cracked wall: tech', 'tile'), @('!G', 'Cracked wall: moss', 'tile'),
    @('=S', 'Window: stone', 'tile'), @('=T', 'Window: tech', 'tile'), @('=W', 'Window: wood', 'tile'), @('=R', 'Window: brick', 'tile'),
    @('g^', 'Enemy: guard', 'enemy'), @('d^', 'Enemy: dog', 'enemy'), @('o^', 'Enemy: officer', 'enemy'), @('e^', 'Enemy: elite', 'enemy'),
    @('m^', 'Enemy: mutant', 'enemy'), @('s^', 'Enemy: sniper', 'enemy'), @('h^', 'Enemy: shield bearer', 'enemy'), @('k^', 'Enemy: kamikaze bot', 'enemy'),
    @('b^', 'Boss: commander', 'enemy'), @('u^', 'Boss: war machine', 'enemy'), @(':^', 'Patrol waypoint', 'dir'),
    @('+a', 'Item: clip', 'tile'), @('+h', 'Item: first aid', 'tile'), @('+f', 'Item: food', 'tile'), @('+d', 'Item: dog food', 'tile'),
    @('+m', 'Item: machine gun', 'tile'), @('+c', 'Item: chain gun', 'tile'), @('+p', 'Item: Pipeline Cannon', 'tile'), @('+r', 'Item: Force Blaster', 'tile'), @('+z', 'Item: Force charge', 'tile'),
    @('+l', 'Item: rocket launcher', 'tile'), @('+o', 'Item: rockets', 'tile'), @('+t', 'Item: flamethrower', 'tile'), @('+j', 'Item: throwing knives', 'tile'),
    @('+g', 'Item: gold key', 'tile'), @('+s', 'Item: silver key', 'tile'), @('+q', 'Item: SUDO', 'tile'), @('+u', 'Item: extra life', 'tile'),
    @('+1', 'Treasure: coins', 'tile'), @('+2', 'Treasure: goblet', 'tile'), @('+3', 'Treasure: chest', 'tile'), @('+4', 'Treasure: crown', 'tile'),
    @('*e', 'Explosive barrel', 'tile'), @('*b', 'Deco: barrel', 'tile'), @('*c', 'Deco: column', 'tile'), @('*t', 'Deco: table', 'tile'), @('*x', 'Deco: crates', 'tile'),
    @('*l', 'Deco: ceiling lamp', 'tile'), @('*h', 'Deco: chandelier', 'tile'), @('*L', 'Deco: floor lamp', 'tile'), @('*p', 'Deco: plant', 'tile'), @('*a', 'Deco: armour', 'tile'),
    @('*f', 'Deco: flag', 'tile'), @('*v', 'Deco: vat', 'tile'), @('*B', 'Deco: bed', 'tile'), @('*m', 'Deco: console', 'tile'), @('*r', 'Deco: server rack', 'tile'), @('*T', 'Deco: desk with terminal', 'tile'), @('*n', 'Deco: neon prompt sign', 'tile'), @('*g', 'Deco: stalagmite', 'tile'),
    @('*s', 'Deco: bones', 'tile'), @('*u', 'Deco: puddle', 'tile'), @('*k', 'Deco: dead guard', 'tile'),
    @('~s', 'Trap: spikes', 'tile'), @('~c', 'Trap: crusher', 'tile'), @('@1', 'Teleporter pair 1', 'tile'), @('@2', 'Teleporter pair 2', 'tile')
)

function Get-CellColors([string]$Code) {                       # background, text
    $c = $Code[0]
    switch -CaseSensitive -Regex ($Code) {
        '^\.\.$'       { return '2A2A2A', '2A2A2A' }
        '^MX$|^MY$'    { return 'D02020', 'FFFFFF' }
        '^D'           { return '30B0B8', '000000' }
        '^X'           { return 'E040E0', '000000' }
        '^\?'          { return '7A4AA0', 'FFFFFF' }
        '^!'           { return 'C07020', '000000' }
        '^='           { return 'A0D0FF', '000000' }
        '^S'           { return '8A8A8A', '000000' }
        '^B'           { return '3048B8', 'FFFFFF' }
        '^W'           { return '8A5A28', 'FFFFFF' }
        '^R'           { return 'A43828', 'FFFFFF' }
        '^M'           { return '7A8A9A', '000000' }
        '^G'           { return '5A7A4A', 'FFFFFF' }
        '^T'           { return '4A6A80', 'FFFFFF' }
        '^P'           { return '2A2A2A', 'FFE040' }
        '^\+'          { return '2A2A2A', '60FF80' }
        '^\*'          { return '2A2A2A', 'C09060' }
        '^~'           { return '2A2A2A', 'FF9020' }
        '^@'           { return '2A2A2A', '40E0FF' }
        '^:'           { return '2A2A2A', 'FFFFFF' }
        default        { return '2A2A2A', 'FF5050' }               # enemies
    }
}

function New-EmptyMap([int]$Width, [int]$Height) {
    $script:W = $Width; $script:H = $Height
    $script:Grid = New-Object 'string[,]' $Width, $Height
    for ($y = 0; $y -lt $Height; $y++) { for ($x = 0; $x -lt $Width; $x++) {
        $edge = $x -eq 0 -or $y -eq 0 -or $x -eq $Width - 1 -or $y -eq $Height - 1
        $script:Grid[$x, $y] = if ($edge) { 'SS' } else { '..' }
    } }
    $script:Header = [ordered]@{ name = 'New floor'; par = '180'; ceiling = '383838'; floor = '6E6E6E'; floortex = 'flat_stone'; ceiltex = 'ceil_plain'; fog = '101010 16' }
    $script:ExtraLines = @()
}

function Import-Map([string]$File) {
    $script:Header = [ordered]@{}; $script:ExtraLines = @(); $rows = @(); $inMap = $false
    foreach ($line in [System.IO.File]::ReadAllLines($File)) {
        if ($inMap) { if ($line.Trim()) { $rows += $line.TrimEnd() }; continue }
        if ($line.StartsWith('@map')) { $inMap = $true }
        elseif ($line.StartsWith('@spawn') -or $line.StartsWith(';')) { $script:ExtraLines += $line }
        elseif ($line.StartsWith('@')) { $p = $line.Substring(1).Split(' ', 2); $script:Header[$p[0].ToLower()] = "$($p[1])".Trim() }
    }
    if (-not $rows) { throw "No @map block in $File" }
    $script:W = [int]($rows[0].Length / 2); $script:H = $rows.Count
    $script:Grid = New-Object 'string[,]' $script:W, $script:H
    for ($y = 0; $y -lt $script:H; $y++) { for ($x = 0; $x -lt $script:W; $x++) { $script:Grid[$x, $y] = $rows[$y].Substring($x * 2, 2) } }
    $script:Path = $File; $script:Dirty = $false
}

function Export-Map([string]$File) {
    $lines = [System.Collections.Generic.List[string]]::new()
    foreach ($l in $script:ExtraLines) { if ($l.StartsWith(';')) { $lines.Add($l) } }
    foreach ($k in $script:Header.Keys) { if ("$($script:Header[$k])") { $lines.Add("@$k $($script:Header[$k])") } }
    foreach ($l in $script:ExtraLines) { if ($l.StartsWith('@spawn')) { $lines.Add($l) } }
    $lines.Add('@map')
    for ($y = 0; $y -lt $script:H; $y++) {
        $sb = [System.Text.StringBuilder]::new()
        for ($x = 0; $x -lt $script:W; $x++) { $null = $sb.Append($script:Grid[$x, $y]) }
        $lines.Add($sb.ToString())
    }
    [System.IO.File]::WriteAllLines($File, $lines)
    $script:Path = $File; $script:Dirty = $false
}

# ---- drawing ---------------------------------------------------------------------------------------
$script:BrushCache = @{}
function Get-EditorBrush([string]$Hex) {
    if (-not $script:BrushCache[$Hex]) { $script:BrushCache[$Hex] = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb([Convert]::ToInt32("FF$Hex", 16))) }
    $script:BrushCache[$Hex]
}

function Show-Cell([int]$X, [int]$Y) {
    $code = $script:Grid[$X, $Y]; $bg, $fg = Get-CellColors $code; $c = $script:Cell
    $script:CanvasG.FillRectangle((Get-EditorBrush $bg), $X * $c, $Y * $c, $c - 1, $c - 1)
    if ($code -ne '..' -and $bg -eq '2A2A2A' -or $code -cmatch '^(MX|MY|D.|X.|\?.|!.|=.|.[a-z])$') {
        $script:CanvasG.DrawString($code, $script:CellFont, (Get-EditorBrush $fg), $X * $c - 1, $Y * $c + 2)
    }
}

function Show-AllCells {
    $script:CanvasBmp = [System.Drawing.Bitmap]::new($script:W * $script:Cell, $script:H * $script:Cell)
    $script:CanvasG = [System.Drawing.Graphics]::FromImage($script:CanvasBmp)
    $script:CanvasG.Clear([System.Drawing.Color]::Black)
    for ($y = 0; $y -lt $script:H; $y++) { for ($x = 0; $x -lt $script:W; $x++) { Show-Cell $x $y } }
    $script:Canvas.Image = $script:CanvasBmp
    $script:Canvas.Size = $script:CanvasBmp.Size
}

# The code the brush paints right now: palette entry plus direction and behaviour where needed.
function Get-BrushCode {
    $entry = $script:Palette[[Math]::Max(0, $script:List.SelectedIndex)]
    if ($entry[2] -eq 'tile') { return $entry[0] }
    $dir = [Math]::Max(0, $script:DirBox.SelectedIndex)
    $set = if ($entry[2] -eq 'enemy') { ('^>v<', 'nesw', 'NESW')[[Math]::Max(0, $script:ModeBox.SelectedIndex)] } else { '^>v<' }
    "$($entry[0][0])$($set[$dir])"
}

function Set-CellCode([int]$X, [int]$Y, [string]$Code) {
    if ($X -lt 0 -or $Y -lt 0 -or $X -ge $script:W -or $Y -ge $script:H -or $script:Grid[$X, $Y] -ceq $Code) { return }
    $script:Grid[$X, $Y] = $Code; $script:Dirty = $true
    Show-Cell $X $Y
    $script:Canvas.Invalidate([System.Drawing.Rectangle]::new($X * $script:Cell, $Y * $script:Cell, $script:Cell, $script:Cell))
}

function Invoke-CanvasMouse($e) {
    $x = [int][Math]::Floor($e.X / $script:Cell); $y = [int][Math]::Floor($e.Y / $script:Cell)
    if ($x -lt 0 -or $y -lt 0 -or $x -ge $script:W -or $y -ge $script:H) { return }
    $script:Status.Text = "$x, $y   '$($script:Grid[$x, $y])'   brush '$(Get-BrushCode)'$(if ($script:Dirty) { '   (unsaved)' })"
    switch ($e.Button) {
        'Left'   { Set-CellCode $x $y (Get-BrushCode) }
        'Right'  { Set-CellCode $x $y '..' }
        'Middle' {
            $code = $script:Grid[$x, $y]
            for ($i = 0; $i -lt $script:Palette.Count; $i++) {
                $p = $script:Palette[$i]
                if ($p[0] -ceq $code -or ($p[2] -ne 'tile' -and $p[0][0] -ceq $code[0])) { $script:List.SelectedIndex = $i; break }
            }
        }
    }
}

function Save-CurrentMap([bool]$AskName) {
    foreach ($k in @($script:HeaderBoxes.Keys)) { $script:Header[$k] = $script:HeaderBoxes[$k].Text.Trim() }
    $file = $script:Path
    if ($AskName -or -not $file) {
        $dlg = [System.Windows.Forms.SaveFileDialog]::new()
        $dlg.Filter = 'POLF 3D map (*.map)|*.map'; $dlg.InitialDirectory = (Resolve-Path (Join-Path $PSScriptRoot '../maps')).Path
        if ($dlg.ShowDialog() -ne 'OK') { return $false }
        $file = $dlg.FileName
    }
    Export-Map $file
    $script:Form.Text = "POLF 3D level editor - $file"
    $true
}

function Invoke-External([string]$Script, [string[]]$Arguments, [bool]$Capture) {
    $pwsh = (Get-Process -Id $PID).Path
    $argList = @('-NoProfile', '-File', (Join-Path $PSScriptRoot $Script)) + $Arguments
    if (-not $Capture) { Start-Process -FilePath $pwsh -ArgumentList $argList; return }
    (& $pwsh @argList 2>&1 | Out-String) -replace '\x1b\[[0-9;]*m'
}

# ---- window ------------------------------------------------------------------------------------------
if ($Map) { Import-Map (Resolve-Path -LiteralPath $Map).Path } else { New-EmptyMap 32 24 }

$script:Form = [System.Windows.Forms.Form]::new()
$script:Form.Text = "POLF 3D level editor - $(if ($script:Path) { $script:Path } else { 'new map' })"
$script:Form.ClientSize = [System.Drawing.Size]::new(1280, 800)
$script:Form.StartPosition = 'CenterScreen'
$script:CellFont = [System.Drawing.Font]::new('Consolas', 7.5, [System.Drawing.FontStyle]::Bold)

$side = [System.Windows.Forms.Panel]::new(); $side.Dock = 'Left'; $side.Width = 270
$script:List = [System.Windows.Forms.ListBox]::new(); $script:List.Dock = 'Fill'; $script:List.Font = [System.Drawing.Font]::new('Consolas', 9)
foreach ($p in $script:Palette) { $null = $script:List.Items.Add("$($p[0])  $($p[1])") }
$script:List.SelectedIndex = 2

$opts = [System.Windows.Forms.FlowLayoutPanel]::new(); $opts.Dock = 'Bottom'; $opts.Height = 330; $opts.FlowDirection = 'TopDown'; $opts.WrapContents = $false
$script:DirBox = [System.Windows.Forms.ComboBox]::new(); $script:DirBox.DropDownStyle = 'DropDownList'; $script:DirBox.Width = 250
$null = $script:DirBox.Items.AddRange(@('faces north', 'faces east', 'faces south', 'faces west')); $script:DirBox.SelectedIndex = 0
$script:ModeBox = [System.Windows.Forms.ComboBox]::new(); $script:ModeBox.DropDownStyle = 'DropDownList'; $script:ModeBox.Width = 250
$null = $script:ModeBox.Items.AddRange(@('standing', 'standing, deaf (ambush)', 'patrolling')); $script:ModeBox.SelectedIndex = 0
$opts.Controls.AddRange(@($script:DirBox, $script:ModeBox))
$script:HeaderBoxes = [ordered]@{}
foreach ($k in 'name', 'par', 'ceiling', 'floor', 'floortex', 'ceiltex', 'fog') {
    $lbl = [System.Windows.Forms.Label]::new(); $lbl.Text = "@$k"; $lbl.AutoSize = $true
    $box = [System.Windows.Forms.TextBox]::new(); $box.Width = 250; $box.Text = "$($script:Header[$k])"
    $script:HeaderBoxes[$k] = $box
    $opts.Controls.AddRange(@($lbl, $box))
}
$side.Controls.Add($script:List); $side.Controls.Add($opts)

$bar = [System.Windows.Forms.FlowLayoutPanel]::new(); $bar.Dock = 'Top'; $bar.Height = 34
$script:Status = [System.Windows.Forms.Label]::new(); $script:Status.Dock = 'Bottom'; $script:Status.Height = 20; $script:Status.Font = [System.Drawing.Font]::new('Consolas', 9)
$scroll = [System.Windows.Forms.Panel]::new(); $scroll.Dock = 'Fill'; $scroll.AutoScroll = $true; $scroll.BackColor = [System.Drawing.Color]::FromArgb(255, 16, 16, 16)
$script:Canvas = [System.Windows.Forms.PictureBox]::new(); $script:Canvas.Location = [System.Drawing.Point]::new(0, 0)
$scroll.Controls.Add($script:Canvas)

$buttons = [ordered]@{
    'New ...'  = {
        $size = [Microsoft.VisualBasic.Interaction]::InputBox('Width x height in tiles (max 64x64):', 'New map', '32x24')
        if ($size -match '^(\d+)\s*x\s*(\d+)$') { New-EmptyMap ([Math]::Min(64, [int]$Matches[1])) ([Math]::Min(64, [int]$Matches[2])); $script:Path = $null; Show-AllCells; foreach ($k in @($script:HeaderBoxes.Keys)) { $script:HeaderBoxes[$k].Text = "$($script:Header[$k])" } }
    }
    'Open ...' = {
        $dlg = [System.Windows.Forms.OpenFileDialog]::new(); $dlg.Filter = 'POLF 3D map (*.map)|*.map'; $dlg.InitialDirectory = (Resolve-Path (Join-Path $PSScriptRoot '../maps')).Path
        if ($dlg.ShowDialog() -eq 'OK') { Import-Map $dlg.FileName; Show-AllCells; foreach ($k in @($script:HeaderBoxes.Keys)) { $script:HeaderBoxes[$k].Text = "$($script:Header[$k])" }; $script:Form.Text = "POLF 3D level editor - $($dlg.FileName)" }
    }
    'Save'        = { $null = Save-CurrentMap $false }
    'Save as ...' = { $null = Save-CurrentMap $true }
    'Validate'    = { if (Save-CurrentMap $false) { [System.Windows.Forms.MessageBox]::Show((Invoke-External 'Test-Level.ps1' @('-Map', $script:Path) $true), 'Test-Level') } }
    'Play'        = { if (Save-CurrentMap $false) { Invoke-External '../Start-Polf3D.ps1' @('-Map', $script:Path) $false } }
}
foreach ($name in $buttons.Keys) {
    $b = [System.Windows.Forms.Button]::new(); $b.Text = $name; $b.AutoSize = $true
    $b.Add_Click($buttons[$name]); $bar.Controls.Add($b)
}
Add-Type -AssemblyName Microsoft.VisualBasic

$script:Canvas.Add_MouseDown({ param($s, $e) Invoke-CanvasMouse $e })
$script:Canvas.Add_MouseMove({ param($s, $e) Invoke-CanvasMouse $e })
$script:Form.Add_FormClosing({ param($s, $e)
        if ($script:Dirty -and -not $SelfTestOut) {
            $answer = [System.Windows.Forms.MessageBox]::Show('Save the changes?', 'POLF 3D level editor', 'YesNoCancel')
            if ($answer -eq 'Cancel') { $e.Cancel = $true } elseif ($answer -eq 'Yes') { if (-not (Save-CurrentMap $false)) { $e.Cancel = $true } }
        }
    })

$script:Form.Controls.AddRange(@($scroll, $side, $bar, $script:Status))
Show-AllCells

if ($SelfTestOut) {
    # headless smoke test: paint a guard, save, reload, compare
    $script:Form.Show(); [System.Windows.Forms.Application]::DoEvents()
    $script:List.SelectedIndex = [Array]::IndexOf(@($script:Palette | ForEach-Object { $_[0] }), 'g^'); $script:DirBox.SelectedIndex = 1; $script:ModeBox.SelectedIndex = 2
    $free = $null
    for ($y = 1; $y -lt $script:H -and -not $free; $y++) { for ($x = 1; $x -lt $script:W; $x++) { if ($script:Grid[$x, $y] -eq '..') { $free = @($x, $y); break } } }
    Set-CellCode $free[0] $free[1] (Get-BrushCode)
    Export-Map $SelfTestOut
    [System.Windows.Forms.Application]::DoEvents()
    $shot = [System.Drawing.Bitmap]::new($script:Form.Width, $script:Form.Height)
    $script:Form.DrawToBitmap($shot, [System.Drawing.Rectangle]::new(0, 0, $shot.Width, $shot.Height)); $shot.Save("$SelfTestOut.png"); $shot.Dispose()
    Import-Map $SelfTestOut
    $script:Form.Close()
    if ($script:Grid[$free[0], $free[1]] -cne 'gE') { throw "editor self-test failed: found '$($script:Grid[$free[0], $free[1]])'" }
    "editor self-test ok: painted 'gE' at $($free -join ','), map $($script:W)x$($script:H) round-tripped"
    return
}
[System.Windows.Forms.Application]::Run($script:Form)
