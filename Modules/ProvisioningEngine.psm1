<#
    ProvisioningEngine.psm1
    Orchestrates a full project provisioning run: validates input, creates the
    SharePoint site and the Team independently (one failing doesn't abort the
    other), creates channels only if the Team succeeded, and always returns a
    complete status object - callers decide what to do with a partial
    failure, this module never throws past step boundaries.
#>

function New-NsgProvisioningStep {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [bool]$Success,

        [Parameter()]
        [bool]$Skipped = $false,

        [Parameter()]
        [bool]$Mocked = $false,

        [Parameter()]
        [string]$Details = $null,

        [Parameter()]
        [string]$ErrorMessage = $null
    )

    return [PSCustomObject]@{
        Name    = $Name
        Success = $Success
        Skipped = $Skipped
        Mocked  = $Mocked
        Details = $Details
        Error   = $ErrorMessage
    }
}

function Invoke-NsgProjectProvisioning {
    <#
        .SYNOPSIS
        Runs the full provisioning workflow for a single project.

        .OUTPUTS
        PSCustomObject: Project, Success, Steps (array of step results)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Project,

        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Configuration,

        [Parameter()]
        [switch]$DryRun
    )

    $project = if ($Project -is [PSCustomObject] -and $Project.PSObject.Properties.Name -contains 'Name') {
        $Project
    }
    else {
        ConvertTo-NsgProjectDefinition -InputObject $Project
    }

    $validationErrors = Test-NsgProjectDefinition -Project $project
    if ($validationErrors.Count -gt 0) {
        foreach ($validationError in $validationErrors) {
            Write-NsgLog $validationError -Level Error
        }
        return [PSCustomObject]@{
            Project = $project
            Success = $false
            Steps   = @(New-NsgProvisioningStep -Name 'Input validation' -Success $false -ErrorMessage ($validationErrors -join '; '))
        }
    }

    Write-NsgLog "Starting provisioning for project '$($project.Name)' ($($project.Number))." -Level Info
    if ($DryRun) {
        Write-NsgLog "Dry run enabled - no resources will actually be created." -Level Warning
    }

    $steps = [System.Collections.Generic.List[PSCustomObject]]::new()
    $siteUrl = Get-NsgSiteUrl -Configuration $Configuration -Project $project
    $authContext = Get-NsgAuthenticationContext -Configuration $Configuration -SiteUrl $siteUrl

    if ($authContext.Mode -eq 'Certificate' -and -not $authContext.Connected -and -not $DryRun) {
        $steps.Add((New-NsgProvisioningStep -Name 'Authentication' -Success $false -ErrorMessage $authContext.Error))
        Write-NsgLog "Authentication failed: $($authContext.Error). Aborting provisioning." -Level Error
        return [PSCustomObject]@{
            Project = $project
            Success = $false
            Steps   = $steps.ToArray()
        }
    }

    # --- SharePoint site (independent step) ---
    $siteResult = New-NsgSharePointSite -Project $project -AuthContext $authContext -SiteUrl $siteUrl -DryRun:$DryRun
    $steps.Add((New-NsgProvisioningStep -Name 'SharePoint site' -Success $siteResult.Success -Skipped $siteResult.Skipped -Mocked $siteResult.Mocked -Details $siteResult.SiteUrl -ErrorMessage $siteResult.Error))

    # --- Team (independent step) ---
    $teamResult = New-NsgTeam -Project $project -AuthContext $authContext -DryRun:$DryRun
    $steps.Add((New-NsgProvisioningStep -Name 'Microsoft Team' -Success $teamResult.Success -Skipped $teamResult.Skipped -Mocked $teamResult.Mocked -Details $teamResult.DisplayName -ErrorMessage $teamResult.Error))

    # --- Channels (depends on Team having succeeded) ---
    if ($teamResult.Success -and $teamResult.TeamId) {
        $channelsResult = Add-NsgDefaultChannels -TeamId $teamResult.TeamId -Channels $Configuration.teams.defaultChannels -AuthContext $authContext -DryRun:$DryRun
        $channelDetails = "Created: $($channelsResult.Created -join ', ')"
        $steps.Add((New-NsgProvisioningStep -Name 'Default channels' -Success $channelsResult.Success -Details $channelDetails -ErrorMessage ($channelsResult.Errors -join '; ')))
    }
    else {
        $steps.Add((New-NsgProvisioningStep -Name 'Default channels' -Success $false -Skipped $true -Details 'Skipped because Team creation did not succeed.'))
    }

    if ($authContext.Mode -eq 'Certificate') {
        Disconnect-NsgContext -AuthContext $authContext
    }

    $overallSuccess = -not ($steps | Where-Object { -not $_.Success -and -not $_.Skipped })

    $summary = [PSCustomObject]@{
        Project = $project
        Success = [bool]$overallSuccess
        Steps   = $steps.ToArray()
    }

    Write-NsgProvisioningSummary -Summary $summary
    return $summary
}

function Write-NsgProvisioningSummary {
    <#
        .SYNOPSIS
        Prints a readable end-of-run summary so a partially failed run is
        never just a wall of exceptions.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Summary
    )

    Write-NsgLog '----------------------------------------' -Level Info
    Write-NsgLog "Provisioning summary for '$($Summary.Project.Name)' ($($Summary.Project.Number))" -Level Info

    foreach ($step in $Summary.Steps) {
        $status = if ($step.Skipped) { 'SKIPPED' } elseif ($step.Success) { 'OK' } else { 'FAILED' }
        $level = if ($step.Skipped) { 'Warning' } elseif ($step.Success) { 'Success' } else { 'Error' }
        $line = "  [$status] $($step.Name)"
        if ($step.Details) { $line += " - $($step.Details)" }
        if ($step.Error) { $line += " - ERROR: $($step.Error)" }
        Write-NsgLog $line -Level $level
    }

    $overall = if ($Summary.Success) { 'SUCCESS' } else { 'PARTIAL / FAILED' }
    $overallLevel = if ($Summary.Success) { 'Success' } else { 'Warning' }
    Write-NsgLog "Overall result: $overall" -Level $overallLevel
    Write-NsgLog '----------------------------------------' -Level Info
}

Export-ModuleMember -Function Invoke-NsgProjectProvisioning, Write-NsgProvisioningSummary, New-NsgProvisioningStep
