<#
    InputProvider.psm1
    Turns a script's declared "inputs" (from the registry) into actual
    values, either by prompting interactively or by taking preset values
    (used by tests, or by any future non-interactive caller such as an API).
#>

function Test-NsgInputValues {
    <#
        .SYNOPSIS
        Validates that all required inputs have a non-empty value.
        Returns an array of human-readable error strings (empty = valid).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        $InputDefinitions,

        [Parameter(Mandatory = $true)]
        [hashtable]$Values
    )

    $errors = [System.Collections.Generic.List[string]]::new()

    foreach ($inputDef in $InputDefinitions) {
        $isRequired = $true
        if ($inputDef.PSObject.Properties.Name -contains 'required') {
            $isRequired = [bool]$inputDef.required
        }

        if ($isRequired -and [string]::IsNullOrWhiteSpace([string]$Values[$inputDef.name])) {
            $errors.Add("'$($inputDef.name)' is required.")
        }
    }

    # The leading comma prevents PowerShell from unwrapping a single-error
    # array into a bare string on the way out.
    return ,$errors.ToArray()
}

function Get-NsgScriptInputValues {
    <#
        .SYNOPSIS
        Resolves values for every declared input of a script. Values already
        present in -PresetValues are used as-is; anything missing (and
        required) is prompted for interactively unless -NonInteractive is set,
        in which case missing required values raise an error instead.

        .OUTPUTS
        Hashtable of input name -> value.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        $InputDefinitions,

        [Parameter()]
        [hashtable]$PresetValues = @{},

        [Parameter()]
        [switch]$NonInteractive
    )

    $values = @{}
    foreach ($key in $PresetValues.Keys) {
        $values[$key] = $PresetValues[$key]
    }

    foreach ($inputDef in $InputDefinitions) {
        $isRequired = $true
        if ($inputDef.PSObject.Properties.Name -contains 'required') {
            $isRequired = [bool]$inputDef.required
        }

        $hasValue = -not [string]::IsNullOrWhiteSpace([string]$values[$inputDef.name])
        if ($hasValue) {
            continue
        }

        if ($NonInteractive) {
            if ($isRequired) {
                throw "Missing required input '$($inputDef.name)' and -NonInteractive was specified."
            }
            continue
        }

        $promptText = if ($inputDef.prompt) { $inputDef.prompt } else { $inputDef.name }
        do {
            $entered = Read-Host -Prompt $promptText
            if (-not $isRequired) { break }
            if ([string]::IsNullOrWhiteSpace($entered)) {
                Write-Host "'$($inputDef.name)' is required." -ForegroundColor Yellow
            }
        } while ([string]::IsNullOrWhiteSpace($entered))

        $values[$inputDef.name] = $entered
    }

    $errors = Test-NsgInputValues -InputDefinitions $InputDefinitions -Values $values
    if ($errors.Count -gt 0) {
        throw "Missing required input(s): $($errors -join '; ')"
    }

    return $values
}

Export-ModuleMember -Function Test-NsgInputValues, Get-NsgScriptInputValues
