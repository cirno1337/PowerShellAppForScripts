<#
    Authentication.psm1
    Single place that decides HOW we connect (real certificate vs. mock).
    SharePoint.psm1 / Teams.psm1 never check the environment themselves -
    they receive a connection context from here and act on its .Mode.
    This is what lets ecm4nsg dev work today and a real cert work later
    without touching provisioning logic.
#>

function Get-NsgAuthenticationContext {
    <#
        .SYNOPSIS
        Builds (but does not necessarily connect) the authentication context
        for the current configuration. In Mock mode nothing touches the
        network. In Certificate mode this establishes a real PnP connection.

        .OUTPUTS
        PSCustomObject with: Mode, Connected, SiteUrl, Error
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Configuration,

        [Parameter(Mandatory = $true)]
        [string]$SiteUrl
    )

    $mode = $Configuration.authentication.mode

    if ($mode -eq 'Mock') {
        return [PSCustomObject]@{
            Mode      = 'Mock'
            Connected = $false
            SiteUrl   = $SiteUrl
            Error     = $null
        }
    }

    return Connect-NsgCertificateContext -Configuration $Configuration -SiteUrl $SiteUrl
}

function Assert-NsgPnPModuleAvailable {
    <#
        .SYNOPSIS
        Guards real (Certificate mode) code paths. Only called when we are
        actually about to connect for real, so Mock/DryRun usage never
        requires PnP.PowerShell to be installed.
    #>
    [CmdletBinding()]
    param()

    if (-not (Get-Module -ListAvailable -Name 'PnP.PowerShell')) {
        throw "PnP.PowerShell module is not installed. Install it with: Install-Module PnP.PowerShell -Scope CurrentUser"
    }

    if (-not (Get-Module -Name 'PnP.PowerShell')) {
        Import-Module PnP.PowerShell -ErrorAction Stop
    }
}

function Connect-NsgCertificateContext {
    <#
        .SYNOPSIS
        Establishes a real PnP Online connection using a certificate on disk.
        Never call this directly from provisioning logic - go through
        Get-NsgAuthenticationContext so Mock mode is respected.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingConvertToSecureStringWithPlainText', '',
        Justification = 'The certificate password only ever exists as plaintext in an environment variable; converting it to SecureString here is what hands it safely to Connect-PnPOnline.')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Configuration,

        [Parameter(Mandatory = $true)]
        [string]$SiteUrl
    )

    try {
        Assert-NsgPnPModuleAvailable

        $certPath = $Configuration.authentication.certificate.path
        if (-not (Test-Path -Path $certPath)) {
            throw "Certificate not found at '$certPath'."
        }

        $certPassword = Resolve-NsgCertificatePassword -Configuration $Configuration
        $tenantIdentifier = if ($Configuration.tenant.tenantId) { $Configuration.tenant.tenantId } else { $Configuration.tenant.tenantName }

        $connectParams = @{
            Url                = $SiteUrl
            ClientId           = $Configuration.authentication.clientId
            Tenant             = $tenantIdentifier
            CertificatePath    = $certPath
            ErrorAction        = 'Stop'
        }
        if ($certPassword) {
            $connectParams['CertificatePassword'] = (ConvertTo-SecureString -String $certPassword -AsPlainText -Force)
        }

        Connect-PnPOnline @connectParams

        return [PSCustomObject]@{
            Mode      = 'Certificate'
            Connected = $true
            SiteUrl   = $SiteUrl
            Error     = $null
        }
    }
    catch {
        return [PSCustomObject]@{
            Mode      = 'Certificate'
            Connected = $false
            SiteUrl   = $SiteUrl
            Error     = $_.Exception.Message
        }
    }
}

function Disconnect-NsgContext {
    <#
        .SYNOPSIS
        Tears down a real connection. No-op in Mock mode.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$AuthContext
    )

    if ($AuthContext.Mode -eq 'Certificate' -and $AuthContext.Connected) {
        Disconnect-PnPOnline -ErrorAction SilentlyContinue
    }
}

Export-ModuleMember -Function Get-NsgAuthenticationContext, Connect-NsgCertificateContext, Disconnect-NsgContext, Assert-NsgPnPModuleAvailable
