# POLF 3D - Copyright (c) 2026 oNdsen. Licensed under the MIT License, see LICENSE.

<#
.SYNOPSIS
    Maintenance: builds the release ZIP of the game - and, with -Publish, the GitHub release that carries it.
.DESCRIPTION
    The ZIP holds what is needed to play and to build levels: the start script, Play.cmd, src, maps, demos, mods,
    tools, the README, the changelog and the licence - straight out of the committed state (git archive), so
    nothing that is lying around in the working copy gets in. The pictures of the README stay on GitHub.

    The file is always called polf3d.zip, so that
        https://github.com/oNdsen/polf3d/releases/latest/download/polf3d.zip
    is the newest one for ever. GitHub counts downloads per file of a release: never replace the file of a release
    that is out, make a new release - the download badge of the README adds them all up.

    The version is read from Start-Polf3D.ps1 ($script:PolfVersion), the release notes are that version's section
    of CHANGELOG.md plus the SHA256 of the ZIP, which the game's updater (src/Update.ps1) checks a download against.
    -Publish needs the GitHub CLI (gh), a clean working copy and a pushed main branch.
.PARAMETER Publish
    Tag the commit as v<version>, push the tag and create the GitHub release with the ZIP attached.
.EXAMPLE
    ./tools/New-Release.ps1              # just build bin/release/polf3d.zip and say what is in it
.EXAMPLE
    ./tools/New-Release.ps1 -Publish
#>
[CmdletBinding()]
param([switch]$Publish)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Push-Location $root
try {
    $start = Get-Content -LiteralPath (Join-Path $root 'Start-Polf3D.ps1') -Raw
    if ($start -notmatch "\`$script:PolfVersion = '(\d+\.\d+\.\d+)'") { throw 'No version found in Start-Polf3D.ps1.' }
    $version = $Matches[1]; $tag = "v$version"

    $log = Get-Content -LiteralPath (Join-Path $root 'CHANGELOG.md') -Raw
    if ($log -notmatch "(?ms)^## $([regex]::Escape($version))\b[^\n]*\n(.*?)(?=^## |\z)") { throw "CHANGELOG.md has no section for $version." }
    $notes = $Matches[1].Trim()

    if ($Publish) {
        if (git status --porcelain) { throw 'The working copy is not clean: commit first, a release is cut from a commit.' }
        git fetch --quiet origin
        if ((git rev-parse HEAD) -ne (git rev-parse origin/main)) { throw 'HEAD is not what is on origin/main: push first.' }
        if (git tag --list $tag) { throw "The tag $tag exists already. A release that is out is never replaced (its download count would go with it): raise the version." }
        if (-not (Get-Command gh -ErrorAction SilentlyContinue)) { throw 'The GitHub CLI (gh) is not installed.' }
    }

    $outDir = Join-Path $root 'bin/release'
    $null = New-Item -ItemType Directory -Path $outDir -Force
    $zip = Join-Path $outDir 'polf3d.zip'
    Remove-Item -LiteralPath $zip -ErrorAction SilentlyContinue
    git archive --format=zip --prefix=polf3d/ -o $zip HEAD -- Start-Polf3D.ps1 Play.cmd README.md HOW-IT-WAS-BUILT.md CHANGELOG.md LICENSE src maps demos mods tools
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $zip)) { throw 'git archive failed.' }

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [System.IO.Compression.ZipFile]::OpenRead($zip)
    $files = @($archive.Entries | Where-Object { $_.Name }); $archive.Dispose()
    foreach ($needed in 'polf3d/Start-Polf3D.ps1', 'polf3d/Play.cmd', 'polf3d/src/Game.ps1', 'polf3d/src/Scaler.cs', 'polf3d/maps/level1.map', 'polf3d/maps/arena.map', 'polf3d/maps/tutorial.map', 'polf3d/demos/attract.json', 'polf3d/LICENSE') {
        if ($needed -notin $files.FullName) { throw "The ZIP lacks $needed." }
    }
    $sha = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLowerInvariant()
    Write-Host ("POLF 3D {0}: {1}  -  {2} files, {3:0} KB, SHA256 {4}  (commit {5})" -f $version, $zip, $files.Count, ((Get-Item -LiteralPath $zip).Length / 1KB), $sha, (git rev-parse --short HEAD))

    if ($Publish) {
        $notesFile = Join-Path $outDir 'notes.md'
        Set-Content -LiteralPath $notesFile -Value "$notes`n`nSHA256 of polf3d.zip: ``$sha``" -Encoding utf8
        git tag -a $tag -m "POLF 3D $version"
        git push origin $tag
        gh release create $tag $zip --title "POLF 3D $version" --notes-file $notesFile
        if ($LASTEXITCODE -ne 0) { throw 'gh release create failed.' }
        Write-Host "Released: https://github.com/oNdsen/polf3d/releases/tag/$tag"
    }
}
finally { Pop-Location }
