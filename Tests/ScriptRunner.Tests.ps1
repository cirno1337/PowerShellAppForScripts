BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    Import-Module (Join-Path $repoRoot 'Modules/ScriptRunner.psm1') -Force
}

Describe 'ScriptRunner' {

    Context 'Invoke-NsgRegisteredScript' {

        It 'binds input values to the parameter name declared by the registry entry' {
            Mock -CommandName Invoke-NsgScriptFile -ModuleName ScriptRunner -MockWith { $Parameters }

            $definition = [PSCustomObject]@{ id = 'project-provisioning'; script = 'HelloWorld.ps1'; parameterName = 'Project' }
            $values = @{ Name = 'Example'; Number = 'PRJ-001'; Owner = 'user@example.com' }

            Invoke-NsgRegisteredScript -ScriptDefinition $definition -Values $values -RootPath $repoRoot

            Should -Invoke -CommandName Invoke-NsgScriptFile -ModuleName ScriptRunner -Times 1 -ParameterFilter {
                $Parameters.ContainsKey('Project') -and $Parameters['Project']['Name'] -eq 'Example'
            }
        }

        It 'defaults the parameter name to Inputs when none is declared' {
            Mock -CommandName Invoke-NsgScriptFile -ModuleName ScriptRunner -MockWith { $Parameters }

            $definition = [PSCustomObject]@{ id = 'hello-world'; script = 'HelloWorld.ps1' }

            Invoke-NsgRegisteredScript -ScriptDefinition $definition -Values @{} -RootPath $repoRoot

            Should -Invoke -CommandName Invoke-NsgScriptFile -ModuleName ScriptRunner -Times 1 -ParameterFilter {
                $Parameters.ContainsKey('Inputs')
            }
        }

        It 'adds -DryRun to the parameters when requested' {
            Mock -CommandName Invoke-NsgScriptFile -ModuleName ScriptRunner -MockWith { $Parameters }

            $definition = [PSCustomObject]@{ id = 'hello-world'; script = 'HelloWorld.ps1' }

            Invoke-NsgRegisteredScript -ScriptDefinition $definition -Values @{} -RootPath $repoRoot -DryRun

            Should -Invoke -CommandName Invoke-NsgScriptFile -ModuleName ScriptRunner -Times 1 -ParameterFilter {
                $Parameters.ContainsKey('DryRun') -and $Parameters['DryRun'] -eq $true
            }
        }

        It 'throws when the script file does not exist' {
            $definition = [PSCustomObject]@{ id = 'missing'; script = 'DoesNotExist.ps1' }

            { Invoke-NsgRegisteredScript -ScriptDefinition $definition -Values @{} -RootPath $repoRoot } | Should -Throw
        }
    }
}
