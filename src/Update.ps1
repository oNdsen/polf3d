# POLF 3D - Copyright (c) 2026 oNdsen. Licensed under the MIT License, see LICENSE.

# Update.ps1 - the game keeps itself up to date.
#
# Once a day the title screen asks GitHub for the latest release (one request, in the background, never in the way:
# offline, a slow line or a rate limit just mean no news). Is there a newer version, a line on the title screen says
# so, U shows what is new, and Enter downloads polf3d.zip, checks it against the SHA256 the release notes carry,
# unpacks it, keeps a copy of the files it replaces (polf3d-backup-<version>.zip next to the game), copies the new
# ones over the old and starts the game again. saves/, bin/ and your own mods are not touched.
#
# The same on the command line: ./Start-Polf3D.ps1 -Update. The check can be turned off in the options menu and
# with -NoUpdateCheck. Tests point $script:UpdateSource at a file, and the file's download links at files.

$script:UpdateSource = 'https://api.github.com/repos/oNdsen/polf3d/releases/latest'
$script:UpdateCheck = $null          # the background check while it runs: @{ Shell; Handle; Started }
$script:NewRelease = $null               # a newer release, once one is known: @{ Version; Tag; Notes; Zip; Sha; Url }
$script:UpdateState = ''             # what the title screen may say: '' (nothing yet), 'current', 'available', 'failed'
$script:UpdateCheckOff = $false       # -NoUpdateCheck

function Get-UpdateStampPath { Join-Path $script:SaveDir 'update-check.json' }

# The text of the latest release: from the GitHub API, or from a file (tests).
function Get-ReleaseText([string]$Source) {
    if ($Source -match '^https?://') {
        $headers = @{ 'User-Agent' = "polf3d/$script:PolfVersion"; Accept = 'application/vnd.github+json' }
        return (Invoke-WebRequest -Uri $Source -Headers $headers -TimeoutSec 8 -UseBasicParsing).Content
    }
    Get-Content -LiteralPath $Source -Raw
}

# What the game needs to know about a release - or $null when it is not a newer one with a ZIP.
function ConvertTo-UpdateInfo([string]$Text) {
    try { $release = $Text | ConvertFrom-Json -AsHashtable } catch { return $null }
    if (-not $release -or -not $release.tag_name -or [string]$release.tag_name -notmatch '^v?(\d+\.\d+\.\d+)$') { return $null }
    $version = [version]$Matches[1]
    if ($version -le [version]$script:PolfVersion) { return $null }
    $zip = @($release.assets | Where-Object { $_.name -eq 'polf3d.zip' })[0]
    if (-not $zip) { return $null }
    $notes = [string]$release.body
    $sha = if ($notes -match 'SHA256.{0,40}?([0-9A-Fa-f]{64})') { $Matches[1].ToLowerInvariant() } else { '' }
    @{ Version = $version; Tag = [string]$release.tag_name; Notes = $notes; Zip = [string]$zip.browser_download_url; Sha = $sha; Url = [string]$release.html_url }
}

# Starts the daily check in a runspace of its own. Yesterday's answer is good enough for today.
function Start-UpdateCheck {
    if ($script:UpdateCheck -or $script:UpdateState -or $script:UpdateCheckOff -or -not $script:Settings.UpdateCheck) { return }
    $stamp = Get-UpdateStampPath
    if (Test-Path -LiteralPath $stamp) {
        try {
            $last = Get-Content -LiteralPath $stamp -Raw | ConvertFrom-Json -AsHashtable
            if (((Get-Date) - [datetime]$last.Checked).TotalHours -lt 20) {
                $script:NewRelease = ConvertTo-UpdateInfo ([string]$last.Text)
                $script:UpdateState = if ($script:NewRelease) { 'available' } else { 'current' }
                return
            }
        }
        catch { }
    }
    $ps = [powershell]::Create()
    $null = $ps.AddScript({
        param($Source, $Agent)
        if ($Source -match '^https?://') { (Invoke-WebRequest -Uri $Source -Headers @{ 'User-Agent' = $Agent; Accept = 'application/vnd.github+json' } -TimeoutSec 8 -UseBasicParsing).Content }
        else { Get-Content -LiteralPath $Source -Raw }
    }).AddArgument($script:UpdateSource).AddArgument("polf3d/$script:PolfVersion")
    $script:UpdateCheck = @{ Shell = $ps; Handle = $ps.BeginInvoke(); Started = $script:Clock.Elapsed.TotalSeconds }
}

