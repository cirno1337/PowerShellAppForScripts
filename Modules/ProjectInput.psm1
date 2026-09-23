<#
    ProjectInput.psm1
    Everything about *what a project is* and how to validate it. Deliberately
    has no idea whether the data came from Read-Host, a TUI, a hashtable
    passed by another script, or JSON from an API - that separation is the
    whole point (see README architecture section).
#>

function New-NsgProjectDefinition {
    <#
        .SYNOPSIS
        Builds a canonical project definition object from raw values,
        regardless of where they came from.
    #>
    [CmdletBinding()]
    param(
        # Empty strings are allowed to pass through here on purpose: this
        # function only builds the shape of a project definition.
        # Test-NsgProjectDefinition is what decides whether the values are
        # actually valid, so callers get a real validation error list instead
        # of a raw parameter-binding exception for a blank field.
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Number,

        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Owner
    )

    return [PSCustomObject]@{
        Name   = $Name
        Number = $Number
        Owner  = $Owner
    }
}

function ConvertTo-NsgProjectDefinition {
    <#
        .SYNOPSIS
        Normalizes a hashtable or PSCustomObject (e.g. coming from the
        TUI's generic -Inputs value bag) into a canonical project definition.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $InputObject
    )

    $asHashtable = @{}
    if ($InputObject -is [hashtable]) {
        $asHashtable = $InputObject
    }
    else {
        foreach ($property in $InputObject.PSObject.Properties) {
            $asHashtable[$property.Name] = $property.Value
        }
    }

    return New-NsgProjectDefinition -Name $asHashtable['Name'] -Number $asHashtable['Number'] -Owner $asHashtable['Owner']
}

function Test-NsgProjectDefinition {
    <#
        .SYNOPSIS
        Validates a project definition. Returns an array of human-readable
        error strings; empty array means the project is valid.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Project
    )

    $errors = [System.Collections.Generic.List[string]]::new()

    if (-not $Project) {
        $errors.Add('Project definition is missing.')
        return ,$errors.ToArray()
    }

    if ([string]::IsNullOrWhiteSpace($Project.Name)) {
        $errors.Add('Project name is required.')
    }

    if ([string]::IsNullOrWhiteSpace($Project.Number)) {
        $errors.Add('Project number is required.')
    }
    elseif ($Project.Number -notmatch '^[A-Za-z0-9][A-Za-z0-9-]*$') {
        $errors.Add("Project number '$($Project.Number)' contains invalid characters (letters, digits and hyphens only).")
    }

    if ([string]::IsNullOrWhiteSpace($Project.Owner)) {
        $errors.Add('Project owner is required.')
    }
    elseif ($Project.Owner -notmatch '^[^@\s]+@[^@\s]+\.[^@\s]+$') {
        $errors.Add("Project owner '$($Project.Owner)' does not look like a valid email address.")
    }

    # The leading comma prevents PowerShell from unwrapping a single-error
    # array into a bare string on the way out.
    return ,$errors.ToArray()
}

function Get-NsgProjectDefinitionInteractive {
    <#
        .SYNOPSIS
        Prompts the user on the console for project details, re-prompting
        on validation failure. This is ONE way to get a project definition -
        callers that already have the data should use New-NsgProjectDefinition
        directly instead.
    #>
    [CmdletBinding()]
    param()

    while ($true) {
        $name = Read-Host -Prompt 'Project name'
        $number = Read-Host -Prompt 'Project number'
        $owner = Read-Host -Prompt 'Project owner (email)'

        $project = New-NsgProjectDefinition -Name $name -Number $number -Owner $owner
        $errors = Test-NsgProjectDefinition -Project $project

        if ($errors.Count -eq 0) {
            return $project
        }

        Write-Host "Please fix the following before continuing:" -ForegroundColor Yellow
        foreach ($validationError in $errors) {
            Write-Host " - $validationError" -ForegroundColor Yellow
        }
    }
}

Export-ModuleMember -Function New-NsgProjectDefinition, ConvertTo-NsgProjectDefinition, Test-NsgProjectDefinition, Get-NsgProjectDefinitionInteractive
