# POLF 3D - Copyright (c) 2026 oNdsen. Licensed under the MIT License, see LICENSE.

# Music.ps1 - procedural chiptune. The title screen has its own anthem and every floor a loop in
# a loop of its own in a style that suits it (rock, march, crypt, techno, finale; the secret floor gets a jolly tune).
# A track is composed in code - chord progression, bass, lead, drums - rendered to a WAV file
# once and cached in bin/music.
#
# Rendering trick: a note is one short wave pattern copied over and over with Buffer.BlockCopy,
# and the channels are mixed with SIMD vectors, so PowerShell never has to loop over the
# individual samples of a whole track.
# Playback is the mixer's job (src/Mixer.cs): it loops a track without the slightest gap.

$script:MUSIC_RATE = 22050
$script:MUSIC_VERSION = 3                       # bump to invalidate cached tracks
$script:MUSIC_BONUS = 99                        # track number of the secret floor
$script:MUSIC_ENDING = 98                       # ... and of the epilogue
$script:MusicEnabled = $true
$script:MusicIds = @{}                          # track -> the mixer's id of its samples
$script:MusicTrack = -1

# Tempo (beats per minute), Root (Hz of scale step 0 in the bass octave), Bars (4/4, sixteen steps each),
# Scale (semitones) and Chords (one per bar, repeated: semitone offset + m/M for minor/major).
$script:MusicStyles = @{
    anthem   = @{ Tempo = 104; Root = 73.42; Bars = 16; Scale = 0, 2, 3, 5, 7, 8, 10; Chords = '0m', '0m', '8M', '10M', '0m', '5m', '7M', '0m' }
    rock     = @{ Tempo = 152; Root = 82.41; Bars = 16; Scale = 0, 3, 5, 6, 7, 10;    Chords = '0m', '0m', '0m', '0m', '5m', '5m', '0m', '0m', '7m', '5m', '0m', '0m', '0m', '0m', '7m', '7m' }
    march    = @{ Tempo = 116; Root = 98.0;  Bars = 16; Scale = 0, 2, 3, 5, 7, 8, 10; Chords = '0m', '0m', '5m', '0m', '8M', '3M', '7M', '0m' }
    crypt    = @{ Tempo = 66;  Root = 65.41; Bars = 8;  Scale = 0, 1, 3, 6, 7, 8, 11; Chords = '0m', '0m', '1M', '0m', '-2m', '0m', '6m', '1M' }
    techno   = @{ Tempo = 138; Root = 55.0;  Bars = 16; Scale = 0, 2, 3, 5, 7, 8, 10; Chords = '0m', '0m', '0m', '0m', '8M', '8M', '10M', '10M' }
    finale   = @{ Tempo = 164; Root = 73.42; Bars = 16; Scale = 0, 2, 3, 5, 7, 8, 11; Chords = '0m', '0m', '8M', '7M', '0m', '5m', '7M', '7M' }
    ending   = @{ Tempo = 92;  Root = 65.41; Bars = 32; Scale = 0, 2, 4, 5, 7, 9, 11;    Chords = '0M', '7M', '9m', '5M', '0M', '7M', '5M', '0M', '5M', '7M', '4m', '9m', '5M', '7M', '0M', '0M' }
    treasure = @{ Tempo = 126; Root = 65.41; Bars = 16; Scale = 0, 2, 4, 7, 9;        Chords = '0M', '0M', '5M', '0M', '9m', '5M', '7M', '0M' }
}

# Track 0 = title screen, track N = floor N (further floors cycle through the list), 99 = secret floor.
# Dungeon, barracks, catacombs, lab, citadel - data centre, archive, foundry, executive floor, ring 0.
$script:FloorStyles = 'rock', 'march', 'crypt', 'techno', 'finale', 'techno', 'crypt', 'rock', 'march', 'finale'
function Get-MusicStyle([int]$Track) {
    if ($Track -le 0) { return 'anthem' }
    if ($Track -eq $script:MUSIC_BONUS) { return 'treasure' }
    if ($Track -eq $script:MUSIC_ENDING) { return 'ending' }
    $script:FloorStyles[($Track - 1) % $script:FloorStyles.Count]
}

# ---------------------------------------------------------------------------------------------
# Building blocks
# ---------------------------------------------------------------------------------------------
# Fills $Buf[$Start .. $Start+$Length) by repeating $Pattern (both int16[]).
function Copy-Pattern([int16[]]$Buf, [int]$Start, [int]$Length, [int16[]]$Pattern) {
    if ($Start -lt 0 -or $Start -ge $Buf.Length -or $Length -le 0) { return }
    if ($Start + $Length -gt $Buf.Length) { $Length = $Buf.Length - $Start }
    $first = [Math]::Min($Pattern.Length, $Length)
    [Buffer]::BlockCopy($Pattern, 0, $Buf, $Start * 2, $first * 2)
    $done = $first
    while ($done -lt $Length) {                  # double the filled stretch until the note is full
        $n = [Math]::Min($done, $Length - $done)
        [Buffer]::BlockCopy($Buf, $Start * 2, $Buf, ($Start + $done) * 2, $n * 2)
        $done += $n
    }
}

