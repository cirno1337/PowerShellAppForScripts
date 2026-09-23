BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    Import-Module (Join-Path $repoRoot 'Modules/ScriptRegistry.psm1') -Force
}

Describe 'ScriptRegistry' {

    Context 'Get-NsgScriptRegistry' {

        It 'loads the real config/scripts.json shipped with the project' {
            $registry = Get-NsgScriptRegistry -Path (Join-Path $repoRoot 'config/scripts.json')

            $registry.Count | Should -Be 2
            ($registry | Where-Object { $_.id -eq 'project-provisioning' }) | Should -Not -BeNullOrEmpty
            ($registry | Where-Object { $_.id -eq 'hello-world' }) | Should -Not -BeNullOrEmpty
        }

        It 'throws when the file does not exist' {
            { Get-NsgScriptRegistry -Path (Join-Path $TestDrive 'missing.json') } | Should -Throw
        }

        It 'throws when an entry is missing required fields' {
            $path = Join-Path $TestDrive 'bad-scripts.json'
            @{ scripts = @(@{ id = 'no-script-field'; name = 'Broken' }) } | ConvertTo-Json | Set-Content -Path $path

            { Get-NsgScriptRegistry -Path $path } | Should -Throw '*script*'
        }

        It 'throws when two entries share the same id' {
            $path = Join-Path $TestDrive 'dup-scripts.json'
            @{
                scripts = @(
                    @{ id = 'dup'; name = 'One'; script = 'a.ps1' },
                    @{ id = 'dup'; name = 'Two'; script = 'b.ps1' }
                )
            } | ConvertTo-Json | Set-Content -Path $path

            { Get-NsgScriptRegistry -Path $path } | Should -Throw '*duplicate*'
        }
    }

    Context 'Get-NsgScriptDefinition' {

        It 'returns the matching entry by id' {
            $registry = Get-NsgScriptRegistry -Path (Join-Path $repoRoot 'config/scripts.json')

            $definition = Get-NsgScriptDefinition -Registry $registry -Id 'hello-world'

            $definition.script | Should -Be 'HelloWorld.ps1'
        }

        It 'returns $null for an unknown id' {
            $registry = Get-NsgScriptRegistry -Path (Join-Path $repoRoot 'config/scripts.json')

            Get-NsgScriptDefinition -Registry $registry -Id 'does-not-exist' | Should -BeNullOrEmpty
        }
    }
}
