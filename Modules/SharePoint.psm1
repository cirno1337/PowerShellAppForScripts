<#
    SharePoint.psm1
    SharePoint-specific provisioning logic. Every function takes an
    $AuthContext (from Authentication.psm1) and branches on its .Mode -
    the caller (ProvisioningEngine) never has to know about Mock vs real.
#>

function Test-NsgSharePointSiteExists {
    <#
        .SYNOPSIS
        Checks whether a site already exists at the given URL.
        In Mock mode we can't safely know, so we say "no" and log that the
        check was skipped rather than pretending we verified it.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$AuthContext,

        [Parameter(Mandatory = $true)]
        [string]$SiteUrl
    )

    if ($AuthContext.Mode -eq 'Mock') {
        Write-NsgMockAction "Skipping existence check for site '$SiteUrl' (mock mode)."
        return $false
    }

    try {
        $site = Get-PnPTenantSite -Url $SiteUrl -ErrorAction Stop
        return [bool]$site
    }
    catch {
        return $false
    }
}

function New-NsgSharePointSite {
    <#
        .SYNOPSIS
        Creates a SharePoint team site for the project, unless it already
        exists (idempotent) or we are in Mock/DryRun.

        .OUTPUTS
        PSCustomObject: Success, SiteUrl, Skipped, Mocked, Error
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Project,

        [Parameter(Mandatory = $true)]
        [PSCustomObject]$AuthContext,

        [Parameter(Mandatory = $true)]
        [string]$SiteUrl,

        [Parameter()]
        [switch]$DryRun
    )

    $result = [PSCustomObject]@{
        Success = $false
        SiteUrl = $SiteUrl
        Skipped = $false
        Mocked  = $false
        Error   = $null
    }

    if ($AuthContext.Mode -eq 'Mock' -or $DryRun) {
        Write-NsgMockAction "Would create SharePoint site: $SiteUrl (title: '$($Project.Name)', owner: $($Project.Owner))"
        $result.Success = $true
        $result.Mocked = $true
        return $result
    }

    try {
        if (Test-NsgSharePointSiteExists -AuthContext $AuthContext -SiteUrl $SiteUrl) {
            Write-NsgLog "SharePoint site already exists at '$SiteUrl'. Skipping creation." -Level Warning
            $result.Success = $true
            $result.Skipped = $true
            return $result
        }

        # TeamSiteWithoutMicrosoft365Group: a modern team site at an explicit
        # -Url with an explicit -Owner, and no Microsoft 365 group of its own.
        # The project's Team (with its own group) is provisioned separately
        # by Teams.psm1 - using plain -Type TeamSite here would create a
        # second, redundant Microsoft 365 group tied to this site.
        New-PnPSite -Type TeamSiteWithoutMicrosoft365Group -Title $Project.Name -Url $SiteUrl -Owner $Project.Owner -Wait -ErrorAction Stop | Out-Null
        Write-NsgLog "Created SharePoint site: $SiteUrl" -Level Success
        $result.Success = $true
        return $result
    }
    catch {
        $result.Error = $_.Exception.Message
        Write-NsgLog "Failed to create SharePoint site '$SiteUrl': $($result.Error)" -Level Error
        return $result
    }
}

Export-ModuleMember -Function Test-NsgSharePointSiteExists, New-NsgSharePointSite