# Every title frame: has the check come back?
function Update-UpdateCheck {
    if (-not $script:UpdateCheck) { Start-UpdateCheck; return }
    $check = $script:UpdateCheck
    if (-not $check.Handle.IsCompleted) { if ($script:Clock.Elapsed.TotalSeconds - $check.Started -gt 15) { Stop-UpdateCheck; $script:UpdateState = 'failed' }; return }
    try {
        $text = [string](@($check.Shell.EndInvoke($check.Handle))[0])
        if ($check.Shell.HadErrors -or -not $text) { throw 'no answer' }
        $script:NewRelease = ConvertTo-UpdateInfo $text
        $script:UpdateState = if ($script:NewRelease) { 'available' } else { 'current' }
        try {
            $null = New-Item -ItemType Directory -Path $script:SaveDir -Force
            @{ Checked = (Get-Date).ToString('s'); Text = $text } | ConvertTo-Json -Compress | Set-Content -LiteralPath (Get-UpdateStampPath) -Encoding utf8
        }
        catch { }
    }
    catch { $script:UpdateState = 'failed' }
    finally { Stop-UpdateCheck }
}

function Stop-UpdateCheck {
    if (-not $script:UpdateCheck) { return }
    try { if (-not $script:UpdateCheck.Handle.IsCompleted) { $script:UpdateCheck.Shell.Stop() }; $script:UpdateCheck.Shell.Dispose() } catch { }
    $script:UpdateCheck = $null
}

# The line under the title screen, if there is anything to say.
function Get-UpdateNotice {
    if ($script:NewRelease) { return "new update available: v$($script:NewRelease.Version)" }
    ''
}

# The release notes as plain lines that fit the screen: markdown is for GitHub. The changelog is written in
# hard-wrapped lines, so a paragraph or a bullet is joined first and then wrapped to the width of the screen.
function Get-UpdateNotes([int]$Width = 108, [int]$Lines = 16) {
    $paragraphs = [System.Collections.Generic.List[string]]::new(); $current = ''
    foreach ($raw in ([string]$script:NewRelease.Notes) -split "`r?`n") {
        $line = ($raw -replace '\*\*|`|^#+\s*', '' -replace '^\s*[-*]\s+', '- ' -replace '\[([^\]]+)\]\([^)]+\)', '$1').Trim()
        if ($line -match '^SHA256' -or $line -match '^Download polf3d\.zip below') { continue }
        if (-not $line) { if ($current) { $paragraphs.Add($current); $paragraphs.Add(''); $current = '' }; continue }
        if ($line.StartsWith('- ') -and $current) { $paragraphs.Add($current); $current = $line }
        else { $current = if ($current) { "$current $line" } else { $line } }
    }
    if ($current) { $paragraphs.Add($current) }
    $out = [System.Collections.Generic.List[string]]::new()
    foreach ($paragraph in $paragraphs) {
        if (-not $paragraph) { if ($out.Count -and $out[$out.Count - 1]) { $out.Add('') }; continue }
        $indent = if ($paragraph.StartsWith('- ')) { '  ' } else { '' }
        $row = ''
        foreach ($word in $paragraph.Split(' ')) {
            if ($row.Length + $word.Length + 1 -gt $Width -and $row) { $out.Add($row); $row = "$indent$word" } else { $row = if ($row) { "$row $word" } else { $word } }
        }
        if ($row) { $out.Add($row) }
        if ($out.Count -ge $Lines) { break }
    }
    if ($out.Count -gt $Lines) { $out.RemoveRange($Lines, $out.Count - $Lines) }
    $out
}

