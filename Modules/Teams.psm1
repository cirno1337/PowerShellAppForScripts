<#
    Teams.psm1
    Microsoft Team + channel provisioning, built on PnP.PowerShell's Graph
    wrappers (New-PnPMicrosoft365Group / New-PnPTeamsTeam / New-PnPTeamsChannel)
    so the project only depends on one PowerShell module for both SharePoint
    and Teams.
#>

function Get-NsgTeamMailNickname {
    <#
        .SYNOPSIS
        Derives a stable, Graph-safe mail nickname from the project number,
        used both to create the group and to check for an existing one.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Project
    )

    return ($Project.Number -replace '[^A-Za-z0-9]', '').ToLowerInvariant()
}

function Test-NsgTeamExists {
    <#
        .SYNOPSIS
        Checks whether a Microsoft 365 Group (Team) already exists for this
        project's mail nickname. Skipped in Mock mode.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$AuthContext,

        [Parameter(Mandatory = $true)]
        [string]$MailNickname
    )

    if ($AuthContext.Mode -eq 'Mock') {
        Write-NsgMockAction "Skipping existence check for Team '$MailNickname' (mock mode)."
        return $null
    }

    $existing = Get-PnPMicrosoft365Group -Identity $MailNickname -ErrorAction SilentlyContinue
    return $existing
}

function New-NsgTeam {
    <#
        .SYNOPSIS
        Creates a Microsoft 365 Group and teamifies it, unless it already
        exists or we are in Mock/DryRun.

        .OUTPUTS
        PSCustomObject: Success, TeamId, DisplayName, Skipped, Mocked, Error
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Project,

        [Parameter(Mandatory = $true)]
        [PSCustomObject]$AuthContext,

        [Parameter()]
        [switch]$DryRun
    )

    $displayName = "$($Project.Number) $($Project.Name)"
    $mailNickname = Get-NsgTeamMailNickname -Project $Project

    $result = [PSCustomObject]@{
        Success     = $false
        TeamId      = $null
        DisplayName = $displayName
        Skipped     = $false
        Mocked      = $false
        Error       = $null
    }

    if ($AuthContext.Mode -eq 'Mock' -or $DryRun) {
        Write-NsgMockAction "Would create Team: $displayName (owner: $($Project.Owner))"
        $result.Success = $true
        $result.Mocked = $true
        $result.TeamId = "mock-team-$mailNickname"
        return $result
    }

    try {
        $existing = Test-NsgTeamExists -AuthContext $AuthContext -MailNickname $mailNickname
        if ($existing) {
            Write-NsgLog "Team '$displayName' already exists. Skipping creation." -Level Warning
            $result.Success = $true
            $result.Skipped = $true
            $result.TeamId = $existing.Id
            return $result
        }

        $group = New-PnPMicrosoft365Group -DisplayName $displayName -MailNickname $mailNickname -Description "Project team for $displayName" -Owners $Project.Owner -ErrorAction Stop
        New-PnPTeamsTeam -GroupId $group.Id -ErrorAction Stop | Out-Null

        Write-NsgLog "Created Team: $displayName ($($group.Id))" -Level Success
        $result.Success = $true
        $result.TeamId = $group.Id
        return $result
    }
    catch {
        $result.Error = $_.Exception.Message
        Write-NsgLog "Failed to create Team '$displayName': $($result.Error)" -Level Error
        return $result
    }
}

function Add-NsgDefaultChannels {
    <#
        .SYNOPSIS
        Creates the configured default channels on a Team. "General" is
        skipped because Microsoft Teams already creates it automatically -
        attempting to create it again would just fail noisily.

        .OUTPUTS
        PSCustomObject: Success, Created (array), Skipped (array), Errors (array)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TeamId,

        [Parameter(Mandatory = $true)]
        [string[]]$Channels,

        [Parameter(Mandatory = $true)]
        [PSCustomObject]$AuthContext,

        [Parameter()]
        [switch]$DryRun
    )

    $created = [System.Collections.Generic.List[string]]::new()
    $skipped = [System.Collections.Generic.List[string]]::new()
    $errors = [System.Collections.Generic.List[string]]::new()

    foreach ($channel in $Channels) {
        if ($channel -eq 'General') {
            $skipped.Add($channel)
            continue
        }

        if ($AuthContext.Mode -eq 'Mock' -or $DryRun) {
            Write-NsgMockAction "Would create channel: $channel"
            $created.Add($channel)
            continue
        }

        try {
            New-PnPTeamsChannel -Team $TeamId -DisplayName $channel -ErrorAction Stop | Out-Null
            Write-NsgLog "Created channel: $channel" -Level Success
            $created.Add($channel)
        }
        catch {
            $errors.Add("$channel`: $($_.Exception.Message)")
            Write-NsgLog "Failed to create channel '$channel': $($_.Exception.Message)" -Level Error
        }
    }

    return [PSCustomObject]@{
        Success = ($errors.Count -eq 0)
        Created = $created.ToArray()
        Skipped = $skipped.ToArray()
        Errors  = $errors.ToArray()
    }
}

Export-ModuleMember -Function Get-NsgTeamMailNickname, Test-NsgTeamExists, New-NsgTeam, Add-NsgDefaultChannels
