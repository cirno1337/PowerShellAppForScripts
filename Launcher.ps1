<#
    Launcher.ps1
    Registry-driven TUI. This file knows nothing about SharePoint, Teams or
    any specific automation - it only knows how to render config/scripts.json
    as a menu, collect the inputs each entry declares, and hand off to
    ScriptRunner. Adding a new automation never requires editing this file;
    see README.md "Adding a new script to the TUI".
#>
[CmdletBinding()]
param(
    [Parameter()]
    [string]$ScriptsPath,

    [Parameter()]
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$repoRoot = $PSScriptRoot

Import-Module (Join-Path $repoRoot 'Modules/Logging.psm1') -Force -Global
Import-Module (Join-Path $repoRoot 'Modules/ScriptRegistry.psm1') -Force -Global
Import-Module (Join-Path $repoRoot 'Modules/InputProvider.psm1') -Force -Global
Import-Module (Join-Path $repoRoot 'Modules/ScriptRunner.psm1') -Force -Global

if ([string]::IsNullOrWhiteSpace($ScriptsPath)) {
    $ScriptsPath = Join-Path $repoRoot 'config/scripts.json'
}

function Show-NsgMenu {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        $Registry
    )

    Write-Host '========================================'
    Write-Host '        NSG Project Automation'
    Write-Host '========================================'
    Write-Host ''

    $index = 1
    foreach ($entry in $Registry) {
        Write-Host "$index. $($entry.name)"
        $index++
    }
    Write-Host 'Q. Exit'
    Write-Host ''
}

function Read-NsgMenuChoice {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        $Registry
    )

    $choice = Read-Host -Prompt 'Select an option'

    if ($choice -in @('Q', 'q')) {
        return $null
    }

    $choiceIndex = 0
    if (-not [int]::TryParse($choice, [ref]$choiceIndex)) {
        Write-Host "Invalid choice: '$choice'" -ForegroundColor Yellow
        return 'invalid'
    }

    if ($choiceIndex -lt 1 -or $choiceIndex -gt $Registry.Count) {
        Write-Host "Invalid choice: '$choice'" -ForegroundColor Yellow
        return 'invalid'
    }

    return $Registry[$choiceIndex - 1]
}

try {
    $registry = Get-NsgScriptRegistry -Path $ScriptsPath
}
catch {
    Write-Host "Failed to load script registry: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

while ($true) {
    Show-NsgMenu -Registry $registry
    $selection = Read-NsgMenuChoice -Registry $registry

    if ($null -eq $selection) {
        Write-Host 'Goodbye.'
        break
    }
    if ($selection -eq 'invalid') {
        continue
    }

    Write-Host ''
    Write-Host "Running: $($selection.name)" -ForegroundColor Cyan

    try {
        $values = Get-NsgScriptInputValues -InputDefinitions $selection.inputs
        Invoke-NsgRegisteredScript -ScriptDefinition $selection -Values $values -RootPath $repoRoot -DryRun:$DryRun | Out-Null
    }
    catch {
        Write-Host "'$($selection.name)' failed: $($_.Exception.Message)" -ForegroundColor Red
    }

    Write-Host ''
    Read-Host -Prompt 'Press Enter to return to the menu' | Out-Null
}