# A few periods of a wave at amplitude +-127. Several periods, because one period is a whole number of
# samples and that alone would put the higher notes noticeably out of tune.
#   square | pulse (25 %) | thin (12.5 %) | triangle | saw | power (root + fifth: a "distorted guitar")
function New-WaveUnit([double]$Freq, [string]$Wave) {
    if ($Wave -eq 'power') { $Freq /= 2 }                     # root and fifth share a period twice as long
    $best = 1; $bestErr = 1e9
    foreach ($k in 1..5) {
        $exact = $k * $script:MUSIC_RATE / $Freq
        $err = [Math]::Abs($exact - [Math]::Round($exact)) / $exact
        if ($err -lt $bestErr - 1e-9) { $best = $k; $bestErr = $err }
    }
    $len = [Math]::Max(2, [int][Math]::Round($best * $script:MUSIC_RATE / $Freq))
    $p = [int16[]]::new($len)
    switch ($Wave) {
        'square'   { for ($i = 0; $i -lt $len; $i++) { $p[$i] = if ((($i * $best / $len) % 1) -lt 0.5) { 127 } else { -127 } } }
        'pulse'    { for ($i = 0; $i -lt $len; $i++) { $p[$i] = if ((($i * $best / $len) % 1) -lt 0.25) { 127 } else { -127 } } }
        'thin'     { for ($i = 0; $i -lt $len; $i++) { $p[$i] = if ((($i * $best / $len) % 1) -lt 0.125) { 127 } else { -127 } } }
        'triangle' { for ($i = 0; $i -lt $len; $i++) { $p[$i] = [int](127 * (4 * [Math]::Abs((($i * $best / $len) % 1) - 0.5) - 1)) } }
        'saw'      { for ($i = 0; $i -lt $len; $i++) { $p[$i] = [int](127 * (2 * (($i * $best / $len) % 1) - 1)) } }
        'power'    {
            for ($i = 0; $i -lt $len; $i++) {
                $t = $i * $best / $len
                $p[$i] = $(if (((2 * $t) % 1) -lt 0.5) { 63 } else { -63 }) + $(if (((3 * $t) % 1) -lt 0.5) { 63 } else { -63 })
            }
        }
    }
    , $p
}

# The unit wave multiplied by $Amp (1..70) - a vector multiplication, sixteen samples at a time.
function Get-WavePattern([double]$Freq, [int]$Amp, [string]$Wave) {
    $mx = $script:Mx
    $unitKey = "$([Math]::Round($Freq, 2))|$Wave"
    $key = "$unitKey|$Amp"
    $hit = $mx.Patterns[$key]
    if ($hit) { return , $hit }
    $unit = $mx.Units[$unitKey]
    if (-not $unit) {
        $raw = New-WaveUnit $Freq $Wave
        $unit = @{ Length = $raw.Length; Data = [int16[]]::new([int][Math]::Ceiling($raw.Length / 64.0) * 64) }      # padded for the vectors
        [Array]::Copy($raw, $unit.Data, $raw.Length)
        $mx.Units[$unitKey] = $unit
    }
    $vt = [System.Numerics.Vector[int16]]; $n = $vt::Count
    $scaled = [int16[]]::new($unit.Data.Length)
    for ($i = 0; $i -lt $scaled.Length; $i += $n) { $vt::op_Multiply($vt::new($unit.Data, $i), [int16]$Amp).CopyTo($scaled, $i) }
    $p = [int16[]]::new($unit.Length)
    [Array]::Copy($scaled, $p, $unit.Length)
    $mx.Patterns[$key] = $p
    , $p
}

# One note. $Step and $Steps are sixteenths (fractions allowed), $Semi is semitones above the root.
# $Decay < 1 fades the note to that fraction of $Amp, in five audible terraces like an old sound chip.
function Add-Note([int16[]]$Chan, [double]$Step, [double]$Steps, [double]$Semi, [int]$Amp, [string]$Wave, [double]$Decay = 1.0, [double]$Detune = 1.0) {
    $mx = $script:Mx
    $freq = $mx.Root * [Math]::Pow(2, $Semi / 12.0) * $Detune
    $at = [int]($Step * $mx.StepLen); $len = [int]($Steps * $mx.StepLen)
    if ($Decay -ge 1.0) { Copy-Pattern $Chan $at $len (Get-WavePattern $freq $Amp $Wave); return }
    $parts = 5; $seg = [int]($len / $parts)
    for ($i = 0; $i -lt $parts; $i++) {
        $a = [Math]::Max(1, [int]($Amp * [Math]::Pow($Decay, $i / ($parts - 1.0))))
        Copy-Pattern $Chan ($at + $i * $seg) $seg (Get-WavePattern $freq $a $Wave)
    }
}

# Scale step -> semitones (steps beyond the scale continue in the next octave, negative ones below).
function Get-ScaleSemi([int[]]$Scale, [int]$Index) {
    $n = $Scale.Count
    $oct = [int][Math]::Floor($Index / $n)
    12 * $oct + $Scale[$Index - $oct * $n]
}

