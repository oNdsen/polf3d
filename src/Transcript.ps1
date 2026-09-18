# POLF 3D - Copyright (c) 2026 oNdsen. Licensed under the MIT License, see LICENSE.

# Transcript.ps1 - every floor writes its own Start-Transcript: what was killed with what, what was
# found, which powers were used, how it ended - and a dry remark about the performance. The file goes
# to saves/transcripts, the remark onto the "floor completed" screen.

$script:Transcript = $null

function Get-TranscriptTime { Format-Time ($script:Stats.Tics / $script:TICRATE) -Tenths }

function Start-RunTranscript {
    if ($script:Playback -or $script:Predicting) { $script:Transcript = $null; return }
    $script:Transcript = [System.Collections.Generic.List[string]]::new()
    $where = if ($script:DungeonSeed) { "DUNGEON-$($script:DungeonSeed)" } elseif ($script:BonusMap) { 'TREASURY' } else { "FLOOR$($script:LevelIndex + 1)" }
    foreach ($line in '**********************', 'PowerShell transcript start', "Start time: $((Get-Date).ToString('yyyyMMddHHmmss'))", 'Username: SHELLSTEIN\intruder',
        "Machine: $where ($($script:LevelName))", "Difficulty: $($script:Difficulties[$script:Difficulty].Name)", "Mods: $(if ($script:Mods) { $script:Mods -join ', ' } else { 'none' })", '**********************',
        "PS Shellstein:\$where> Enter-Floor -Weapon '$($script:Weapons[$script:P.Weapon].Name)' -Health $($script:P.Health)") { $script:Transcript.Add($line) }
}

# $Stream: '' (output) | VERBOSE | WARNING | ERROR - like the streams of the real thing.
function Add-TranscriptLine([string]$Text, [string]$Stream = '') {
    if (-not $script:Transcript -or $script:Predicting -or $script:Playback) { return }
    $script:Transcript.Add("$(Get-TranscriptTime)  $(if ($Stream) { "${Stream}: " })$Text")
}

# The closing remark: one line, picked by how it went.
function Get-TranscriptVerdict([bool]$Survived) {
    $st = $script:Stats; $p = $script:P
    $kills = Get-Percent $st.Kills $st.KillTotal; $seconds = $st.Tics / $script:TICRATE
    if (-not $Survived) { return 'Unhandled exception. The process was terminated by its environment.' }
    if ($p.Cheated) { return 'Completed with elevated privileges nobody remembers granting. Audit pending.' }
    if ($kills -eq 100 -and (Get-Percent $st.Secrets $st.SecretTotal) -eq 100 -and (Get-Percent $st.Treasures $st.TreasureTotal) -eq 100) { return 'Exit code 0. No survivors, no secrets, no loose change. HR has been informed.' }
    if ($kills -le 20) { return "Completed with $kills % of the staff still employed. A remarkably quiet change window." }
    if ($seconds -le $script:ParSeconds * 0.6) { return 'Completed well under par. Somebody skipped the change advisory board.' }
    if ($p.Health -le 15) { return "Completed with $($p.Health) health. Works in production; nobody should ask how." }
    if ($seconds -gt $script:ParSeconds * 2) { return 'Completed. Eventually. The ticket had already been escalated twice.' }
    if ($kills -eq 100) { return 'Completed. Everybody who was on shift has been logged off for good.' }
    'Completed. No findings. Next maintenance window: the floor above.'
}

function Stop-RunTranscript([bool]$Survived) {
    $t = $script:Transcript
    if (-not $t) { return $null }
    $script:Transcript = $null
    $st = $script:Stats
    $verdict = Get-TranscriptVerdict $Survived
    $t.Add("$(Get-TranscriptTime)  $(if ($Survived) { 'Exit-Floor' } else { 'ERROR: the pipeline has been stopped' })")
    $t.Add("          kills $($st.Kills)/$($st.KillTotal)   secrets $($st.Secrets)/$($st.SecretTotal)   treasure $($st.Treasures)/$($st.TreasureTotal)   health $($script:P.Health)   score $($script:P.Score)")
    $t.Add("          $verdict")
    foreach ($line in '**********************', 'PowerShell transcript end', "End time: $((Get-Date).ToString('yyyyMMddHHmmss'))", '**********************') { $t.Add($line) }
    try {
        $dir = Join-Path $script:SaveDir 'transcripts'
        $null = New-Item -ItemType Directory -Path $dir -Force
        $file = Join-Path $dir ("PowerShell_transcript.SHELLSTEIN.{0}.txt" -f (Get-Date).ToString('yyyyMMddHHmmss'))
        [System.IO.File]::WriteAllLines($file, $t)
        # a year of play should not fill the disk: keep the last fifty
        Get-ChildItem -LiteralPath $dir -Filter 'PowerShell_transcript.*.txt' | Sort-Object Name -Descending | Select-Object -Skip 50 | Remove-Item -Force -ErrorAction SilentlyContinue
    }
    catch { $file = $null }
    @{ Verdict = $verdict; File = $file }
}
