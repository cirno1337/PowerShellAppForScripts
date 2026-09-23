BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    Import-Module (Join-Path $repoRoot 'Modules/InputProvider.psm1') -Force
}

Describe 'InputProvider' {

    Context 'Test-NsgInputValues' {

        It 'flags a missing required field' {
            $inputDefs = @([PSCustomObject]@{ name = 'Owner'; prompt = 'Owner'; required = $true })

            $errors = Test-NsgInputValues -InputDefinitions $inputDefs -Values @{}

            $errors.Count | Should -Be 1
            $errors[0] | Should -Match 'Owner'
        }

        It 'does not flag an optional field that is missing' {
            $inputDefs = @([PSCustomObject]@{ name = 'Notes'; prompt = 'Notes'; required = $false })

            $errors = Test-NsgInputValues -InputDefinitions $inputDefs -Values @{}

            $errors.Count | Should -Be 0
        }
    }

    Context 'Get-NsgScriptInputValues' {

        It 'uses preset values without prompting' {
            Mock -CommandName Read-Host -ModuleName InputProvider -MockWith { throw 'Read-Host should not be called' }

            $inputDefs = @([PSCustomObject]@{ name = 'Name'; prompt = 'Project name'; required = $true })

            $values = Get-NsgScriptInputValues -InputDefinitions $inputDefs -PresetValues @{ Name = 'Example' }

            $values['Name'] | Should -Be 'Example'
        }

        It 'returns an empty hashtable when there are no declared inputs' {
            $values = Get-NsgScriptInputValues -InputDefinitions @()

            $values.Count | Should -Be 0
        }

        It 'prompts for missing required values' {
            Mock -CommandName Read-Host -ModuleName InputProvider -MockWith { 'Prompted Value' }

            $inputDefs = @([PSCustomObject]@{ name = 'Owner'; prompt = 'Owner'; required = $true })

            $values = Get-NsgScriptInputValues -InputDefinitions $inputDefs

            $values['Owner'] | Should -Be 'Prompted Value'
        }

        It 'throws in NonInteractive mode when a required value is missing' {
            $inputDefs = @([PSCustomObject]@{ name = 'Owner'; prompt = 'Owner'; required = $true })

            { Get-NsgScriptInputValues -InputDefinitions $inputDefs -NonInteractive } | Should -Throw
        }
    }
}
