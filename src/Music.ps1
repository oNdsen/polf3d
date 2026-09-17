# POLF 3D - Copyright (c) 2026 oNdsen. Licensed under the MIT License, see LICENSE.

# Music.ps1 - procedural chiptune. Every floor gets its own loop, composed from a seed (tempo,
# key, bass line, lead melody, drums), rendered to a WAV file once and cached in bin/music.
#
# Rendering trick: a note is one wave period copied over and over with Buffer.BlockCopy, so
# PowerShell never has to touch individual samples except for the final three-channel mix.
# Playback uses WPF's MediaPlayer, which mixes happily with the SoundPlayer used for effects.

$script:MUSIC_RATE = 22050
$script:MUSIC_VERSION = 2                       # bump to invalidate cached tracks
$script:MusicEnabled = $true
$script:MusicPlayer = $null
$script:MusicSeconds = 0.0
$script:MusicTrack = -1

# Fills $Buf[$Start .. $Start+$Length) by repeating $Pattern (both int16[]).
function Copy-Pattern([int16[]]$Buf, [int]$Start, [int]$Length, [int16[]]$Pattern) {
    if ($Start -ge $Buf.Length) { return }
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

function New-WavePeriod([double]$Freq, [int]$Amp, [string]$Wave) {
    $len = [Math]::Max(2, [int][Math]::Round($script:MUSIC_RATE / $Freq))
    $p = [int16[]]::new($len)
    for ($i = 0; $i -lt $len; $i++) {
        $t = $i / $len
        $p[$i] = switch ($Wave) {
            'square'   { if ($t -lt 0.5) { $Amp } else { - $Amp } }
            'pulse'    { if ($t -lt 0.25) { $Amp } else { - $Amp } }
            'triangle' { [int]($Amp * (4 * [Math]::Abs($t - 0.5) - 1)) }
        }
    }
    , $p
}

function New-MusicTrack([int]$Track, [string]$Path) {
    $rng = [System.Random]::new(4200 + $Track)
    $tempo = (126, 132, 118, 100, 140, 150)[$Track % 6]
    $rootHz = (87.31, 110.0, 82.41, 73.42, 98.0, 65.41)[$Track % 6]            # F2 A2 E2 D2 G2 C2
    $stepLen = [int]($script:MUSIC_RATE * 60.0 / $tempo / 4)                   # one sixteenth note
    $steps = 128                                                                # eight bars
    $total = $stepLen * $steps
    $bass = [int16[]]::new($total); $lead = [int16[]]::new($total); $drum = [int16[]]::new($total)

    $penta = 0, 3, 5, 7, 10                                                     # minor pentatonic
    $chords = 0, 0, 8, 10, 0, 0, 5, 7                                           # i i VI VII i i iv v
    $hz = { param($semi) $rootHz * [Math]::Pow(2, $semi / 12.0) }

    # drums: pre-rendered one-shots
    $kick = [int16[]]::new([int]($script:MUSIC_RATE * 0.09)); $ph = 0.0
    for ($i = 0; $i -lt $kick.Length; $i++) { $ph += (160.0 - 120.0 * $i / $kick.Length) / $script:MUSIC_RATE; $kick[$i] = [int16]($(if (($ph % 1) -lt 0.5) { 46 } else { -46 }) * (1 - $i / $kick.Length)) }
    $snare = [int16[]]::new([int]($script:MUSIC_RATE * 0.07))
    for ($i = 0; $i -lt $snare.Length; $i++) { $snare[$i] = [int16](($rng.Next(81) - 40) * (1 - $i / $snare.Length)) }
    $hat = [int16[]]::new([int]($script:MUSIC_RATE * 0.02))
    for ($i = 0; $i -lt $hat.Length; $i++) { $hat[$i] = [int16](($rng.Next(41) - 20) * (1 - $i / $hat.Length)) }

    # a two-bar lead motif (step -> scale index, -1 = rest), varied on its repeats
    $motif = [int[]]::new(32); $idx = 5
    for ($s = 0; $s -lt 32; $s++) {
        if ($s % 2 -eq 1 -and $rng.Next(100) -lt 70) { $motif[$s] = -1; continue }
        if ($rng.Next(100) -lt 22) { $motif[$s] = -1; continue }
        $idx = [Math]::Max(3, [Math]::Min(11, $idx + $rng.Next(5) - 2))
        $motif[$s] = $idx
    }

    for ($s = 0; $s -lt $steps; $s++) {
        $bar = [int][Math]::Floor($s / 16); $inBar = $s % 16
        $chord = $chords[$bar % 8]
        $at = $s * $stepLen

        # bass: syncopated root / fifth / octave
        if ($inBar -in 0, 3, 6, 8, 11, 14) {
            $semi = $chord + $(switch ($inBar) { 6 { 7 } 14 { 12 } default { 0 } })
            Copy-Pattern $bass $at ([int]($stepLen * 1.8)) (New-WavePeriod (& $hz $semi) 38 'triangle')
        }
        # lead: the motif, transposed with the chord, with a changed tail every fourth bar
        $m = $motif[$s % 32]
        if ($bar % 4 -eq 3 -and $inBar -ge 8 -and $rng.Next(100) -lt 60) { $m = 4 + $rng.Next(7) }
        if ($m -ge 0 -and $bar -ge 1) {
            $semi = 24 + $chord + 12 * [int][Math]::Floor($m / 5) + $penta[$m % 5] - 12
            $wave = if ($bar % 8 -ge 4) { 'pulse' } else { 'square' }
            Copy-Pattern $lead $at ([int]($stepLen * 0.9)) (New-WavePeriod (& $hz $semi) 26 $wave)
        }
        # drums
        if ($inBar -in 0, 8 -or ($inBar -eq 10 -and $bar % 2 -eq 1)) { Copy-Pattern $drum $at $kick.Length $kick }
        elseif ($inBar -in 4, 12) { Copy-Pattern $drum $at $snare.Length $snare }
        elseif ($inBar % 2 -eq 0) { Copy-Pattern $drum $at $hat.Length $hat }
    }

    # the one loop that touches every sample: mix down to 8 bit
    $data = [byte[]]::new($total)
    for ($i = 0; $i -lt $total; $i++) { $data[$i] = 128 + $bass[$i] + $lead[$i] + $drum[$i] }

    $null = New-Item -ItemType Directory -Path (Split-Path $Path) -Force
    $fs = [System.IO.File]::Create($Path)
    $bw = [System.IO.BinaryWriter]::new($fs)
    $bw.Write([byte[]][char[]]'RIFF'); $bw.Write([int](36 + $total)); $bw.Write([byte[]][char[]]'WAVEfmt ')
    $bw.Write([int]16); $bw.Write([int16]1); $bw.Write([int16]1); $bw.Write([int]$script:MUSIC_RATE); $bw.Write([int]$script:MUSIC_RATE)
    $bw.Write([int16]1); $bw.Write([int16]8)
    $bw.Write([byte[]][char[]]'data'); $bw.Write([int]$total); $bw.Write($data)
    $bw.Dispose(); $fs.Dispose()
}

# Track 0 = title screen, track N = floor N.
function Start-Music([int]$Track) {
    if (-not $script:MusicEnabled) { return }
    if ($Track -eq $script:MusicTrack -and $script:MusicPlayer) { return }
    try {
        $path = Join-Path $script:MusicDir ("track{0}-v{1}.wav" -f $Track, $script:MUSIC_VERSION)
        if (-not (Test-Path -LiteralPath $path)) { New-MusicTrack $Track $path }
        Stop-Music
        $script:MusicSeconds = ((Get-Item -LiteralPath $path).Length - 44) / $script:MUSIC_RATE
        $script:MusicPlayer = [System.Windows.Media.MediaPlayer]::new()
        $script:MusicPlayer.Open([Uri]::new($path))
        $script:MusicPlayer.Volume = 0.35
        $script:MusicPlayer.Play()
        $script:MusicTrack = $Track
        $script:MusicStarted = $script:Clock.Elapsed.TotalSeconds
    }
    catch {
        Write-Warning "Music disabled: $($_.Exception.Message)"
        $script:MusicEnabled = $false
    }
}

function Stop-Music {
    if ($script:MusicPlayer) { $script:MusicPlayer.Stop(); $script:MusicPlayer.Close(); $script:MusicPlayer = $null }
    $script:MusicTrack = -1
}

# Called every frame: restarts the loop when it has played through.
function Update-Music {
    if (-not $script:MusicPlayer) { return }
    if ($script:Clock.Elapsed.TotalSeconds - $script:MusicStarted -ge $script:MusicSeconds - 0.03) {
        $script:MusicPlayer.Position = [TimeSpan]::Zero
        $script:MusicPlayer.Play()
        $script:MusicStarted = $script:Clock.Elapsed.TotalSeconds
    }
}

function Switch-Music {
    $script:MusicEnabled = -not $script:MusicEnabled
    if ($script:MusicEnabled) { Start-Music $script:MusicWanted } else { Stop-Music }
    Show-Message "Music $(if ($script:MusicEnabled) { 'ON' } else { 'OFF' })"
}