# A bar of melody written as text, one character per sixteenth:
#   0-9 a-z = scale step   . = rest   - = hold the note before
function Add-Melody {
    param([int16[]]$Chan, [int]$Bar, [string]$Text, [int[]]$Scale, [int]$BaseSemi = 0, [int]$Amp = 30, [string]$Wave = 'square',
        [double]$Decay = 0.5, [double]$Detune = 1.0, [double]$Delay = 0.0, [int]$Shift = 0)
    for ($s = 0; $s -lt $Text.Length; $s++) {
        $c = $Text[$s]
        if ($c -eq '.' -or $c -eq '-') { continue }
        $idx = if ([char]::IsDigit($c)) { [int]$c - 48 } else { [int][char]::ToLower($c) - 87 }
        $hold = 1
        while ($s + $hold -lt $Text.Length -and $Text[$s + $hold] -eq '-') { $hold++ }
        Add-Note $Chan ($Bar * 16 + $s + $Delay) ($hold * 0.92) ($BaseSemi + (Get-ScaleSemi $Scale ($idx + $Shift))) $Amp $Wave $Decay $Detune
    }
}

# Fills a rhythm template (x = note, - = hold, . = rest) with a random walk over the scale and returns
# it in Add-Melody notation. The first note of the bar is pulled onto a note of the chord.
function New-MelodyBar([System.Random]$Rng, [string]$Template, [int[]]$Scale, [int[]]$ChordTones, [int]$Low, [int]$High) {
    $mx = $script:Mx
    $digits = '0123456789abcdefghijklmnopqrstuvwxyz'
    $first = $true
    $out = foreach ($c in $Template.ToCharArray()) {
        if ($c -ne 'x') { $c; continue }
        $idx = [Math]::Max($Low, [Math]::Min($High, $mx.Walk + $Rng.Next(5) - 2))
        if ($first) {
            foreach ($d in 0, 1, -1, 2, -2) {
                $semi = ((Get-ScaleSemi $Scale ($idx + $d)) % 12 + 12) % 12
                if ($ChordTones -contains $semi -and $idx + $d -ge $Low) { $idx += $d; break }
            }
            $first = $false
        }
        $mx.Walk = $idx
        $digits[$idx]
    }
    -join $out
}

# '8M' -> @{ Semi = 8; Tones = 0,4,7 }   (m = minor triad, M = major triad)
function Get-Chord([string]$Text) {
    $semi = [int]$Text.Substring(0, $Text.Length - 1)
    @{ Semi = $semi; Tones = if ($Text.EndsWith('M')) { 0, 4, 7 } else { 0, 3, 7 } }
}

# The pitch classes (0..11) of a chord, for New-MelodyBar.
function Get-ChordClasses([hashtable]$Chord) { $Chord.Tones | ForEach-Object { (($Chord.Semi + $_) % 12 + 12) % 12 } }

function Add-Drum([int16[]]$Chan, [int]$Bar, [double]$Step, [int16[]]$Sample) {
    Copy-Pattern $Chan ([int](($Bar * 16 + $Step) * $script:Mx.StepLen)) $Sample.Length $Sample
}

# Pre-rendered one-shots. $Kind: tone (sine sweep $From -> $To Hz) or noise ($Bright: hissy instead of dull).
function New-DrumSample([System.Random]$Rng, [string]$Kind, [double]$Seconds, [int]$Amp, [double]$From = 0, [double]$To = 0, [bool]$Bright = $false) {
    $len = [int]($script:MUSIC_RATE * $Seconds)
    $s = [int16[]]::new($len); $ph = 0.0; $last = 0.0
    for ($i = 0; $i -lt $len; $i++) {
        $env = 1.0 - $i / $len
        if ($Kind -eq 'tone') {
            $ph += ($From + ($To - $From) * $i / $len) / $script:MUSIC_RATE
            $v = [Math]::Sin(2 * [Math]::PI * $ph)
        }
        else {
            $n = $Rng.NextDouble() * 2 - 1
            $v = if ($Bright) { ($n - $last) * 0.7 } else { ($n + $last) * 0.5 }
            $last = $n
        }
        $s[$i] = [int16]($Amp * 127 * $v * $env * $env)
    }
    , $s
}

function New-DrumKit([System.Random]$Rng) {
    @{
        Kick      = New-DrumSample $Rng 'tone' 0.11 60 150 40
        Timpani   = New-DrumSample $Rng 'tone' 0.30 58 82 70
        Heart     = New-DrumSample $Rng 'tone' 0.14 46 60 42
        Snare     = New-DrumSample $Rng 'noise' 0.10 38
        SnareSoft = New-DrumSample $Rng 'noise' 0.06 17
        Hat       = New-DrumSample $Rng 'noise' 0.025 16 0 0 $true
        OpenHat   = New-DrumSample $Rng 'noise' 0.09 20 0 0 $true
        Crash     = New-DrumSample $Rng 'noise' 0.60 30 0 0 $true
    }
}

