BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    Import-Module (Join-Path $repoRoot 'Modules/Logging.psm1') -Force
    Import-Module (Join-Path $repoRoot 'Modules/Configuration.psm1') -Force
    Import-Module (Join-Path $repoRoot 'Modules/Authentication.psm1') -Force
    Import-Module (Join-Path $repoRoot 'Modules/ProjectInput.psm1') -Force
    Import-Module (Join-Path $repoRoot 'Modules/SharePoint.psm1') -Force
    Import-Module (Join-Path $repoRoot 'Modules/Teams.psm1') -Force
    Import-Module (Join-Path $repoRoot 'Modules/ProvisioningEngine.psm1') -Force

    $script:TestConfig = [PSCustomObject]@{
        environment    = 'Development'
        authentication = [PSCustomObject]@{ mode = 'Mock' }
        tenant         = [PSCustomObject]@{}
        sharePoint     = [PSCustomObject]@{ baseUrl = 'https://contoso.sharepoint.com/sites/'; siteUrlPattern = '{Number}-{Name}' }
        teams          = [PSCustomObject]@{ defaultChannels = @('General', 'Project Management', 'Documentation') }
    }

    $script:TestProject = New-NsgProjectDefinition -Name 'Example Project' -Number 'PRJ-001' -Owner 'user@example.com'
}

