BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    Import-Module (Join-Path $repoRoot 'Modules/ProjectInput.psm1') -Force
}

Describe 'ProjectInput' {

    Context 'Test-NsgProjectDefinition' {

        It 'accepts a fully valid project' {
            $project = New-NsgProjectDefinition -Name 'Example Project' -Number 'PRJ-001' -Owner 'user@example.com'

            Test-NsgProjectDefinition -Project $project | Should -BeNullOrEmpty
        }

        It 'rejects an empty name' {
            $project = New-NsgProjectDefinition -Name '' -Number 'PRJ-001' -Owner 'user@example.com'

            $errors = Test-NsgProjectDefinition -Project $project
            $errors -join ';' | Should -Match 'name'
        }

        It 'rejects a project number with invalid characters' {
            $project = New-NsgProjectDefinition -Name 'Example' -Number 'PRJ 001!' -Owner 'user@example.com'

            $errors = Test-NsgProjectDefinition -Project $project
            $errors -join ';' | Should -Match 'invalid characters'
        }

        It 'rejects an owner that is not a valid email' {
            $project = New-NsgProjectDefinition -Name 'Example' -Number 'PRJ-001' -Owner 'not-an-email'

            $errors = Test-NsgProjectDefinition -Project $project
            $errors -join ';' | Should -Match 'valid email'
        }
    }

    Context 'ConvertTo-NsgProjectDefinition' {

        It 'normalizes a hashtable into a project definition' {
            $project = ConvertTo-NsgProjectDefinition -InputObject @{ Name = 'Example'; Number = 'PRJ-001'; Owner = 'user@example.com' }

            $project.Name | Should -Be 'Example'
            $project.Number | Should -Be 'PRJ-001'
            $project.Owner | Should -Be 'user@example.com'
        }
    }
}