# ---------------------------------------------------------------------------------------------
# The compositions. Each gets the channels in $script:Mx.Ch (Bass, Lead, Harm, Extra, DrumA, DrumB).
# ---------------------------------------------------------------------------------------------
# Title screen: a solemn fanfare over timpani; the second time round with a harmony voice and arpeggios.
function Add-AnthemMusic([hashtable]$Def, [hashtable]$Kit, [System.Random]$Rng) {
    $ch = $script:Mx.Ch
    $theme = '0-..0.0-4---4---', '7---6-4-5---4---', '5-..5.5-7---5---', '6-..6.6-8---a---',
             'b---9-7-9---7---', 'a---9-7-a---c---', 'b---b-b-8---b---', 'e-----------....'
    for ($bar = 0; $bar -lt $Def.Bars; $bar++) {
        $chord = Get-Chord $Def.Chords[$bar % 8]; $at = $bar * 16; $second = $bar -ge 8
        if ($bar % 8 -eq 7) { Add-Note $ch.Bass $at 15 $chord.Semi 58 'triangle' 0.6 }
        else {
            Add-Note $ch.Bass $at 6 $chord.Semi 58 'triangle' 0.7
            Add-Note $ch.Bass ($at + 8) 3.6 $chord.Semi 58 'triangle' 0.7
            Add-Note $ch.Bass ($at + 12) 3.6 ($chord.Semi - 5) 58 'triangle' 0.7
        }
        Add-Melody $ch.Lead $bar $theme[$bar % 8] -Scale $Def.Scale -BaseSemi 12 -Amp 34 -Wave $(if ($second) { 'square' } else { 'pulse' }) -Decay 0.55
        if ($second) {
            Add-Melody $ch.Harm $bar $theme[$bar % 8] -Scale $Def.Scale -BaseSemi 12 -Amp 18 -Wave 'pulse' -Decay 0.55 -Shift 2       # a third above
            for ($s = 0; $s -lt 16; $s++) { Add-Note $ch.Extra ($at + $s) 0.8 ($chord.Semi + 24 + $chord.Tones[(0, 1, 2, 1)[$s % 4]]) 14 'thin' 0.4 }
        }
        if ($bar -ge 2) {
            Add-Drum $ch.DrumA $bar 0 $Kit.Timpani; Add-Drum $ch.DrumA $bar 8 $Kit.Timpani
            if ($bar % 8 -eq 7) { foreach ($s in 8..15) { Add-Drum $ch.DrumB $bar $s $(if ($s -ge 12) { $Kit.Snare } else { $Kit.SnareSoft }) } }
            else { foreach ($s in 4, 12) { Add-Drum $ch.DrumB $bar $s $Kit.Snare }; foreach ($s in 14, 15) { Add-Drum $ch.DrumB $bar $s $Kit.SnareSoft } }
        }
    }
}

# Floor 1: rock. A power-chord riff through a twelve-bar-blues-like progression, a driving beat and a blues-scale solo.
function Add-RockMusic([hashtable]$Def, [hashtable]$Kit, [System.Random]$Rng) {
    $ch = $script:Mx.Ch; $chromatic = 0..11
    $riffs = '0-0.3-0.5-0.3-5-', '0-0.3-0.5-6-5-3-'
    $rhythms = 'x.x.x-..x.x.x---', 'x-x.xxx.x---..x.', '..x.x.x-x.xxx-x-', 'xxx.x-x.x-----..'
    $solo = @{}
    for ($bar = 0; $bar -lt $Def.Bars; $bar++) {
        $chord = Get-Chord $Def.Chords[$bar % $Def.Chords.Count]; $at = $bar * 16
        Add-Melody $ch.Harm $bar $riffs[[int]($bar % 4 -eq 3)] -Scale $chromatic -BaseSemi $chord.Semi -Amp 42 -Wave 'power' -Decay 0.5
        for ($s = 0; $s -lt 16; $s += 2) { Add-Note $ch.Bass ($at + $s) 1.7 $chord.Semi 46 'triangle' 0.6 }
        if ($bar -ge 4) {
            # the solo: a four-bar phrase, played twice, then a new one
            $slot = [int][Math]::Floor(($bar - 4) / 8) * 4 + ($bar - 4) % 4
            if (-not $solo.ContainsKey($slot)) { $solo[$slot] = New-MelodyBar $Rng $rhythms[$Rng.Next($rhythms.Count)] $Def.Scale (0, 3, 7) 4 15 }
            Add-Melody $ch.Lead $bar $solo[$slot] -Scale $Def.Scale -BaseSemi 12 -Amp 30 -Wave 'square' -Decay 0.45
        }
        if ($bar % 8 -eq 0) { Add-Drum $ch.DrumB $bar 0 $Kit.Crash }
        foreach ($s in 0, 8, 10) { Add-Drum $ch.DrumA $bar $s $Kit.Kick }
        if ($bar % 8 -eq 7) { foreach ($s in 4, 8, 10, 12, 13, 14, 15) { Add-Drum $ch.DrumB $bar $s $Kit.Snare } }
        else {
            foreach ($s in 2, 6, 10, 14) { Add-Drum $ch.DrumB $bar $s $Kit.Hat }
            foreach ($s in 4, 12) { Add-Drum $ch.DrumB $bar $s $Kit.Snare }
        }
    }
}

