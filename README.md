# MaksIT Unified Scheduler Service

![Line Coverage](badges/coverage-lines.svg) ![Branch Coverage](badges/coverage-branches.svg) ![Method Coverage](badges/coverage-methods.svg)

A modern, fully rewritten Windows service built on **.NET 10** for scheduling and running PowerShell scripts and console applications.
Designed for system administrators — and also for those who *feel like* system administrators — who need a predictable, resilient, and secure background execution environment.

---

## Table of Contents

- [MaksIT Unified Scheduler Service](#maksit-unified-scheduler-service)
  - [Table of Contents](#table-of-contents)
  - [Scripts Examples](#scripts-examples)
  - [Features at a Glance](#features-at-a-glance)
  - [Installation](#installation)
    - [Using CLI Commands](#using-cli-commands)
    - [Using sc.exe](#using-scexe)
  - [Configuration (`appsettings.json`)](#configuration-appsettingsjson)
    - [Path Resolution](#path-resolution)
    - [Log Levels](#log-levels)
    - [PowerShell Scripts](#powershell-scripts)
    - [Processes](#processes)
  - [How It Works](#how-it-works)
    - [PowerShell Execution Parameters](#powershell-execution-parameters)
    - [Execution Model](#execution-model)
  - [Reusable Scheduler Module (`SchedulerTemplate.psm1`)](#reusable-scheduler-module-schedulertemplatepsm1)
    - [Exported Functions](#exported-functions)
    - [Module Version](#module-version)
    - [Example usage](#example-usage)
  - [Security](#security)
  - [Logging](#logging)
  - [Testing](#testing)
    - [Running Tests](#running-tests)
    - [Code Coverage](#code-coverage)
    - [Test Structure](#test-structure)
  - [Contact](#contact)
  - [License](#license)

## Scripts Examples

> **Note:** These examples are **bundled with the release** and included in the default `appsettings.json`, but are **disabled by default**. To enable an example, set `"Disabled": false` in the configuration.

- [Hyper-V Backup](./src/Scripts/HyperV-Backup/README.md) - Production-ready Hyper-V VM backup solution with scheduling and retention management
- [Native-Sync](./src/Scripts/Native-Sync/README.md) - Production-ready file synchronization solution using pure PowerShell with no external dependencies
- [File-Sync](./src/Scripts/File-Sync/README.md) - [FreeFileSync](https://freefilesync.org/) batch job execution
- [Windows-Update](./src/Scripts/Windows-Update/README.md) - Production-ready Windows Update automation solution using pure PowerShell
- [Scheduler Template Module](./src/Scripts/SchedulerTemplate.psm1)

---

## Features at a Glance

* **.NET 10 Worker Service** – clean, robust, stable.
* **Windows only** – designed specifically for Windows services.
* **Strongly typed configuration** via `appsettings.json`.
* **Parallel execution** – PowerShell scripts & executables run concurrently using RunspacePool and Task.WhenAll.
* **Relative path support** – script and process paths can be relative to the application directory.
* **Signature enforcement** (AllSigned by default).
* **Automatic restart-on-failure** for supervised processes.
* **Extensible logging** (file + console + Windows EventLog).
* **Built-in CLI** for service management (`--install`, `--uninstall`, `--start`, `--stop`, `--status`).
* **Reusable scheduling module**: `SchedulerTemplate.psm1`.
* **Thread-isolated architecture** — individual failures do not affect others.

---

## Installation

### Using CLI Commands

The executable includes built-in service management commands. Run as Administrator:

```powershell
# Install the service (auto-start enabled)
MaksIT.UScheduler.exe --install

# Start the service
MaksIT.UScheduler.exe --start

# Check service status
MaksIT.UScheduler.exe --status

# Stop the service
MaksIT.UScheduler.exe --stop

# Uninstall the service
MaksIT.UScheduler.exe --uninstall

# Show help
MaksIT.UScheduler.exe --help
```

| Command | Short | Description |
|---------|-------|-------------|
| `--install` | `-i` | Install the Windows service (auto-start) |
| `--uninstall` | `-u` | Stop and remove the Windows service |
| `--start` | | Start the service |
| `--stop` | | Stop the service |
| `--status` | | Query service status |
| `--help` | `-h` | Show help message |

> **Note:** Service management commands require administrator privileges.

### Using sc.exe

Alternatively, use Windows Service Control Manager directly:

```powershell
sc.exe create "MaksIT.UScheduler" binpath="C:\Path\To\MaksIT.UScheduler.exe" start=auto
sc.exe start "MaksIT.UScheduler"
```

To uninstall:

```powershell
sc.exe stop "MaksIT.UScheduler"
sc.exe delete "MaksIT.UScheduler"
```

---

## Configuration (`appsettings.json`)

```json
{
  "Logging": {
    "LogLevel": {
      "Default": "Information"
    },
    "EventLog": {
      "SourceName": "MaksIT.UScheduler",
      "LogName": "Application",
      "LogLevel": {
        "Microsoft": "Information",
        "Microsoft.Hosting.Lifetime": "Information"
      }
    }
  },
  "Configuration": {
    "ServiceName": "MaksIT.UScheduler",
    "LogDir": "C:\\Logs",

    "Powershell": [
      { "Path": "../Scripts/MyScript.ps1", "IsSigned": true, "Disabled": false },
      { "Path": "C:\\Scripts\\AnotherScript.ps1", "IsSigned": false, "Disabled": true }
    ],

    "Processes": [
      { "Path": "../Tools/MyApp.exe", "Args": ["--option"], "RestartOnFailure": true, "Disabled": false }
    ]
  }
}
```

> **Note:** `ServiceName` and `LogDir` are optional. Defaults: `"MaksIT.UScheduler"` and `Logs` folder in app directory.

### Path Resolution

Paths can be either absolute or relative:

| Path Type | Example | Resolved To |
|-----------|---------|-------------|
| Absolute | `C:\Scripts\backup.ps1` | `C:\Scripts\backup.ps1` |
| Relative | `../Scripts/backup.ps1` | `{AppDirectory}\..\Scripts\backup.ps1` |
| Relative | `scripts/backup.ps1` | `{AppDirectory}\scripts\backup.ps1` |

Relative paths are resolved against the application's base directory (where `MaksIT.UScheduler.exe` is located).

### Log Levels

The `"Default": "Information"` setting controls the minimum severity of messages that get logged. Available levels (from most to least verbose):

| Level | Description |
|-------|-------------|
| `Trace` | Most detailed, for debugging internals |
| `Debug` | Debugging information |
| `Information` | General operational events (recommended default) |
| `Warning` | Abnormal or unexpected events |
| `Error` | Errors and exceptions |
| `Critical` | Critical failures requiring immediate attention |
| `None` | Disables logging |

### PowerShell Scripts

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `Path` | string | required | Path to `.ps1` file (absolute or relative) |
| `IsSigned` | bool | `true` | `true` enforces AllSigned, `false` runs unrestricted |
| `Disabled` | bool | `false` | `true` skips this script during execution |

### Processes

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `Path` | string | required | Path to executable (absolute or relative) |
| `Args` | string[] | `null` | Command-line arguments |
| `RestartOnFailure` | bool | `false` | Restart process if it exits with non-zero code |
| `Disabled` | bool | `false` | `true` skips this process during execution |

---

## How It Works

Each script or process is executed in its own managed thread.

### PowerShell Execution Parameters

```csharp
myCommand.Parameters.Add(new CommandParameter("Automated", true));
myCommand.Parameters.Add(new CommandParameter("CurrentDateTimeUtc", DateTime.UtcNow.ToString("o")));
```

Inside the script:

```powershell
param (
    [switch]$Automated,
    [string]$CurrentDateTimeUtc
)
```

### Execution Model

Scripts and processes run **in parallel** using:

- **PowerShell**: `RunspacePool` (up to CPU core count concurrent runspaces)
- **Processes**: `Task.WhenAll` for concurrent process execution

```
Unified Scheduler Service
├── PSScriptBackgroundService (RunspacePool)
│   ├── ScriptA.ps1     ─┐
│   ├── ScriptB.ps1     ─┼─ Parallel execution
│   └── ScriptC.ps1     ─┘
└── ProcessBackgroundService (Task.WhenAll)
    ├── ProgramA.exe    ─┐
    ├── ProgramB.exe    ─┼─ Parallel execution
    └── ProgramC.exe    ─┘
```

- A failure in one script/process **never stops the service** or other components.
- The same script/process won't run twice concurrently (protected by "already running" check).
- Execution cycle repeats every 10 seconds.

---

## Reusable Scheduler Module (`SchedulerTemplate.psm1`)

This module provides:

* Scheduling by:

  * Month
  * Weekday
  * Exact time(s)
  * Minimum interval
* Automatic lock file (no concurrent execution)
* Last-run file tracking
* Unified callback execution pattern

### Exported Functions

| Function | Description |
|----------|-------------|
| `Write-Log` | Logging with timestamp, level (Info/Success/Warning/Error), and color support |
| `Invoke-ScheduledExecution` | Main scheduler — checks schedule, manages locks, runs callback |
| `Get-CredentialFromEnvVar` | Retrieves credentials from Base64-encoded machine environment variables |
| `Test-UNCPath` | Validates whether a path is a UNC path |
| `Send-EmailNotification` | Sends SMTP email with optional SSL and credential support |

### Module Version

The module exports `$ModuleVersion` and `$ModuleDate` for version tracking.

### Example usage

```powershell
param (
    [switch]$Automated,
    [string]$CurrentDateTimeUtc
)

Import-Module "$PSScriptRoot\..\SchedulerTemplate.psm1" -Force

$Config = @{
    RunMonth = @()
    RunWeekday = @()
    RunTime = @("22:52")
    MinIntervalMinutes = 10
}

function Start-BusinessLogic {
     Write-Log "Executing business logic..." -Automated:$Automated
}

Invoke-ScheduledExecution -Config $Config -Automated:$Automated -CurrentDateTimeUtc $CurrentDateTimeUtc -ScriptBlock {
    Start-BusinessLogic
}
```

**Workflow for new scheduled scripts:**

1. Copy template
2. Modify `$Config`
3. Implement `Start-BusinessLogic`
4. Add script to `appsettings.json`

That’s it — the full scheduling engine is reused automatically.

---

## Security

* Scripts run with **AllSigned** execution policy by default.
* Set `IsSigned: false` to use **Unrestricted** policy (not recommended for production).
* Scripts are auto-unblocked before execution (Zone.Identifier removed).
* Signature validation ensures only trusted scripts execute.

---

## Logging

* **Console logging** — standard output
* **File logging** — written to `LogDir` (default: `Logs` folder in app directory)
* **Windows EventLog** — events logged to Application log under `MaksIT.UScheduler` source
* All events (start, stop, crash, restart, error, skip) are logged

---

## Testing

The project includes a comprehensive test suite using **xUnit** and **Moq** for unit testing.

### Running Tests

```powershell
# Run all tests
dotnet test src/MaksIT.UScheduler.Tests

# Run with verbose output
dotnet test src/MaksIT.UScheduler.Tests --verbosity normal
```

### Code Coverage

Coverage badges are generated locally using [ReportGenerator](https://github.com/danielpalme/ReportGenerator).

**Prerequisites:**

```powershell
dotnet tool install --global dotnet-reportgenerator-globaltool
```

**Generate coverage report and badges:**

```powershell
.\src\scripts\Run-Coverage\Run-Coverage.ps1

# With HTML report opened in browser
.\src\scripts\Run-Coverage\Run-Coverage.ps1 -OpenReport
```

### Test Structure

| Test Class | Coverage |
|------------|----------|
| `ConfigurationTests` | Configuration POCOs and default values |
| `ProcessBackgroundServiceTests` | Process execution lifecycle and error handling |
| `PSScriptBackgroundServiceTests` | PowerShell script execution and signature validation |

---

## Contact

Maksym Sadovnychyy – MAKS-IT, 2025
Email: maksym.sadovnychyy@gmail.com

---

## License

MIT License
Copyright (c) 2025
Maksym Sadovnychyy – MAKS-IT
maksym.sadovnychyy@gmail.com

---