# A file from a URL - or from a path (tests).
function Copy-UpdateFile([string]$Source, [string]$Destination) {
    if ($Source -match '^https?://') { Invoke-WebRequest -Uri $Source -OutFile $Destination -Headers @{ 'User-Agent' = "polf3d/$script:PolfVersion" } -TimeoutSec 120 -UseBasicParsing }
    else { Copy-Item -LiteralPath $Source -Destination $Destination -Force }
}

# The files the new version would replace, zipped next to the game: the way back if the new one disappoints.
function Save-UpdateBackup([string]$Root, [string]$New, [string]$Path) {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    Remove-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    $archive = [System.IO.Compression.ZipFile]::Open($Path, [System.IO.Compression.ZipArchiveMode]::Create)
    try {
        foreach ($file in Get-ChildItem -LiteralPath $New -File -Recurse) {
            $relative = $file.FullName.Substring($New.Length).TrimStart('\', '/')
            $old = Join-Path $Root $relative
            if (Test-Path -LiteralPath $old) { $null = [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive, $old, $relative.Replace('\', '/')) }
        }
    }
    finally { $archive.Dispose() }
}

# Downloads, checks, unpacks and installs $Info over $Root. Throws when anything is not as it should be - and
# throws before a single file of the game has been touched. $Report tells the player what is going on.
function Install-Update([hashtable]$Info, [string]$Root, [scriptblock]$Report = { param($Text) Write-Step $Text }) {
    $work = Join-Path ([System.IO.Path]::GetTempPath()) "polf3d-update-$($Info.Version)"
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
    $null = New-Item -ItemType Directory -Path $work -Force
    try {
        $zip = Join-Path $work 'polf3d.zip'
        & $Report "downloading POLF 3D $($Info.Version) ..."
        Copy-UpdateFile $Info.Zip $zip
        & $Report 'checking the download ...'
        if ($Info.Sha) {
            $hash = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLowerInvariant()
            if ($hash -ne $Info.Sha) { throw 'the download is damaged: its SHA256 is not the one the release names' }
        }
        Expand-Archive -LiteralPath $zip -DestinationPath $work -Force
        $new = Join-Path $work 'polf3d'
        $start = Join-Path $new 'Start-Polf3D.ps1'
        if (-not (Test-Path -LiteralPath $start)) { throw 'the ZIP holds no game (no Start-Polf3D.ps1 in it)' }
        if ((Get-Content -LiteralPath $start -Raw) -notmatch "\`$script:PolfVersion = '$([regex]::Escape("$($Info.Version)"))'") { throw "the ZIP is not version $($Info.Version)" }
        & $Report 'keeping a copy of the old files ...'
        $backup = Join-Path $Root "polf3d-backup-$script:PolfVersion.zip"
        Save-UpdateBackup $Root $new $backup
        & $Report 'installing ...'
        $installing = $true
        try {
            foreach ($file in Get-ChildItem -LiteralPath $new -File -Recurse) {
                $relative = $file.FullName.Substring($new.Length).TrimStart('\', '/')
                $target = Join-Path $Root $relative
                $null = New-Item -ItemType Directory -Path (Split-Path $target) -Force
                Copy-Item -LiteralPath $file.FullName -Destination $target -Force
            }
        }
        catch {
            # half way through is the one state the game must not be left in: the old files go back
            & $Report 'that failed - putting the old files back ...'
            $back = Restore-UpdateBackup $backup $Root
            throw "$($_.Exception.Message) - the old files are back ($back of them; the copy is $(Split-Path $backup -Leaf))"
        }
        $true
    }
    finally { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue }
}

# The files of a backup, back where they were - one by one, so that a file that cannot be written does not stop the
# rest. Returns how many went back.
function Restore-UpdateBackup([string]$Path, [string]$Root) {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [System.IO.Compression.ZipFile]::OpenRead($Path); $count = 0
    try {
        foreach ($entry in $archive.Entries) {
            if (-not $entry.Name) { continue }
            $target = Join-Path $Root $entry.FullName.Replace('/', '\')
            try { [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $target, $true); $count++ } catch { }
        }
    }
    finally { $archive.Dispose() }
    $count
}

# The command line the game was started with, so that it can start itself the same way: every parameter that was
# given, as it was given. -Update and -Version do not come along (they would only run once more).
function ConvertTo-StartArguments([System.Collections.IDictionary]$Bound) {
    $arguments = [System.Collections.Generic.List[string]]::new()
    foreach ($name in $Bound.Keys) {
        if ($name -in 'Update', 'Version') { continue }
        $value = $Bound[$name]
        if ($value -is [switch] -or $value -is [bool]) { if ($value) { $arguments.Add("-$name") }; continue }
        $arguments.Add("-$name"); $arguments.Add("$value")
    }
    $arguments.ToArray()
}

# The game starts itself again, the way it was started: Play.cmd if there is one, plain pwsh otherwise - and with
# the same parameters as the first time.
function Restart-Game([string]$Root) {
    $play = Join-Path $Root 'Play.cmd'
    $arguments = @($script:StartArguments)
    if (Test-Path -LiteralPath $play) {
        $quoted = @($arguments | ForEach-Object { if ($_ -match '\s') { "'$_'" } else { $_ } })      # Play.cmd hands them to a PowerShell command line
        Start-Process -FilePath 'cmd.exe' -ArgumentList (@('/c', "`"$play`"") + $quoted) -WorkingDirectory $Root
    }
    else {
        $quoted = @($arguments | ForEach-Object { if ($_ -match '\s') { "`"$_`"" } else { $_ } })
        Start-Process -FilePath 'pwsh' -ArgumentList (@('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$(Join-Path $Root 'Start-Polf3D.ps1')`"") + $quoted) -WorkingDirectory $Root
    }
    $script:Running = $false
}

# What the update is doing right now: the loading screen in the window, a line at the bottom of the terminal.
function Write-UpdateProgress([string]$Text) {
    if (-not $script:TerminalMode) { Show-LoadStep $Text; return }
    try { [Console]::SetCursorPosition(0, [Console]::WindowHeight - 1); [Console]::Write($Text.PadRight([Console]::WindowWidth - 1)) } catch { }
}

# Enter on the update screen: install, then start over. Says what went wrong if it did.
function Invoke-UpdateInstall {
    $root = Split-Path $PSScriptRoot
    try {
        $null = Install-Update $script:NewRelease $root { param($Text) Write-UpdateProgress $Text }
        Write-UpdateProgress "POLF 3D $($script:NewRelease.Version) is installed - starting it ..."
        Start-Sleep -Milliseconds 800
        Restart-Game $root
    }
    catch { Show-Message "Update failed: $($_.Exception.Message)"; Start-Sfx 'noway'; Set-Mode 'title' }
}

function Show-UpdateScreen {
    Show-Shade 'FF0A1020'
    Write-HudBar '2C54C4' 0 0 320 3; Write-HudBar '2C54C4' 0 237 320 3
    Write-HudText 'NEW UPDATE AVAILABLE' 'Big' 'FFFFFF' 0 14 320 24
    Write-HudText "v$($script:NewRelease.Version)   -   you have v$script:PolfVersion   -   what is new:" 'Small' '8FB0FF' 0 38 320 10
    $y = 54.0
    foreach ($line in (Get-UpdateNotes)) { Write-HudLine $line 'Small' 'C0C8D8' 18 $y; $y += 7.4 }
    Write-HudText '[Enter] download, install and restart the game     [Esc] back' 'Small' 'FFE860' 0 190 320 10
    Write-HudText 'saved games, settings and your own mods stay as they are' 'Small' '7080A0' 0 204 320 10
}

# -Update on the command line: check now, say what there is, install it.
function Invoke-Update {
    $root = Split-Path $PSScriptRoot
    Write-Step "POLF 3D $script:PolfVersion - asking for the latest release ..."
    $text = Get-ReleaseText $script:UpdateSource
    $info = ConvertTo-UpdateInfo $text
    if (-not $info) { Write-Step "this is the newest version there is."; return }
    Write-Step "POLF 3D $($info.Version) is out ($($info.Url))"
    $script:NewRelease = $info
    foreach ($line in (Get-UpdateNotes 100 40)) { Write-Host "    $line" }
    $null = Install-Update $info $root
    Write-Step "POLF 3D $($info.Version) is installed. The old files are in polf3d-backup-$script:PolfVersion.zip."
}