# Floor 2: the barracks march. Oom-pah bass, a rattling snare drum and a brassy tune in dotted rhythm.
function Add-MarchMusic([hashtable]$Def, [hashtable]$Kit, [System.Random]$Rng) {
    $ch = $script:Mx.Ch
    $rhythms = 'x--xx---x--xx---', 'x-x-x--xx---x---', 'x--xx-x-x---x-x-', 'x---x--xx-x-x---'
    $tune = @{}
    for ($bar = 0; $bar -lt $Def.Bars; $bar++) {
        $chord = Get-Chord $Def.Chords[$bar % 8]; $at = $bar * 16
        foreach ($s in 0, 8) { Add-Note $ch.Bass ($at + $s) 3 $chord.Semi 58 'triangle' 0.6 }
        foreach ($s in 4, 12) { Add-Note $ch.Bass ($at + $s) 3 ($chord.Semi - 5) 58 'triangle' 0.6 }
        foreach ($s in 2, 10) { Add-Note $ch.Harm ($at + $s) 1.2 ($chord.Semi + 12 + $chord.Tones[1]) 20 'pulse' 0.5 }
        foreach ($s in 6, 14) { Add-Note $ch.Harm ($at + $s) 1.2 ($chord.Semi + 12 + $chord.Tones[2]) 20 'pulse' 0.5 }
        if ($bar -ge 2) {
            $slot = $bar % 8
            if (-not $tune.ContainsKey($slot)) {
                $tune[$slot] = if ($slot -eq 7) { '7-----7-7-------' } else { New-MelodyBar $Rng $rhythms[$Rng.Next($rhythms.Count)] $Def.Scale (Get-ChordClasses $chord) 3 12 }
            }
            Add-Melody $ch.Lead $bar $tune[$slot] -Scale $Def.Scale -BaseSemi 12 -Amp 34 -Wave 'pulse' -Decay 0.65
            if ($bar -ge 10) { Add-Melody $ch.Extra $bar $tune[$slot] -Scale $Def.Scale -BaseSemi 24 -Amp 14 -Wave 'thin' -Decay 0.5 }      # piccolo on top
        }
        foreach ($s in 0, 8) { Add-Drum $ch.DrumA $bar $s $Kit.Kick }
        foreach ($s in 4, 7, 12, 15) { Add-Drum $ch.DrumB $bar $s $Kit.Snare }
        foreach ($s in 3, 6, 11, 14) { Add-Drum $ch.DrumB $bar $s $Kit.SnareSoft }
    }
}

# Floor 3: the catacombs. Hardly any rhythm at all: two drones beating against each other, far-away bells
# with an echo, a heartbeat, and now and then the wind.
function Add-CryptMusic([hashtable]$Def, [hashtable]$Kit, [System.Random]$Rng) {
    $ch = $script:Mx.Ch
    $bells = '0.....4...5.....', '..3.......1.....', '0.....4...6.....', '..7---....5-....',
             '9.....7...5.....', '..4.......3.....', 'a---....8-..7-..', '6-------........'
    # the wind: dull noise that swells and dies away
    $wind = [int16[]]::new([int]($script:MUSIC_RATE * 2.0)); $low = 0.0
    for ($i = 0; $i -lt $wind.Length; $i++) {
        $low += (($Rng.NextDouble() * 2 - 1) - $low) * 0.08
        $wind[$i] = [int16](127 * 60 * $low * [Math]::Sin([Math]::PI * $i / $wind.Length))
    }
    for ($bar = 0; $bar -lt $Def.Bars; $bar++) {
        $chord = Get-Chord $Def.Chords[$bar % 8]; $at = $bar * 16
        Add-Note $ch.Bass $at 16 $chord.Semi 50 'triangle'
        Add-Note $ch.Harm $at 16 ($chord.Semi + 12) 20 'triangle' 1.0 1.012          # slightly out of tune: a slow, uneasy beating
        Add-Melody $ch.Lead $bar $bells[$bar % 8] -Scale $Def.Scale -BaseSemi 36 -Amp 38 -Wave 'triangle' -Decay 0.12
        Add-Melody $ch.Extra $bar $bells[$bar % 8] -Scale $Def.Scale -BaseSemi 36 -Amp 15 -Wave 'triangle' -Decay 0.12 -Detune 1.005 -Delay 3
        Add-Drum $ch.DrumA $bar 0 $Kit.Heart; Add-Drum $ch.DrumA $bar 3 $Kit.Heart
        if ($bar % 4 -eq 3) { Add-Drum $ch.DrumB $bar 5 $wind }
    }
}

