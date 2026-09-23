BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    Import-Module (Join-Path $repoRoot 'Modules/Configuration.psm1') -Force
}

Describe 'Configuration' {

    Context 'Get-NsgConfiguration' {

        It 'falls back to settings.example.json when settings.json is missing' {
            $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ([guid]::NewGuid())
            New-Item -ItemType Directory -Path (Join-Path $tempRoot 'config') -Force | Out-Null
            Copy-Item -Path (Join-Path $repoRoot 'config/settings.example.json') -Destination (Join-Path $tempRoot 'config/settings.example.json')

            $config = Get-NsgConfiguration -RepoRoot $tempRoot -WarningAction SilentlyContinue

            $config._IsExampleConfig | Should -BeTrue
            $config.authentication.mode | Should -Be 'Mock'

            Remove-Item -Path $tempRoot -Recurse -Force
        }

        It 'throws when neither settings.json nor settings.example.json exist' {
            $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ([guid]::NewGuid())
            New-Item -ItemType Directory -Path (Join-Path $tempRoot 'config') -Force | Out-Null

            { Get-NsgConfiguration -RepoRoot $tempRoot } | Should -Throw

            Remove-Item -Path $tempRoot -Recurse -Force
        }
    }

    Context 'Test-NsgConfiguration' {

        It 'requires clientId, tenant and certificate path when mode is Certificate' {
            $config = [PSCustomObject]@{
                environment    = 'Production'
                authentication = [PSCustomObject]@{ mode = 'Certificate' }
                tenant         = [PSCustomObject]@{}
                sharePoint     = [PSCustomObject]@{ baseUrl = 'https://contoso.sharepoint.com/sites/'; siteUrlPattern = '{Number}-{Name}' }
                teams          = [PSCustomObject]@{ defaultChannels = @('General') }
            }

            $errors = Test-NsgConfiguration -Configuration $config

            $errors.Count | Should -BeGreaterThan 0
            $errors -join ';' | Should -Match 'clientId'
        }

        It 'passes validation for a well-formed Mock configuration' {
            $config = [PSCustomObject]@{
                environment    = 'Development'
                authentication = [PSCustomObject]@{ mode = 'Mock' }
                tenant         = [PSCustomObject]@{}
                sharePoint     = [PSCustomObject]@{ baseUrl = 'https://contoso.sharepoint.com/sites/'; siteUrlPattern = '{Number}-{Name}' }
                teams          = [PSCustomObject]@{ defaultChannels = @('General', 'Documentation') }
            }

            $errors = Test-NsgConfiguration -Configuration $config

            $errors.Count | Should -Be 0
        }
    }

    Context 'Get-NsgSiteUrl' {

        It 'substitutes {Name} and {Number} tokens and sanitizes special characters' {
            $config = [PSCustomObject]@{
                sharePoint = [PSCustomObject]@{ baseUrl = 'https://contoso.sharepoint.com/sites/'; siteUrlPattern = '{Number}-{Name}' }
            }
            $project = [PSCustomObject]@{ Name = 'Example Project'; Number = 'PRJ-001'; Owner = 'user@example.com' }

            $url = Get-NsgSiteUrl -Configuration $config -Project $project

            $url | Should -Be 'https://contoso.sharepoint.com/sites/PRJ-001-Example-Project'
        }
    }

    Context 'Resolve-NsgCertificatePassword' {

        It 'returns $null when no environment variable is configured' {
            $config = [PSCustomObject]@{ authentication = [PSCustomObject]@{ certificate = [PSCustomObject]@{} } }

            Resolve-NsgCertificatePassword -Configuration $config | Should -BeNullOrEmpty
        }

        It 'reads the password from the configured environment variable' {
            $envVarName = 'NSG_TEST_CERT_PASSWORD_' + [guid]::NewGuid().ToString('N')
            [System.Environment]::SetEnvironmentVariable($envVarName, 'super-secret')

            $config = [PSCustomObject]@{ authentication = [PSCustomObject]@{ certificate = [PSCustomObject]@{ passwordEnvironmentVariable = $envVarName } } }

            Resolve-NsgCertificatePassword -Configuration $config | Should -Be 'super-secret'

            [System.Environment]::SetEnvironmentVariable($envVarName, $null)
        }
    }
}
