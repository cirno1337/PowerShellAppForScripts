# NSG Project Automation

PowerShell toolkit that provisions SharePoint Online project sites and their
paired Microsoft Teams (with a default channel set), plus a small,
configuration-driven TUI launcher for running this and future automations.

The prototype targets the `ecm4nsg` development tenant and runs entirely in
**Mock mode** by default, so it can be exercised end-to-end without a
certificate or real permissions. Switching to a real tenant is a
configuration change, not a code change.

## Architecture

```text
TUI (Launcher.ps1)
 |
 +-- Script Registry        (Modules/ScriptRegistry.psm1, config/scripts.json)
 |
 +-- Input Provider         (Modules/InputProvider.psm1)
 |
 +-- Script Runner          (Modules/ScriptRunner.psm1)
       |
       +-- ProjectProvisioner.ps1        <-- also runnable standalone / from another script / from an API
       |      |
       |      +-- ProjectInput.psm1        (project definition + validation)
       |      +-- Authentication.psm1      (Mock vs. Certificate, decided here only)
       |      +-- SharePoint.psm1
       |      +-- Teams.psm1
       |      +-- ProvisioningEngine.psm1  (orchestration + status/summary)
       |      +-- Logging.psm1
       |
       +-- HelloWorld.ps1
       |
       +-- Future scripts (registered in config/scripts.json)
```

**The Launcher never imports SharePoint/Teams/Authentication modules and has
no idea how provisioning works.** It only knows: read the registry, collect
declared inputs, invoke the script file. `ProjectProvisioner.ps1` has no idea
whether it was started from the TUI, another script, or a scheduled task -
it just takes a `-Project` object. This is what makes both sides independently
testable and reusable.

### Why one module for SharePoint and Teams (PnP.PowerShell only)

Teams provisioning is implemented via PnP's Graph-backed cmdlets
(`New-PnPTeamsTeam`, `Add-PnPTeamsChannel`) instead of pulling in the
separate `MicrosoftTeams` module. That keeps authentication to a single
`Connect-PnPOnline` call and a single module dependency for the whole
provisioning path. `New-PnPTeamsTeam -DisplayName ...` creates the
Microsoft 365 Group *and* teamifies it in one call (PnP handles waiting for
the new group to become available to Graph internally); the SharePoint site
is created separately as `-Type TeamSiteWithoutMicrosoft365Group` so it
doesn't spin up a second, redundant group of its own.

### Why Authentication decides Mock vs. real, not SharePoint/Teams

`SharePoint.psm1` and `Teams.psm1` always call the same functions
(`New-NsgSharePointSite`, `New-NsgTeam`, ...) and receive an `$AuthContext`
object with a `.Mode` (`Mock` or `Certificate`) from `Authentication.psm1`.
They branch on that mode to decide whether to actually call PnP cmdlets or
log a `[DEV/MOCK]` line and return a simulated result. This means going from
`ecm4nsg` development to a real certificate-backed tenant is purely a
`config/settings.json` change (`authentication.mode`) - no script is rewritten.

### Provisioning status, not silent exceptions

`Invoke-NsgProjectProvisioning` (in `ProvisioningEngine.psm1`) creates the
SharePoint site and the Team as **independent** steps - one failing does not
abort the other - and only attempts channel creation if the Team step
succeeded. It never lets an exception escape uncaught; every run ends with a
readable summary and returns a status object:

```powershell
$result.Success        # overall bool
$result.Steps           # array of { Name, Success, Skipped, Mocked, Details, Error }
```

Callers (a script, the TUI, or a future API) decide what "partial success"
means for them instead of the engine deciding for everyone.

### Registry-driven TUI

`config/scripts.json` is the only place that lists automations. Each entry
declares its own inputs:

```json
{
  "id": "some-new-script",
  "name": "Some New Automation",
  "description": "Does something useful",
  "script": "SomeNewScript.ps1",
  "parameterName": "Inputs",
  "inputs": [
    { "name": "InputA", "prompt": "Input A", "required": true }
  ]
}
```