# Floor 4: the lab. Four on the floor, an acid bass line, arpeggios - and a lead that only arrives half way through.
function Add-TechnoMusic([hashtable]$Def, [hashtable]$Kit, [System.Random]$Rng) {
    $ch = $script:Mx.Ch; $chromatic = 0..11
    $lead = '4-------7-------', '6-----4---------', '4-------7-------', '8-----7-6-4-----',
            '5-------7-------', '9-----7---------', '6-------8-------', 'a---8---6---4---'
    for ($bar = 0; $bar -lt $Def.Bars; $bar++) {
        $chord = Get-Chord $Def.Chords[$bar % 8]; $at = $bar * 16; $second = $bar -ge 8
        Add-Melody $ch.Bass $bar '00c0.c0a00c.3c0a' -Scale $chromatic -BaseSemi ($chord.Semi + 12) -Amp 46 -Wave 'saw' -Decay 0.3
        if ($bar -ge 2) {
            $tones = $chord.Tones + 12
            $order = if ($second) { 0, 2, 1, 3 } else { 0, 1, 2, 3, 2, 1 }
            for ($s = 0; $s -lt 16; $s++) { Add-Note $ch.Harm ($at + $s) 0.8 ($chord.Semi + 36 + $tones[$order[$s % $order.Count]]) 20 'thin' 0.35 }
        }
        if ($second) { Add-Melody $ch.Lead $bar $lead[$bar % 8] -Scale $Def.Scale -BaseSemi 36 -Amp 28 -Wave 'square' -Decay 0.7 }
        foreach ($s in 0, 4, 8, 12) { Add-Drum $ch.DrumA $bar $s $Kit.Kick }
        if ($bar -ge 1) { foreach ($s in 2, 6, 10, 14) { Add-Drum $ch.DrumB $bar $s $Kit.OpenHat } }
        if ($bar -ge 4) { foreach ($s in 4, 12) { Add-Drum $ch.DrumB $bar $s $Kit.Snare } }
        if ($second) { foreach ($s in 1, 5, 9, 13) { Add-Drum $ch.DrumB $bar $s $Kit.Hat } }
        if ($bar % 8 -eq 7) { foreach ($s in 8..15) { Add-Drum $ch.DrumB $bar $s $(if ($s -ge 12) { $Kit.Snare } else { $Kit.SnareSoft }) } }      # the build-up
    }
}

# Floor 5: the citadel. Harmonic minor at a gallop; first the theme, then arpeggio runs over it.
function Add-FinaleMusic([hashtable]$Def, [hashtable]$Kit, [System.Random]$Rng) {
    $ch = $script:Mx.Ch
    $theme = '7-----4-7---9---', '8---7---6---4---', '5-----7-9---c---', 'b---9---8---6---',
             '7-----9-b---e---', 'c---a---9---7---', '8---8-8-b---8---', '6---8---b---d---'
    for ($bar = 0; $bar -lt $Def.Bars; $bar++) {
        $chord = Get-Chord $Def.Chords[$bar % 8]; $at = $bar * 16; $second = $bar -ge 8
        foreach ($s in 0, 4, 8, 12) {
            Add-Note $ch.Harm ($at + $s) 1.8 $chord.Semi 40 'power' 0.6
            Add-Note $ch.Harm ($at + $s + 2) 0.9 $chord.Semi 40 'power' 0.6
            Add-Note $ch.Harm ($at + $s + 3) 0.9 $chord.Semi 40 'power' 0.6
        }
        foreach ($s in 0, 8) { Add-Note $ch.Bass ($at + $s) 7 $chord.Semi 46 'triangle' 0.6 }
        if ($second) {
            Add-Melody $ch.Extra $bar $theme[$bar % 8] -Scale $Def.Scale -BaseSemi 12 -Amp 24 -Wave 'pulse' -Decay 0.6
            $tones = $chord.Tones + ($chord.Tones | ForEach-Object { $_ + 12 })
            for ($s = 0; $s -lt 16; $s++) { Add-Note $ch.Lead ($at + $s) 0.85 ($chord.Semi + 24 + $tones[(0, 1, 2, 3, 4, 3, 2, 1)[$s % 8]]) 28 'square' 0.4 }
        }
        else { Add-Melody $ch.Lead $bar $theme[$bar % 8] -Scale $Def.Scale -BaseSemi 24 -Amp 30 -Wave 'square' -Decay 0.6 }
        if ($bar % 8 -eq 0) { Add-Drum $ch.DrumB $bar 0 $Kit.Crash }
        foreach ($s in 0, 2, 3, 8, 10, 11) { Add-Drum $ch.DrumA $bar $s $Kit.Kick }
        if ($bar % 8 -eq 7) { foreach ($s in 4, 6, 8, 10, 12, 13, 14, 15) { Add-Drum $ch.DrumB $bar $s $Kit.Snare } }
        else { foreach ($s in 4, 12) { Add-Drum $ch.DrumB $bar $s $Kit.Snare }; foreach ($s in 6, 14) { Add-Drum $ch.DrumB $bar $s $Kit.Hat } }
    }
}

