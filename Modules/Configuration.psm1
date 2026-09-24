<#
    Configuration.psm1
    Loads and validates the JSON configuration that drives tenant/auth/site/
    Teams settings. Nothing here talks to SharePoint, Teams or the network -
    it only knows how to turn a JSON file into a validated object, and how to
    resolve secrets (certificate password) from the environment rather than
    from the file itself.
#>

function Get-NsgConfiguration {
    <#
        .SYNOPSIS
        Loads configuration from -ConfigPath, falling back to
        config/settings.example.json when the real settings file doesn't
        exist yet (with a loud warning - example values are not usable
        against a real tenant).

        .PARAMETER ConfigPath
        Path to settings.json. Defaults to <RepoRoot>/config/settings.json.

        .PARAMETER RepoRoot
        Root of the project, used to resolve default paths.
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$ConfigPath,

        [Parameter()]
        [string]$RepoRoot = (Split-Path -Path $PSScriptRoot -Parent)
    )

    if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
        $ConfigPath = Join-Path -Path $RepoRoot -ChildPath 'config/settings.json'
    }

    $usingExample = $false
    if (-not (Test-Path -Path $ConfigPath)) {
        $examplePath = Join-Path -Path $RepoRoot -ChildPath 'config/settings.example.json'
        if (-not (Test-Path -Path $examplePath)) {
            throw "No configuration found. Expected '$ConfigPath' or '$examplePath'."
        }
        Write-Warning "Configuration file '$ConfigPath' not found. Falling back to settings.example.json - these values will NOT work against a real tenant."
        $ConfigPath = $examplePath
        $usingExample = $true
    }

    $raw = Get-Content -Path $ConfigPath -Raw | ConvertFrom-Json

    $errors = Test-NsgConfiguration -Configuration $raw
    if ($errors.Count -gt 0) {
        throw "Invalid configuration in '$ConfigPath':`n - $($errors -join "`n - ")"
    }

    $raw | Add-Member -NotePropertyName '_IsExampleConfig' -NotePropertyValue $usingExample -Force
    $raw | Add-Member -NotePropertyName '_ConfigPath' -NotePropertyValue $ConfigPath -Force
    $raw | Add-Member -NotePropertyName '_RepoRoot' -NotePropertyValue $RepoRoot -Force

    return $raw
}

function Test-NsgConfiguration {
    <#
        .SYNOPSIS
        Validates the shape of a loaded configuration object.
        Returns an array of human-readable error strings (empty = valid).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Configuration
    )

    $errors = [System.Collections.Generic.List[string]]::new()

    if (-not $Configuration.environment) {
        $errors.Add("Missing 'environment' (expected 'Development' or 'Production').")
    }

    if (-not $Configuration.authentication) {
        $errors.Add("Missing 'authentication' section.")
    }
    elseif ($Configuration.authentication.mode -notin @('Mock', 'Certificate')) {
        $errors.Add("'authentication.mode' must be 'Mock' or 'Certificate', got '$($Configuration.authentication.mode)'.")
    }

    if ($Configuration.authentication.mode -eq 'Certificate') {
        if (-not $Configuration.authentication.clientId) {
            $errors.Add("'authentication.clientId' is required when mode is 'Certificate'.")
        }
        if (-not $Configuration.tenant.tenantId -and -not $Configuration.tenant.tenantName) {
            $errors.Add("'tenant.tenantId' or 'tenant.tenantName' is required when mode is 'Certificate'.")
        }
        if (-not $Configuration.tenant.adminSiteUrl) {
            $errors.Add("'tenant.adminSiteUrl' is required when mode is 'Certificate' (site creation must connect to an existing site, not the one being created).")
        }
        if (-not $Configuration.authentication.certificate.path) {
            $errors.Add("'authentication.certificate.path' is required when mode is 'Certificate'.")
        }
    }

    if (-not $Configuration.sharePoint.baseUrl) {
        $errors.Add("Missing 'sharePoint.baseUrl'.")
    }

    if (-not $Configuration.sharePoint.siteUrlPattern) {
        $errors.Add("Missing 'sharePoint.siteUrlPattern'.")
    }

    if (-not $Configuration.teams -or -not $Configuration.teams.defaultChannels -or $Configuration.teams.defaultChannels.Count -eq 0) {
        $errors.Add("'teams.defaultChannels' must contain at least one channel.")
    }

    # The leading comma prevents PowerShell from unwrapping a single-error
    # array into a bare string on the way out.
    return ,$errors.ToArray()
}

function Resolve-NsgCertificatePassword {
    <#
        .SYNOPSIS
        Resolves the certificate password from the environment variable named
        in configuration. The password itself is never stored in JSON.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Configuration
    )

    $envVarName = $Configuration.authentication.certificate.passwordEnvironmentVariable
    if ([string]::IsNullOrWhiteSpace($envVarName)) {
        return $null
    }

    $value = [System.Environment]::GetEnvironmentVariable($envVarName)
    return $value
}

function Get-NsgSiteUrl {
    <#
        .SYNOPSIS
        Builds the target SharePoint site URL for a project from
        sharePoint.baseUrl + sharePoint.siteUrlPattern, substituting
        {Name}/{Number}/{Owner} tokens from the project definition.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Configuration,

        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Project
    )

    $slug = $Configuration.sharePoint.siteUrlPattern
    $slug = $slug.Replace('{Name}', ($Project.Name -replace '[^a-zA-Z0-9-]', '-'))
    $slug = $slug.Replace('{Number}', ($Project.Number -replace '[^a-zA-Z0-9-]', '-'))
    $slug = $slug.Replace('{Owner}', ($Project.Owner -replace '[^a-zA-Z0-9-]', '-'))

    $baseUrl = $Configuration.sharePoint.baseUrl.TrimEnd('/')
    return "$baseUrl/$slug"
}

Export-ModuleMember -Function Get-NsgConfiguration, Test-NsgConfiguration, Resolve-NsgCertificatePassword, Get-NsgSiteUrl