`Launcher.ps1` renders the menu from this file and calls
`Get-NsgScriptInputValues` to collect whatever the entry declares, then
`Invoke-NsgRegisteredScript` binds the collected values to the parameter
named by `parameterName` (default `Inputs`) and runs the script. See
[Adding a new script to the TUI](#adding-a-new-script-to-the-tui).

## Installation

Requires PowerShell 7+.

```powershell
Install-Module PnP.PowerShell -Scope CurrentUser
Install-Module Pester -Scope CurrentUser -MinimumVersion 5.0
```

`PnP.PowerShell` is **only required when using `authentication.mode:
"Certificate"`**. Mock mode and all Pester tests run without it installed -
the module is imported lazily, only on the real connection path
(`Assert-NsgPnPModuleAvailable` in `Modules/Authentication.psm1`).

## Configuration

Copy the example config and edit it - the real file is git-ignored so
secrets never get committed:

```powershell
Copy-Item config/settings.example.json config/settings.json
```

| Section | Purpose |
|---|---|
| `environment` | `"Development"` or `"Production"` (informational/log context) |
| `tenant.tenantId` / `tenant.tenantName` | Entra tenant identifier |
| `sharePoint.baseUrl` | Base site collection URL, e.g. `https://ecm4nsg.sharepoint.com/sites/` |
| `sharePoint.siteUrlPattern` | Site URL suffix template, tokens `{Name}`, `{Number}`, `{Owner}` |
| `authentication.mode` | `"Mock"` or `"Certificate"` |
| `authentication.clientId` | Entra app registration (client) ID |
| `authentication.certificate.path` | Path to the `.pfx`/`.pem` certificate on disk |
| `authentication.certificate.passwordEnvironmentVariable` | Name of the env var holding the certificate password (never stored in JSON) |
| `teams.defaultChannels` | The **only** place default Teams channels are listed |
| `logging.path` | Log file path, relative to the repo root |

### Development / Mock mode

With `"authentication": { "mode": "Mock" }`, no network calls are made.
Every SharePoint/Teams operation logs what it *would* do and returns a
simulated (but clearly marked) result:

```text
[DEV/MOCK] Would create SharePoint site: https://ecm4nsg.sharepoint.com/sites/PRJ-001-Example-Project
[DEV/MOCK] Would create Team: PRJ-001 Example Project
[DEV/MOCK] Would create channel: Project Management
[DEV/MOCK] Would create channel: Documentation
```

The engine never reports a resource as created unless it genuinely was -
mocked steps are flagged `Mocked = $true` in the result so a caller can tell
the difference from a real success.

### Switching to a real certificate

1. Place the certificate on disk (not in the repo).
2. Set `authentication.mode` to `"Certificate"` in `config/settings.json`.
3. Fill in `authentication.clientId`, `tenant.tenantId`/`tenant.tenantName`,
   and `authentication.certificate.path`.
4. If the certificate is password-protected, set an environment variable
   (name of your choosing) and point
   `authentication.certificate.passwordEnvironmentVariable` at it, e.g.:

   ```powershell
   $env:NSG_CERT_PASSWORD = 'the-password'
   ```

5. Ensure `PnP.PowerShell` is installed (see Installation).

No script changes are required - `Authentication.psm1` picks up the new mode
automatically.

### Dry run

Any provisioning run can be forced into a no-op preview with `-DryRun`,
independently of `authentication.mode`:

```powershell
.\ProjectProvisioner.ps1 -Project @{ Name = 'Example'; Number = 'PRJ-001'; Owner = 'user@example.com' } -DryRun
.\Launcher.ps1 -DryRun
```

## Usage

### Interactive (TUI)

```powershell
.\Launcher.ps1
```

```text
========================================
        NSG Project Automation
========================================

1. Create SharePoint Project
2. Hello World Demo
Q. Exit
```

### Interactive (provisioner only)

```powershell
.\ProjectProvisioner.ps1
```

### Programmatic (from another script, service, or future API)

```powershell
$project = @{
    Name   = 'Example Project'
    Number = 'PRJ-001'
    Owner  = 'user@example.com'
}

$result = .\ProjectProvisioner.ps1 -Project $project

if (-not $result.Success) {
    $result.Steps | Where-Object { -not $_.Success -and -not $_.Skipped }
}
```

`ProjectProvisioner.ps1` never calls `exit` - it's designed to be dot-sourced
or invoked with the call operator (`&`) from another process without
terminating the caller. It returns a status object instead; a truly
standalone CLI wrapper can inspect `.Success` and set its own exit code if
needed.

## Adding a new script to the TUI

1. Drop the script file in the repo root (or a subfolder) with a parameter
   block accepting a single value-bag parameter, e.g.:

   ```powershell
   param(
       [hashtable]$Inputs = @{},
       [switch]$DryRun
   )
   ```

2. Add an entry to `config/scripts.json`:

   ```powershell
   $Scripts += @{
       Id = "some-new-script"
       Name = "Some New Automation"
       Description = "Does something useful"
       Script = "SomeNewScript.ps1"
       Inputs = @(
           @{ Name = "InputA"; Prompt = "Input A"; Required = $true }
       )
   }
   ```

3. That's it - `Launcher.ps1` picks it up automatically. No changes to
   `Launcher.ps1`, `ScriptRegistry.psm1` or `ScriptRunner.psm1` are needed.

If the script needs the whole input bag under a specific parameter name
(like `ProjectProvisioner.ps1` wants `-Project`), set `"parameterName"` in
the registry entry.

## Example workflow

```powershell
# One-time setup
Copy-Item config/settings.example.json config/settings.json
Install-Module PnP.PowerShell -Scope CurrentUser

# Try it safely first
.\Launcher.ps1
# > 1 (Create SharePoint Project)
# > Project name: Example Project
# > Project number: PRJ-001
# > Project owner (email): user@example.com
# ... [DEV/MOCK] lines, then a summary showing SUCCESS

# Once ecm4nsg has a certificate + app registration ready:
#   - set authentication.mode to "Certificate" in config/settings.json
#   - fill in clientId / tenant / certificate path
#   - set $env:NSG_CERT_PASSWORD if needed
.\Launcher.ps1
# same flow, now creates real resources
```

## Required Entra ID / Graph / PnP permissions

Using an app-only (certificate) registration, grant admin consent for:

| Permission | Type | Why |
|---|---|---|
| `Sites.FullControl.All` | Application | Create/configure SharePoint site collections |
| `Group.ReadWrite.All` | Application | Create the Microsoft 365 Group backing the Team |
| `Directory.ReadWrite.All` | Application | Group/owner provisioning in Entra ID |
| `User.Read.All` | Application | Resolve the owner's UPN/object ID |

Notes:

- `New-PnPTeamsTeam` (teamifying a Microsoft 365 Group) is asynchronous on
  Microsoft's side; it can take a short while before the Team is fully usable
  even after the cmdlet returns successfully.
- The "General" channel always exists on a new Team automatically - the
  provisioner intentionally skips creating it again (see `Add-NsgDefaultChannels`
  in `Modules/Teams.psm1`) to avoid a guaranteed, noisy failure.
- Least-privilege review is recommended before production use; the list
  above is what the cmdlets used here require, not necessarily the minimum
  your tenant's security policy allows.

## Testing

```powershell
Invoke-Pester -Path ./Tests
```

Tests cover: configuration loading/validation and fallback behavior, script
registry loading/validation, menu-driving input collection (interactive and
preset), project input validation, parameter binding in the script runner,
and the provisioning engine's step orchestration (independent SharePoint/Team
steps, channel creation skipped on Team failure, Mock/DryRun forwarding) -
all via Pester mocks, with **no dependency on PnP.PowerShell or network
access**.

Lint with PSScriptAnalyzer if available:

```powershell
Install-Module PSScriptAnalyzer -Scope CurrentUser
Invoke-ScriptAnalyzer -Path . -Recurse
```

> This prototype was developed in an environment without a PowerShell
> runtime available to execute `Invoke-Pester`/`Invoke-ScriptAnalyzer`
> directly. Run the commands above locally (or against `ecm4nsg`) before
> relying on this as a tested baseline, and report back anything that fails.

## Project structure

```text
PowerShellAppForScripts/
├── Launcher.ps1
├── ProjectProvisioner.ps1
├── HelloWorld.ps1
├── Modules/
│   ├── Logging.psm1
│   ├── Configuration.psm1
│   ├── Authentication.psm1
│   ├── ProjectInput.psm1
│   ├── SharePoint.psm1
│   ├── Teams.psm1
│   ├── ProvisioningEngine.psm1
│   ├── ScriptRegistry.psm1
│   ├── InputProvider.psm1
│   └── ScriptRunner.psm1
├── config/
│   ├── settings.example.json
│   ├── settings.json          (git-ignored, created locally)
│   └── scripts.json
├── Tests/
│   └── *.Tests.ps1            (Pester)
└── logs/                       (git-ignored, created at runtime)
```
