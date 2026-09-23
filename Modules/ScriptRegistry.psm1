<#
    ScriptRegistry.psm1
    Loads and validates config/scripts.json - the single source of truth for
    "what automations exist". The Launcher never hardcodes a list of scripts;
    it always asks this module.
#>

function Get-NsgScriptRegistry {
    <#
        .SYNOPSIS
        Loads and validates the script registry from a JSON file.

        .OUTPUTS
        Array of PSCustomObject, one per registered script.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path -Path $Path)) {
        throw "Script registry not found at '$Path'."
    }

    $raw = Get-Content -Path $Path -Raw | ConvertFrom-Json

    if (-not $raw.scripts) {
        throw "Script registry '$Path' does not contain a 'scripts' array."
    }

    $errors = Test-NsgScriptRegistry -Scripts $raw.scripts
    if ($errors.Count -gt 0) {
        throw "Invalid script registry '$Path':`n - $($errors -join "`n - ")"
    }

    return $raw.scripts
}

function Test-NsgScriptRegistry {
    <#
        .SYNOPSIS
        Validates the shape of the scripts array. Returns an array of
        human-readable error strings (empty = valid).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        $Scripts
    )

    $errors = [System.Collections.Generic.List[string]]::new()
    $seenIds = [System.Collections.Generic.HashSet[string]]::new()

    $index = 0
    foreach ($entry in $Scripts) {
        $prefix = "Entry #$index"

        if (-not $entry.id) {
            $errors.Add("$prefix`: missing 'id'.")
        }
        elseif (-not $seenIds.Add($entry.id)) {
            $errors.Add("$prefix`: duplicate id '$($entry.id)'.")
        }

        if (-not $entry.name) {
            $errors.Add("$prefix ('$($entry.id)'): missing 'name'.")
        }

        if (-not $entry.script) {
            $errors.Add("$prefix ('$($entry.id)'): missing 'script'.")
        }

        if ($entry.inputs) {
            foreach ($inputDef in $entry.inputs) {
                if (-not $inputDef.name) {
                    $errors.Add("$prefix ('$($entry.id)'): an input is missing 'name'.")
                }
            }
        }

        $index++
    }

    # The leading comma prevents PowerShell from unwrapping a single-error
    # array into a bare string on the way out.
    return ,$errors.ToArray()
}

function Get-NsgScriptDefinition {
    <#
        .SYNOPSIS
        Looks up a single script definition by id.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        $Registry,

        [Parameter(Mandatory = $true)]
        [string]$Id
    )

    return $Registry | Where-Object { $_.id -eq $Id } | Select-Object -First 1
}

Export-ModuleMember -Function Get-NsgScriptRegistry, Test-NsgScriptRegistry, Get-NsgScriptDefinition
