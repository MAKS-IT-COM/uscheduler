

# MaksIT Unified Scheduler Service

A modern, fully rewritten Windows service built on **.NET 10** for scheduling and running PowerShell scripts and console applications.
Designed for system administrators — and also for those who *feel like* system administrators — who need a predictable, resilient, and secure background execution environment.

---

## Table of Contents

- [MaksIT Unified Scheduler Service](#maksit-unified-scheduler-service)
  - [Table of Contents](#table-of-contents)
  - [Features at a Glance](#features-at-a-glance)
  - [Installation](#installation)
    - [Recommended (using bundled scripts)](#recommended-using-bundled-scripts)
    - [Manual Installation](#manual-installation)
  - [Configuration (`appsettings.json`)](#configuration-appsettingsjson)
    - [PowerShell Scripts](#powershell-scripts)
    - [Processes](#processes)
  - [How It Works](#how-it-works)
    - [PowerShell Execution Parameters](#powershell-execution-parameters)
    - [Thread Layout](#thread-layout)
  - [Reusable Scheduler Module (`SchedulerTemplate.psm1`)](#reusable-scheduler-module-schedulertemplatepsm1)
    - [Example usage](#example-usage)
  - [Security](#security)
  - [Logging](#logging)
  - [Contact](#contact)
  - [License](#license)
- [Appendix](#appendix)
  - [SchedulerTemplate.psm1 (Full Source)](#schedulertemplatepsm1-full-source)

---

## Features at a Glance

* **.NET 10 Worker Service** – clean, robust, stable.
* **Strongly typed configuration** via `appsettings.json`.
* **Run PowerShell scripts & executables concurrently** (each in its own thread).
* **Signature enforcement** (AllSigned by default).
* **Automatic restart-on-failure** for supervised processes.
* **Extensible logging** (file + console).
* **Simple Install.cmd / Uninstall.cmd**.
* **Reusable scheduling module**: `SchedulerTemplate.psm1`.
* **Thread-isolated architecture** — individual failures do not affect others.

---

## Installation

### Recommended (using bundled scripts)

```bat
cd /d path\to\src\MaksIT.UScheduler
Install.cmd
```

To uninstall:

```bat
Uninstall.cmd
```

### Manual Installation

```powershell
sc.exe create "MaksIT.UScheduler Service" binpath="C:\Path\To\MaksIT.UScheduler.exe"
sc.exe start "MaksIT.UScheduler Service"
```

Manual uninstall:

```powershell
sc.exe delete "MaksIT.UScheduler Service"
```

---

## Configuration (`appsettings.json`)

```json
{
  "Configuration": {
    "ServiceName": "MaksIT.UScheduler",
    "LogDir": "C:\\Logs",

    "Powershell": [
      { "Path": "C:\\Scripts\\MyScript.ps1", "IsSigned": true }
    ],

    "Processes": [
      { "Path": "C:\\Programs\\MyApp.exe", "Args": ["--option"], "RestartOnFailure": true }
    ]
  }
}
```

### PowerShell Scripts

* `Path` — full `.ps1` file path
* `IsSigned` — `true` enforces AllSigned, `false` runs unrestricted

### Processes

* `Path` — executable
* `Args` — command-line arguments
* `RestartOnFailure` — restart logic handled by service

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

### Thread Layout

```
Unified Scheduler Service
├── PowerShell
│   ├── ScriptA.ps1     Thread
│   ├── ScriptB.ps1     Thread
│   └── ...
└── Processes
    ├── ProgramA.exe     Thread
    ├── ProgramB.exe     Thread
    └── ...
```

A crash in one thread **never stops the service** or other components.

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
* Logging helpers (Write-Log)

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

* Signed scripts required by default.
* Scripts are auto-unblocked before execution.
* Unrestricted execution can be enabled if needed (not recommended on production systems).

---

## Logging

* Console logging
* File logging under the directory specified by `LogDir`
* All events (start, stop, crash, restart, error, skip) are logged

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

# Appendix

## SchedulerTemplate.psm1 (Full Source)

```powershell
# ======================================================================
# SchedulerTemplate.psm1 - Scheduling + Lock + Interval + Callback Runner
# ======================================================================

function Write-Log {
    param(
        [string]$Message,
        [switch]$Automated,
        [string]$Color = 'White'
    )

    if ($Automated) {
        Write-Output $Message
    }
    else {
        Write-Host $Message -ForegroundColor $Color
    }
}

function Get-CurrentUtcDateTime {
    param([string]$ExternalDateTime, [switch]$Automated)

    if ($ExternalDateTime) {
        try {
            return [datetime]::Parse($ExternalDateTime).ToUniversalTime()
        }
        catch {
            try {
                return [datetime]::ParseExact($ExternalDateTime, 'dd/MM/yyyy HH:mm:ss', $null).ToUniversalTime()
            }
            catch {
                Write-Log "Failed to parse CurrentDateTimeUtc ('$ExternalDateTime'). Using system time (UTC)." -Automated:$Automated -Color 'Red'
                return (Get-Date).ToUniversalTime()
            }
        }
    }
    return (Get-Date).ToUniversalTime()
}

function Test-ScheduleMonth { param([datetime]$DateTime, [array]$Months)
    $name = $DateTime.ToString('MMMM')
    return ($Months.Count -eq 0) -or ($Months -contains $name)
}
function Test-ScheduleWeekday { param([datetime]$DateTime, [array]$Weekdays)
    $name = $DateTime.DayOfWeek.ToString()
    return ($Weekdays.Count -eq 0) -or ($Weekdays -contains $name)
}
function Test-ScheduleTime { param([datetime]$DateTime, [array]$Times)
    $t = $DateTime.ToString('HH:mm')
    return ($Times.Count -eq 0) -or ($Times -contains $t)
}

function Test-Schedule {
    param(
        [datetime]$DateTime,
        [array]$RunMonth,
        [array]$RunWeekday,
        [array]$RunTime
    )

    return (Test-ScheduleMonth -DateTime $DateTime -Months $RunMonth) -and
           (Test-ScheduleWeekday -DateTime $DateTime -Weekdays $RunWeekday) -and
           (Test-ScheduleTime -DateTime $DateTime -Times $RunTime)
}

function Test-Interval {
    param([datetime]$LastRun,[datetime]$Now,[int]$MinIntervalMinutes)
    return $Now -ge $LastRun.AddMinutes($MinIntervalMinutes)
}

function Test-ScheduledExecution {
    param(
        [switch]$Automated,
        [string]$CurrentDateTimeUtc,
        [hashtable]$Config,
        [string]$LastRunFilePath
    )

    $now = Get-CurrentUtcDateTime -ExternalDateTime $CurrentDateTimeUtc -Automated:$Automated
    $shouldRun = $true

    if ($Automated) {
        Write-Log "Automated: $Automated" -Automated:$Automated -Color 'Green'
        Write-Log "Current UTC Time: $now" -Automated:$Automated -Color 'Green'

        if (-not (Test-Schedule -DateTime $now -RunMonth $Config.RunMonth -RunWeekday $Config.RunWeekday -RunTime $Config.RunTime)) {
            Write-Log "Execution skipped due to schedule." -Automated:$Automated -Color 'Yellow'
            $shouldRun = $false
        }
    }

    if ($shouldRun -and $LastRunFilePath -and (Test-Path $LastRunFilePath)) {
        $lastRun = Get-Content $LastRunFilePath | Select-Object -First 1
        if ($lastRun) {
            [datetime]$lr = $lastRun
            if (-not (Test-Interval -LastRun $lr -Now $now -MinIntervalMinutes $Config.MinIntervalMinutes)) {
                Write-Log "Last run at $lr. Interval not reached." -Automated:$Automated -Color 'Yellow'
                $shouldRun = $false
            }
        }
    }

    return @{
        ShouldExecute = $shouldRun
        Now = $now
    }
}

function New-LockGuard {
    param([string]$LockFile,[switch]$Automated)

    if (Test-Path $LockFile) {
        Write-Log "Guard: Lock file exists ($LockFile). Skipping." -Automated:$Automated -Color 'Red'
        return $false
    }
    try {
        New-Item -Path $LockFile -ItemType File -Force | Out-Null
        return $true
    }
    catch {
        Write-Log "Guard: Cannot create lock file ($LockFile)." -Automated:$Automated -Color 'Red'
        return $false
    }
}

function Remove-LockGuard {
    param([string]$LockFile,[switch]$Automated)
    if (Test-Path $LockFile) {
        Remove-Item $LockFile -Force
        Write-Log "Lock removed: $LockFile" -Automated:$Automated -Color 'Cyan'
    }
}

# ======================================================================
# Main unified executor (callback-based)
# ======================================================================
function Invoke-ScheduledExecution {
    param(
        [scriptblock]$ScriptBlock,
        [hashtable]$Config,
        [switch]$Automated,
        [string]$CurrentDateTimeUtc
    )

    $scriptPath  = $MyInvocation.ScriptName
    $lastRunFile = [IO.Path]::ChangeExtension($scriptPath, ".lastRun")
    $lockFile    = [IO.Path]::ChangeExtension($scriptPath, ".lock")

    # Check schedule
    $schedule = Test-ScheduledExecution -Automated:$Automated -CurrentDateTimeUtc $CurrentDateTimeUtc -Config $Config -LastRunFilePath $lastRunFile
    if (-not $schedule.ShouldExecute) {
        Write-Log "Execution skipped." -Automated:$Automated -Color 'Yellow'
        return
    }

    # Lock
    if (-not (New-LockGuard -LockFile $lockFile -Automated:$Automated)) {
        return
    }

    try {
        $schedule.Now.ToString("o") | Set-Content $lastRunFile
        & $ScriptBlock
    }
    finally {
        Remove-LockGuard -LockFile $lockFile -Automated:$Automated
    }
}

Export-ModuleMember -Function * -Alias *
```