# The secret floor: a carefree major-pentatonic ditty with a bouncing bass and the clink of coins.
function Add-TreasureMusic([hashtable]$Def, [hashtable]$Kit, [System.Random]$Rng) {
    $ch = $script:Mx.Ch
    $rhythms = 'x.x.x-x.x.x.x---', 'x-x.x.x-x---..x.', 'xx..x.x.x-x-x---', 'x.xxx.x.x-..x-..'
    $tune = @{}
    for ($bar = 0; $bar -lt $Def.Bars; $bar++) {
        $chord = Get-Chord $Def.Chords[$bar % 8]; $at = $bar * 16
        for ($s = 0; $s -lt 16; $s += 2) { Add-Note $ch.Bass ($at + $s) 1.5 ($chord.Semi + $(if ($s % 4) { 24 } else { 12 })) 50 'triangle' 0.5 }
        foreach ($s in 4, 12) { Add-Note $ch.Harm ($at + $s) 1.5 ($chord.Semi + 24 + $chord.Tones[1]) 16 'pulse' 0.4 }
        $slot = $bar % 8
        if (-not $tune.ContainsKey($slot)) {
            $tune[$slot] = if ($slot -eq 7) { '5-5-7---a-------' } else { New-MelodyBar $Rng $rhythms[$Rng.Next($rhythms.Count)] $Def.Scale (Get-ChordClasses $chord) 3 11 }
        }
        Add-Melody $ch.Lead $bar $tune[$slot] -Scale $Def.Scale -BaseSemi 24 -Amp 30 -Wave $(if ($bar -ge 8) { 'pulse' } else { 'square' }) -Decay 0.5
        if ($bar % 2 -eq 1) { Add-Note $ch.Extra ($at + 14) 0.9 59 16 'thin' 0.5; Add-Note $ch.Extra ($at + 15) 1.0 64 16 'thin' 0.3 }      # "bling"
        foreach ($s in 0, 8) { Add-Drum $ch.DrumA $bar $s $Kit.Kick }
        foreach ($s in 4, 12) { Add-Drum $ch.DrumB $bar $s $Kit.SnareSoft }
        foreach ($s in 2, 6, 10, 14) { Add-Drum $ch.DrumB $bar $s $Kit.Hat }
    }
}

# The epilogue: C major at walking pace. A theme that sings (eight bars), a second one that climbs (eight more),
# then both again with a second voice a third above, a fuller beat and the timpani. It begins almost alone -
# an arpeggio and a bass - the way the morning does.
function Add-EndingMusic([hashtable]$Def, [hashtable]$Kit, [System.Random]$Rng) {
    $ch = $script:Mx.Ch
    $theme = '4---..4-7---6-4-', '6-----4---..1-2-', '2---..2-5---4-2-', '3-----..0-1-2-3-',
             '4---..4-7---8-9-', '8-----6---..4-6-', '7---5---3---5---', '7-----------....',
             '5-..5-7-a---9-7-', '8-..8-9-b---9-8-', '9-----8-6---4---', '5-----..5-7-9-c-',
             'c---a---9---7---', 'b---9---8---6---', '7-8-9-b-c---b---', 'e-----------....'
    for ($bar = 0; $bar -lt $Def.Bars; $bar++) {
        $chord = Get-Chord $Def.Chords[$bar % 16]; $at = $bar * 16; $again = $bar -ge 16; $last = $bar -eq $Def.Bars - 1
        # bass: root, fifth, root an octave up
        if ($last) { Add-Note $ch.Bass $at 15 $chord.Semi 54 'triangle' 0.6 }
        else {
            Add-Note $ch.Bass $at 7 $chord.Semi 54 'triangle' 0.7
            Add-Note $ch.Bass ($at + 8) 3.6 ($chord.Semi + 7) 50 'triangle' 0.7
            Add-Note $ch.Bass ($at + 12) 3.6 ($chord.Semi + 12) 50 'triangle' 0.7
        }
        # the arpeggio that carries it all
        for ($s = 0; $s -lt 16; $s += 2) {
            $tone = $chord.Tones[(0, 1, 2, 1, 0, 2, 1, 2)[$s / 2]] + $(if ($s -in 4, 10) { 12 } else { 0 })
            Add-Note $ch.Extra ($at + $s) 1.8 ($chord.Semi + 24 + $tone) $(if ($again) { 13 } else { 15 }) 'thin' 0.45
        }
        if ($bar -ge 2) {
            Add-Melody $ch.Lead $bar $theme[$bar % 16] -Scale $Def.Scale -BaseSemi 12 -Amp 34 -Wave $(if ($again) { 'square' } else { 'pulse' }) -Decay 0.6
            if ($again) { Add-Melody $ch.Harm $bar $theme[$bar % 16] -Scale $Def.Scale -BaseSemi 12 -Amp 17 -Wave 'pulse' -Decay 0.6 -Shift 2 }
            else { Add-Melody $ch.Harm $bar $theme[$bar % 16] -Scale $Def.Scale -BaseSemi 12 -Amp 9 -Wave 'thin' -Decay 0.5 -Delay 3 }       # an echo
        }
        if ($bar -ge 8) {
            foreach ($s in 0, 8) { Add-Drum $ch.DrumA $bar $s $(if ($again) { $Kit.Kick } else { $Kit.Heart }) }
            foreach ($s in 4, 12) { Add-Drum $ch.DrumB $bar $s $(if ($again) { $Kit.Snare } else { $Kit.SnareSoft }) }
            if ($again) { foreach ($s in 2, 6, 10, 14) { Add-Drum $ch.DrumB $bar $s $Kit.Hat } }
        }
        if ($bar % 16 -eq 15) { foreach ($s in 8, 10, 12, 13, 14, 15) { Add-Drum $ch.DrumA $bar $s $Kit.Timpani } }                 # the roll into the next part
        if ($bar -eq 16) { Add-Drum $ch.DrumB $bar 0 $Kit.Crash }
    }
}

