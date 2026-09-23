<#
    ProjectProvisioner.ps1
    Entry point for provisioning a single project's SharePoint site and Team.
    Callable three ways, all equivalent:

        .\ProjectProvisioner.ps1
            (no -Project) -> prompts interactively for Name/Number/Owner

        .\ProjectProvisioner.ps1 -Project @{ Name = 'Example'; Number = 'PRJ-001'; Owner = 'user@example.com' }
            -> runs immediately, no prompts (this is how the Launcher/TUI and
               any future API caller drive it)

        .\ProjectProvisioner.ps1 -Project $project -DryRun
            -> shows what would happen without creating anything

    This script has no knowledge of the Launcher/TUI - it only knows about
    project definitions, configuration and the provisioning engine.
#>
[CmdletBinding()]
param(
    [Parameter()]
    $Project,

    [Parameter()]
    [string]$ConfigPath,

    [Parameter()]
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$repoRoot = $PSScriptRoot

Import-Module (Join-Path $repoRoot 'Modules/Logging.psm1') -Force -Global
Import-Module (Join-Path $repoRoot 'Modules/Configuration.psm1') -Force -Global
Import-Module (Join-Path $repoRoot 'Modules/Authentication.psm1') -Force -Global
Import-Module (Join-Path $repoRoot 'Modules/ProjectInput.psm1') -Force -Global
Import-Module (Join-Path $repoRoot 'Modules/SharePoint.psm1') -Force -Global
Import-Module (Join-Path $repoRoot 'Modules/Teams.psm1') -Force -Global
Import-Module (Join-Path $repoRoot 'Modules/ProvisioningEngine.psm1') -Force -Global

try {
    $configuration = Get-NsgConfiguration -ConfigPath $ConfigPath -RepoRoot $repoRoot
    Initialize-NsgLogging -LogFilePath (Join-Path $repoRoot $configuration.logging.path)

    if ($configuration._IsExampleConfig) {
        Write-NsgLog "Running with example configuration (config/settings.example.json). Copy it to config/settings.json to customize." -Level Warning
    }

    if ($null -eq $Project) {
        $projectDefinition = Get-NsgProjectDefinitionInteractive
    }
    else {
        $projectDefinition = ConvertTo-NsgProjectDefinition -InputObject $Project
    }

    # Note: this script intentionally never calls `exit` - it may be invoked
    # in-process (Launcher, another script) via the call operator, and `exit`
    # would terminate the calling process too. Callers (including a plain
    # CLI invocation) should inspect the returned object's .Success property,
    # e.g.: $result = .\ProjectProvisioner.ps1 -Project $project; if (-not $result.Success) { ... }
    Invoke-NsgProjectProvisioning -Project $projectDefinition -Configuration $configuration -DryRun:$DryRun
}
catch {
    Write-Host "Provisioning failed unexpectedly: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor DarkGray
    [PSCustomObject]@{
        Project = $Project
        Success = $false
        Steps   = @([PSCustomObject]@{ Name = 'Unhandled error'; Success = $false; Skipped = $false; Mocked = $false; Details = $null; Error = $_.Exception.Message })
    }
}
