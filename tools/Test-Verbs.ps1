# POLF 3D - Copyright (c) 2026 oNdsen. Licensed under the MIT License, see LICENSE.

<#
.SYNOPSIS
    Checks that every function in the project uses an approved PowerShell verb (Get-Verb).
#>
[CmdletBinding()]
param([string]$Root = (Join-Path $PSScriptRoot '..'))

$approved = (Get-Verb).Verb
$bad = foreach ($file in Get-ChildItem -Path $Root -Recurse -Filter *.ps1 | Where-Object FullName -NotMatch '\\reference\\') {
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$null, [ref]$null)
    foreach ($fn in $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)) {
        $verb, $noun = $fn.Name -split '-', 2
        if (-not $noun -or $verb -notin $approved) {
            [pscustomobject]@{ Function = $fn.Name; File = $file.Name; Line = $fn.Extent.StartLineNumber }
        }
    }
}
if ($bad) { $bad | Format-Table -AutoSize; throw "$(@($bad).Count) function(s) without an approved verb." }
Write-Host 'All functions use approved verbs.' -ForegroundColor Green
