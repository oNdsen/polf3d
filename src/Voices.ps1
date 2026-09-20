# POLF 3D - Copyright (c) 2026 oNdsen. Licensed under the MIT License, see LICENSE.

# Voices.ps1 - the garrison talks (and thanks to the mixer, several of them at once). Windows' own speech synthesiser (SAPI, through COM - no assembly
# needed) says each line once into a WAV file in bin/voice, deliberately lo-fi at 11 kHz and 8 bits
# so that it sits well next to the synthesised effects; after that the lines are ordinary sounds.
# No speech engine, no English voice, -NoVoices: then everybody just beeps as before.

$script:VOICE_VERSION = 3
$script:Voices = @{}                 # kind -> names of alert lines;  "kind.die" -> names of last words

# kind, line, pitch (-10..10), rate (-10..10), voice wanted ('m' or 'f'), priority
# (the comma in front of a line with a single entry keeps PowerShell from unrolling it into six strings)
$script:VoiceLines = @(
    @('guard',   'Access denied!',                        -2,  2, 'm', 6), @('guard',   'Intruder alert!',                    0,  2, 'm', 6)
    , @('guard',   'Halt! Identify yourself!',              -3,  3, 'm', 6)
    @('officer', 'Unauthorised access!',                   3,  3, 'm', 6), @('officer', 'Who approved this change?',          4,  3, 'm', 6)
    @('elite',   'Execution policy: restricted!',         -6,  1, 'm', 6), @('elite',   'You do not have permission!',       -6,  2, 'm', 6)
    @('shield',  'Permission denied!',                    -8,  0, 'm', 6), @('shield',  'Firewall up!',                      -8,  1, 'm', 6)
    @('engineer', 'Have you tried turning it off and on again?', 1, 2, 'm', 6), @('engineer', 'That is not covered by the warranty!', 2, 3, 'm', 6)
    @('auditor', 'This will be in my report!',            6,  4, 'm', 6), @('auditor', 'Non-compliant! Non-compliant!',      7,  5, 'm', 6)
    , @('pilot',   'Eject! Eject!',                           5,  5, 'm', 7)
    , @('boss',    'I am the administrator here!',          -10, -1, 'm', 8)
    @('uber',    'Terminating process.',                  -10, -3, 'f', 9), @('uber',    'P C load letter.',                    -10, -3, 'f', 9)
    @('guard.die',   'Null reference!',                   -2,  3, 'm', 5), @('guard.die',   'Unexpected token!',              0,  3, 'm', 5)
    , @('officer.die', 'Roll back! Roll back!',               4,  4, 'm', 5)
    @('elite.die',   'Stack overflow!',                   -6,  2, 'm', 5), @('shield.die',  'Connection reset.',              -8,  0, 'm', 5)
    , @('boss.die',    'I should have made a backup.',      -10, -2, 'm', 8)
    , @('uber.die',    'Fatal exception.',                  -10, -4, 'f', 9)
)

function Initialize-Voices {
    if (-not $script:SfxEnabled) { return }
    $dir = Join-Path (Split-Path $script:MusicDir) 'voice'
    try {
        $sapi = $null; $male = $null; $female = $null
        for ($i = 0; $i -lt $script:VoiceLines.Count; $i++) {
            $line = $script:VoiceLines[$i]
            $name = "say_$($line[0] -replace '\.', '_')_$i"
            $path = Join-Path $dir "$name-v$($script:VOICE_VERSION).wav"
            if (-not (Test-Path -LiteralPath $path)) {
                if (-not $sapi) {
                    # first run: wake the speech engine and look for English voices
                    $sapi = New-Object -ComObject SAPI.SpVoice
                    foreach ($v in $sapi.GetVoices()) {
                        $about = $v.GetDescription()
                        if ($about -notmatch 'English') { continue }
                        if ($v.GetAttribute('Gender') -eq 'Female') { if (-not $female) { $female = $v } } elseif (-not $male) { $male = $v }
                    }
                    if (-not $male -and -not $female) { throw 'no English voice is installed' }
                    $null = New-Item -ItemType Directory -Path $dir -Force
                    Get-ChildItem -LiteralPath $dir -Filter 'say_*.wav' | Where-Object Name -NotLike "*-v$($script:VOICE_VERSION).wav" | Remove-Item -Force -ErrorAction SilentlyContinue
                }
                $sapi.Voice = if ($line[4] -eq 'f' -and $female) { $female } elseif ($male) { $male } else { $female }
                $file = New-Object -ComObject SAPI.SpFileStream
                $file.Format.Type = 8                                  # 11 kHz, 8 bit, mono
                $file.Open($path, 3, $false)
                $sapi.AudioOutputStream = $file
                $text = [System.Security.SecurityElement]::Escape($line[1])
                $null = $sapi.Speak("<pitch middle=`"$($line[2])`"><rate speed=`"$($line[3])`">$text</rate></pitch>", 8)
                $file.Close()
            }
            $id = $script:Mixer::LoadWav([System.IO.File]::ReadAllBytes($path))
            if ($id -lt 0) { throw "cannot read $path" }
            $script:Sfx[$name] = @{ Id = $id; Seconds = $script:Mixer::Seconds($id); Prio = $line[5] }
            if (-not $script:Voices[$line[0]]) { $script:Voices[$line[0]] = @() }
            $script:Voices[$line[0]] += $name
        }
    }
    catch {
        Write-Verbose "No voices: $($_.Exception.Message)"
        $script:Voices = @{}
    }
}

# What somebody shouts when he notices the player / with his last breath. The choice of line is cosmetic, so
# it does not use the game's random generator.
function Get-AlertSound([Actor]$a) {
    $lines = $script:Voices[$a.Kind]
    if ($lines) { $lines[$script:FxRng.Next($lines.Count)] } else { $a.Def.AlertSnd }
}

function Get-DeathSound([Actor]$a) {
    $lines = $script:Voices["$($a.Kind).die"]
    if ($lines -and ($a.Kind -in 'boss', 'uber', 'bsod' -or $script:FxRng.Next(100) -lt 40)) { $lines[$script:FxRng.Next($lines.Count)] } else { $a.Def.DieSnd }
}
