<#
    ScriptRunner.psm1
    Dispatches a registry entry to its underlying .ps1 file. This is the only
    place that knows how to actually invoke a script file; everything above
    it (Launcher) only deals with registry entries and input values.
#>

function Invoke-NsgScriptFile {
    <#
        .SYNOPSIS
        Thin wrapper around calling a script file with a parameter hashtable.
        Kept separate (rather than inlined with '&') so it can be mocked in
        tests without actually executing scripts.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ScriptPath,

        [Parameter(Mandatory = $true)]
        [hashtable]$Parameters
    )

    return & $ScriptPath @Parameters
}

function Invoke-NsgRegisteredScript {
    <#
        .SYNOPSIS
        Resolves a registry entry's script file relative to -RootPath and
        invokes it, binding the collected input values to the parameter name
        declared by the entry (defaulting to 'Inputs').
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $ScriptDefinition,

        [Parameter(Mandatory = $true)]
        [hashtable]$Values,

        [Parameter(Mandatory = $true)]
        [string]$RootPath,

        [Parameter()]
        [switch]$DryRun
    )

    $scriptPath = Join-Path -Path $RootPath -ChildPath $ScriptDefinition.script
    if (-not (Test-Path -Path $scriptPath)) {
        throw "Registered script file not found: '$scriptPath' (id: '$($ScriptDefinition.id)')."
    }

    $parameterName = if ($ScriptDefinition.PSObject.Properties.Name -contains 'parameterName' -and $ScriptDefinition.parameterName) {
        $ScriptDefinition.parameterName
    }
    else {
        'Inputs'
    }

    $parameters = @{ $parameterName = $Values }
    if ($DryRun) {
        $parameters['DryRun'] = $true
    }

    return Invoke-NsgScriptFile -ScriptPath $scriptPath -Parameters $parameters
}

Export-ModuleMember -Function Invoke-NsgScriptFile, Invoke-NsgRegisteredScript
