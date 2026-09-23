<#
    Logging.psm1
    Console + file logging shared by every module and script in this project.
    Callers never write to Write-Host directly so the destination/format can
    change in one place (e.g. structured logging later) without touching
    business logic.
#>

$script:NsgLogFilePath = $null

function Initialize-NsgLogging {
    <#
        .SYNOPSIS
        Configures where log entries are written. Safe to call multiple times.
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$LogFilePath
    )

    if ([string]::IsNullOrWhiteSpace($LogFilePath)) {
        $script:NsgLogFilePath = $null
        return
    }

    $directory = Split-Path -Path $LogFilePath -Parent
    if ($directory -and -not (Test-Path -Path $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }

    $script:NsgLogFilePath = $LogFilePath
}

function Write-NsgLog {
    <#
        .SYNOPSIS
        Writes a single log entry to the console (colored) and, if configured,
        to the active log file.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Message,

        [Parameter()]
        [ValidateSet('Info', 'Success', 'Warning', 'Error', 'Mock')]
        [string]$Level = 'Info'
    )

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line = "[{0}] [{1}] {2}" -f $timestamp, $Level.ToUpperInvariant(), $Message

    $color = switch ($Level) {
        'Success' { 'Green' }
        'Warning' { 'Yellow' }
        'Error'   { 'Red' }
        'Mock'    { 'Cyan' }
        default   { 'Gray' }
    }

    Write-Host $line -ForegroundColor $color

    if ($script:NsgLogFilePath) {
        Add-Content -Path $script:NsgLogFilePath -Value $line
    }
}

function Write-NsgMockAction {
    <#
        .SYNOPSIS
        Standard formatting for "would have done X" messages in Mock/DryRun mode,
        so the [DEV/MOCK] prefix is consistent everywhere it's used.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Action
    )

    Write-NsgLog -Message "[DEV/MOCK] $Action" -Level Mock
}

Export-ModuleMember -Function Initialize-NsgLogging, Write-NsgLog, Write-NsgMockAction
