# POLF 3D - Copyright (c) 2026 oNdsen. Licensed under the MIT License, see LICENSE.

# GifExport.ps1 - turns a demo into an animated GIF (./Start-Polf3D.ps1 -ExportGif demo.json). The demo is played
# back without a window, as the demo verifier does, and ten times a second the view is kept. The colours are
# reduced by Windows itself (WPF: one palette, median cut, from a sheet of frames taken all over the clip - one
# palette for all frames keeps the picture from flickering), every frame is encoded as a GIF of its own, and
# those are stitched together here: header, NETSCAPE loop block, then per frame a graphic control block with the
# delay in front of the frame's image descriptor, colour table and data.

$script:GIF_FPS = 10

# The part of a single-frame GIF that is the frame: from its image descriptor (0x2C) up to the trailer.
function Get-GifFrameBytes([byte[]]$Gif) {
    $pos = 13
    if ($Gif[10] -band 0x80) { $pos += 3 * (1 -shl (($Gif[10] -band 7) + 1)) }                    # a global colour table
    while ($Gif[$pos] -eq 0x21) { $pos += 2; while ($Gif[$pos] -ne 0) { $pos += $Gif[$pos] + 1 }; $pos++ }      # extension blocks
    if ($Gif[$pos] -ne 0x2C) { throw 'GIF export: the encoder produced a frame this code cannot read.' }
    $frame = [byte[]]::new($Gif.Length - 1 - $pos)
    [Array]::Copy($Gif, $pos, $frame, 0, $frame.Length)
    , $frame
}

# Every pixel becomes $Scale x $Scale pixels - no smoothing, these are meant to be blocky.
function Resize-GifFrame([int[]]$Pixels, [int]$Width, [int]$Height, [int]$Scale) {
    $wide = $Width * $Scale
    $row = [int[]]::new($wide); $big = [int[]]::new($wide * $Height * $Scale)
    for ($y = 0; $y -lt $Height; $y++) {
        $at = $y * $Width
        for ($x = 0; $x -lt $Width; $x++) { $v = $Pixels[$at + $x]; for ($k = 0; $k -lt $Scale; $k++) { $row[$x * $Scale + $k] = $v } }
        for ($k = 0; $k -lt $Scale; $k++) { [Array]::Copy($row, 0, $big, ($y * $Scale + $k) * $wide, $wide) }
    }
    , $big
}

# $Frames: int[] pictures (0xAARRGGBB), all $Width x $Height.
function Export-Gif([string]$Path, [object[]]$Frames, [int]$Width, [int]$Height, [int]$Scale = 1) {
    Add-Type -AssemblyName PresentationCore, WindowsBase
    $bgr = [System.Windows.Media.PixelFormats]::Bgr32; $indexed = [System.Windows.Media.PixelFormats]::Indexed8
    # one palette for the whole clip: from up to eight frames, stacked
    $picks = @(for ($i = 0; $i -lt [Math]::Min(8, $Frames.Count); $i++) { , $Frames[[int]($i * ($Frames.Count - 1) / [Math]::Max(1, [Math]::Min(8, $Frames.Count) - 1))] })
    $sheet = [int[]]::new($Width * $Height * $picks.Count)
    for ($i = 0; $i -lt $picks.Count; $i++) { [Array]::Copy($picks[$i], 0, $sheet, $i * $Width * $Height, $Width * $Height) }
    $palette = [System.Windows.Media.Imaging.BitmapPalette]::new([System.Windows.Media.Imaging.BitmapSource]::Create($Width, $Height * $picks.Count, 96, 96, $bgr, $null, $sheet, $Width * 4), 256)

    $out = [System.IO.MemoryStream]::new()
    $w = $Width * $Scale; $h = $Height * $Scale
    $out.Write([byte[]](0x47, 0x49, 0x46, 0x38, 0x39, 0x61, ($w -band 255), ($w -shr 8), ($h -band 255), ($h -shr 8), 0x70, 0, 0), 0, 13)      # GIF89a, no global table
    $out.Write([byte[]](0x21, 0xFF, 0x0B, 0x4E, 0x45, 0x54, 0x53, 0x43, 0x41, 0x50, 0x45, 0x32, 0x2E, 0x30, 0x03, 0x01, 0, 0, 0), 0, 19)       # NETSCAPE2.0: loop for ever
    $delay = [int](100 / $script:GIF_FPS)
    foreach ($pixels in $Frames) {
        if ($Scale -gt 1) { $pixels = Resize-GifFrame $pixels $Width $Height $Scale }
        $source = [System.Windows.Media.Imaging.BitmapSource]::Create($w, $h, 96, 96, $bgr, $null, $pixels, $w * 4)
        $converted = [System.Windows.Media.Imaging.FormatConvertedBitmap]::new($source, $indexed, $palette, 0)
        $encoder = [System.Windows.Media.Imaging.GifBitmapEncoder]::new()
        $encoder.Frames.Add([System.Windows.Media.Imaging.BitmapFrame]::Create($converted))
        $one = [System.IO.MemoryStream]::new(); $encoder.Save($one)
        $frame = Get-GifFrameBytes $one.ToArray(); $one.Dispose()
        $out.Write([byte[]](0x21, 0xF9, 0x04, 0x00, ($delay -band 255), ($delay -shr 8), 0, 0), 0, 8)                                          # graphic control: the delay
        $out.Write($frame, 0, $frame.Length)
    }
    $out.WriteByte(0x3B)
    [System.IO.File]::WriteAllBytes($Path, $out.ToArray()); $out.Dispose()
}

# Plays a demo back and keeps the view ten times a second, from $Start seconds in, for $Seconds seconds.
function Export-DemoGif([string]$DemoPath, [string]$GifPath, [double]$Start = 0, [double]$Seconds = 12, [int]$Scale = 1) {
    $script:KeyDown = [bool[]]::new(256); $script:KeyHit = [System.Collections.Generic.Queue[int]]::new(); $script:Mode = 'play'
    $script:GodMode = $false; $script:InfiniteAmmo = $false; $script:OneHitKill = $false
    if (-not (Start-DemoPlayback $DemoPath)) { Write-Step "GIF export: $($script:Message)"; return $false }
    $frames = [System.Collections.Generic.List[object]]::new()
    $clock = 0.0; $next = $Start * $script:TICRATE; $end = ($Start + $Seconds) * $script:TICRATE; $step = $script:TICRATE / $script:GIF_FPS
    while ($null -ne ($frame = Get-DemoFrame)) {
        Update-View
        if ($clock -ge $next -and $clock -lt $end) { $frames.Add($script:FB.Clone()); $next += $step }
        Update-World $frame.Tics $frame.In; $clock += $frame.Tics
        if ($script:PlayerDied -or $script:LevelDone -or $clock -ge $end) { break }
    }
    Stop-Dungeon
    if (-not $frames.Count) { Write-Step "GIF export: the demo is over before second $Start."; return $false }
    Write-Step "GIF export: $($frames.Count) frames of $($script:ViewW)x$($script:ViewH) - reducing the colours and encoding ..."
    Export-Gif $GifPath $frames.ToArray() $script:ViewW $script:ViewH $Scale
    Write-Step ("GIF export: {0}  ({1:0.0} s, {2:0.0} MB)" -f $GifPath, ($frames.Count / $script:GIF_FPS), ((Get-Item -LiteralPath $GifPath).Length / 1MB))
    $true
}