Describe 'Invoke-NsgProjectProvisioning' {

    BeforeEach {
        Mock -CommandName Get-NsgAuthenticationContext -ModuleName ProvisioningEngine -MockWith {
            [PSCustomObject]@{ Mode = 'Mock'; Connected = $false; SiteUrl = 'https://contoso.sharepoint.com/sites/PRJ-001-Example-Project'; Error = $null }
        }
    }

    It 'fails fast on an invalid project without attempting any provisioning' {
        Mock -CommandName New-NsgSharePointSite -ModuleName ProvisioningEngine
        Mock -CommandName New-NsgTeam -ModuleName ProvisioningEngine

        $invalidProject = New-NsgProjectDefinition -Name '' -Number 'PRJ-001' -Owner 'user@example.com'

        $result = Invoke-NsgProjectProvisioning -Project $invalidProject -Configuration $script:TestConfig

        $result.Success | Should -BeFalse
        $result.Steps[0].Name | Should -Be 'Input validation'
        Should -Invoke -CommandName New-NsgSharePointSite -ModuleName ProvisioningEngine -Times 0
        Should -Invoke -CommandName New-NsgTeam -ModuleName ProvisioningEngine -Times 0
    }

    It 'reports overall success when every step succeeds' {
        Mock -CommandName New-NsgSharePointSite -ModuleName ProvisioningEngine -MockWith {
            [PSCustomObject]@{ Success = $true; SiteUrl = 'https://contoso.sharepoint.com/sites/PRJ-001-Example-Project'; Skipped = $false; Mocked = $true; Error = $null }
        }
        Mock -CommandName New-NsgTeam -ModuleName ProvisioningEngine -MockWith {
            [PSCustomObject]@{ Success = $true; TeamId = 'mock-team-prj001'; DisplayName = 'PRJ-001 Example Project'; Skipped = $false; Mocked = $true; Error = $null }
        }
        Mock -CommandName Add-NsgDefaultChannels -ModuleName ProvisioningEngine -MockWith {
            [PSCustomObject]@{ Success = $true; Created = @('Project Management', 'Documentation'); Skipped = @('General'); Errors = @() }
        }

        $result = Invoke-NsgProjectProvisioning -Project $script:TestProject -Configuration $script:TestConfig

        $result.Success | Should -BeTrue
        ($result.Steps | Where-Object { $_.Name -eq 'Default channels' }).Success | Should -BeTrue
    }

    It 'still attempts Team creation when SharePoint site creation fails, and reports partial failure' {
        Mock -CommandName New-NsgSharePointSite -ModuleName ProvisioningEngine -MockWith {
            [PSCustomObject]@{ Success = $false; SiteUrl = 'https://contoso.sharepoint.com/sites/PRJ-001-Example-Project'; Skipped = $false; Mocked = $false; Error = 'Simulated site failure' }
        }
        Mock -CommandName New-NsgTeam -ModuleName ProvisioningEngine -MockWith {
            [PSCustomObject]@{ Success = $true; TeamId = 'mock-team-prj001'; DisplayName = 'PRJ-001 Example Project'; Skipped = $false; Mocked = $true; Error = $null }
        }
        Mock -CommandName Add-NsgDefaultChannels -ModuleName ProvisioningEngine -MockWith {
            [PSCustomObject]@{ Success = $true; Created = @('Project Management', 'Documentation'); Skipped = @('General'); Errors = @() }
        }

        $result = Invoke-NsgProjectProvisioning -Project $script:TestProject -Configuration $script:TestConfig

        $result.Success | Should -BeFalse
        Should -Invoke -CommandName New-NsgTeam -ModuleName ProvisioningEngine -Times 1
        Should -Invoke -CommandName Add-NsgDefaultChannels -ModuleName ProvisioningEngine -Times 1
        ($result.Steps | Where-Object { $_.Name -eq 'SharePoint site' }).Error | Should -Be 'Simulated site failure'
    }

    It 'skips channel creation when Team creation fails, without throwing' {
        Mock -CommandName New-NsgSharePointSite -ModuleName ProvisioningEngine -MockWith {
            [PSCustomObject]@{ Success = $true; SiteUrl = 'https://contoso.sharepoint.com/sites/PRJ-001-Example-Project'; Skipped = $false; Mocked = $true; Error = $null }
        }
        Mock -CommandName New-NsgTeam -ModuleName ProvisioningEngine -MockWith {
            [PSCustomObject]@{ Success = $false; TeamId = $null; DisplayName = 'PRJ-001 Example Project'; Skipped = $false; Mocked = $false; Error = 'Simulated team failure' }
        }
        Mock -CommandName Add-NsgDefaultChannels -ModuleName ProvisioningEngine

        $result = Invoke-NsgProjectProvisioning -Project $script:TestProject -Configuration $script:TestConfig
        $result.Success | Should -BeFalse
        ($result.Steps | Where-Object { $_.Name -eq 'Default channels' }).Skipped | Should -BeTrue
        Should -Invoke -CommandName Add-NsgDefaultChannels -ModuleName ProvisioningEngine -Times 0
    }

    It 'forwards -DryRun to the SharePoint and Team steps' {
        Mock -CommandName New-NsgSharePointSite -ModuleName ProvisioningEngine -MockWith {
            [PSCustomObject]@{ Success = $true; SiteUrl = 'x'; Skipped = $false; Mocked = $true; Error = $null }
        } -ParameterFilter { $DryRun -eq $true }
        Mock -CommandName New-NsgTeam -ModuleName ProvisioningEngine -MockWith {
            [PSCustomObject]@{ Success = $true; TeamId = 'x'; DisplayName = 'x'; Skipped = $false; Mocked = $true; Error = $null }
        } -ParameterFilter { $DryRun -eq $true }
        Mock -CommandName Add-NsgDefaultChannels -ModuleName ProvisioningEngine -MockWith {
            [PSCustomObject]@{ Success = $true; Created = @(); Skipped = @('General'); Errors = @() }
        } -ParameterFilter { $DryRun -eq $true }

        $result = Invoke-NsgProjectProvisioning -Project $script:TestProject -Configuration $script:TestConfig -DryRun

        $result.Success | Should -BeTrue
        Should -Invoke -CommandName New-NsgSharePointSite -ModuleName ProvisioningEngine -Times 1 -ParameterFilter { $DryRun -eq $true }
        Should -Invoke -CommandName New-NsgTeam -ModuleName ProvisioningEngine -Times 1 -ParameterFilter { $DryRun -eq $true }
    }
}