# ---------------------------------------------------------------------------------------------
# Rendering a track to a 16 bit mono WAV file
# ---------------------------------------------------------------------------------------------
function New-MusicTrack([int]$Track, [string]$Path) {
    $style = Get-MusicStyle $Track
    $def = $script:MusicStyles[$style]
    $rng = [System.Random]::new(4200 + $Track)
    $round = [int][Math]::Floor([Math]::Max(0, $Track - 1) / 5)                 # floors 6+ reuse the styles, two semitones up each round
    if ($Track -in $script:MUSIC_BONUS, $script:MUSIC_ENDING) { $round = 0 }
    $stepLen = [int]($script:MUSIC_RATE * 60.0 / $def.Tempo / 4)               # one sixteenth note
    $total = [int][Math]::Ceiling($stepLen * 16 * $def.Bars / 64.0) * 64       # a multiple of every vector width
    $script:Mx = @{
        StepLen = $stepLen; Root = $def.Root * [Math]::Pow(2, $round * 2 / 12.0); Walk = 7
        Units = @{}; Patterns = @{}
        Ch = @{}
    }
    foreach ($name in 'Bass', 'Lead', 'Harm', 'Extra', 'DrumA', 'DrumB') { $script:Mx.Ch[$name] = [int16[]]::new($total) }
    $kit = New-DrumKit $rng
    switch ($style) {
        'anthem'   { Add-AnthemMusic $def $kit $rng }
        'rock'     { Add-RockMusic $def $kit $rng }
        'march'    { Add-MarchMusic $def $kit $rng }
        'crypt'    { Add-CryptMusic $def $kit $rng }
        'techno'   { Add-TechnoMusic $def $kit $rng }
        'finale'   { Add-FinaleMusic $def $kit $rng }
        'treasure' { Add-TreasureMusic $def $kit $rng }
        'ending'   { Add-EndingMusic $def $kit $rng }
    }

    # mix: the channel amplitudes are chosen so that the sum cannot overflow 16 bits
    $vt = [System.Numerics.Vector[int16]]; $n = $vt::Count
    $mix = $script:Mx.Ch.Bass
    foreach ($name in 'Lead', 'Harm', 'Extra', 'DrumA', 'DrumB') {
        $other = $script:Mx.Ch[$name]
        for ($i = 0; $i -lt $total; $i += $n) { $vt::op_Addition($vt::new($mix, $i), $vt::new($other, $i)).CopyTo($mix, $i) }
    }
    $script:Mx = $null
    $data = [byte[]]::new($total * 2)
    [Buffer]::BlockCopy($mix, 0, $data, 0, $data.Length)

    $null = New-Item -ItemType Directory -Path (Split-Path $Path) -Force
    $fs = [System.IO.File]::Create($Path)
    $bw = [System.IO.BinaryWriter]::new($fs)
    $bw.Write([byte[]][char[]]'RIFF'); $bw.Write([int](36 + $data.Length)); $bw.Write([byte[]][char[]]'WAVEfmt ')
    $bw.Write([int]16); $bw.Write([int16]1); $bw.Write([int16]1); $bw.Write([int]$script:MUSIC_RATE); $bw.Write([int]($script:MUSIC_RATE * 2))
    $bw.Write([int16]2); $bw.Write([int16]16)
    $bw.Write([byte[]][char[]]'data'); $bw.Write([int]$data.Length); $bw.Write($data)
    $bw.Dispose(); $fs.Dispose()
}

function Get-MusicPath([int]$Track) { Join-Path $script:MusicDir ("track{0}-v{1}.wav" -f $Track, $script:MUSIC_VERSION) }

# Composes a track ahead of time, so that it starts without a pause when it is wanted.
function Initialize-MusicTrack([int]$Track) {
    if (-not $script:MusicEnabled -or -not $script:Mixer) { return }
    try { $path = Get-MusicPath $Track; if (-not (Test-Path -LiteralPath $path)) { New-MusicTrack $Track $path } } catch { }
}

function Start-Music([int]$Track) {
    if (-not $script:MusicEnabled -or -not $script:Mixer) { return }
    if ($Track -eq $script:MusicTrack) { return }
    try {
        $path = Get-MusicPath $Track
        if (-not (Test-Path -LiteralPath $path)) {
            # tracks of an older version of the composer are of no use any more
            Get-ChildItem -LiteralPath $script:MusicDir -Filter 'track*.wav' -ErrorAction SilentlyContinue |
                Where-Object Name -NotLike "*-v$($script:MUSIC_VERSION).wav" | Remove-Item -Force -ErrorAction SilentlyContinue
            New-MusicTrack $Track $path
        }
        if (-not $script:MusicIds.ContainsKey($Track)) { $script:MusicIds[$Track] = $script:Mixer::LoadWav([System.IO.File]::ReadAllBytes($path)) }
        $script:Mixer::SetMusic($script:MusicIds[$Track])                # the mixer loops it, sample-exact
        $script:MusicTrack = $Track
    }
    catch {
        Write-Warning "Music disabled: $($_.Exception.Message)"
        $script:MusicEnabled = $false
    }
}

function Stop-Music {
    if ($script:Mixer) { $script:Mixer::SetMusic(-1) }
    $script:MusicTrack = -1
}

function Switch-Music {
    $script:MusicEnabled = -not $script:MusicEnabled
    if ($script:MusicEnabled) { Start-Music $script:MusicWanted } else { Stop-Music }
    Show-Message "Music $(if ($script:MusicEnabled) { 'ON' } else { 'OFF' })"
}
