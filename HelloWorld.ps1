<#
    HelloWorld.ps1
    Minimal demo script proving the registry -> input provider -> runner
    pipeline works end to end for a script with zero inputs.
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '',
    Justification = 'Inputs/DryRun are part of the generic contract every registered script accepts, even when this one ignores them.')]
[CmdletBinding()]
param(
    [Parameter()]
    [hashtable]$Inputs = @{},

    [Parameter()]
    [switch]$DryRun
)

Write-Host 'Hello World!'
