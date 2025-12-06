# Unified Scheduler Service

Is'a completelly rewritten in .NET8 version of **PowerShell Scrip Service** realized in .Net Framework 4.8

As previously, this project still has an aim to allow **System Administrators** and also to who **Thinks to be System Administrator** to launch **Power Shell** scripts and **Console Programs** as **Windows Service**.

## Latest builds

## How to Install and Uninstall Service

### Service Install

```powershell
sc.exe create "Unified Scheduler Service" binpath="C:\Path\To\UScheduler.exe"
```

with providing custom `contentRoot`:

```powershell
sc.exe create "Unified Scheduler Service" binpath="C:\Path\To\UScheduler.exe --contentRoot C:\Other\Path"
```

Edit `appsettings.json`` according your needs. Differently from previuos version it doesn't scans a folders for scripts and same for programs, but you have explicitly set what should be launched. Also, when changes are made, you have to restart service. This will improve security of your environment.

Then **start** your **Unified Scheduler Service**

I have also prepared ***.cmd** file to simplify service system integration:

Install.cmd

```bat
sc.exe create "Unified Scheduler Service" binpath="%~dp0UScheduler.exe"
pause
```

>These ***.cmd** files have to be launched with **Admin** privileges.

After installation you have to start your newly created windows service: Win+R -> services.msc -> Enter -> Search by DisplayName.

### Service Uninstall

```powershell
sc.exe "Unified Scheduler Service"
```

Uninstall.cmd

```bat
sc.exe "Unified Scheduler Service"
pause
```

## How it works

Here is a short explanation of two functional parts currently available.

### Processes

> Warning: For the moment I haven't realized any scheduling functionality for `console applications`, so be carefull, if your program is not a service kind, like `node derver`, `syncthing` ecc... it will execute it continuously every 10 senconds after completes.

This functionality is aimed to execute `console app services` which do not provide any windows service integration, and keeps it always alive.

### Powershell

Executes scripts whith following command parameters every 10 seconds:

```C#
    myCommand.Parameters.Add(new CommandParameter("Automated", true));
    myCommand.Parameters.Add(new CommandParameter("CurrentDateTimeUtc", DateTime.UtcNow.ToString("o")));
```

Retrieve parameters this way:

```PowerShell
[CmdletBinding()]
param (
    [switch]$Automated,
    [string]$CurrentDateTimeUtc
)

# ======================================================================
# CONFIGURATION BLOCK (only modify values here)
# ======================================================================
$Config = @{
    RunMonth          = @()            # e.g. @("January","December")
    RunWeekday        = @()            # e.g. @("Monday","Friday")
    RunTime           = @("20:28")     # UTC times HH:mm
    MinIntervalMinutes = 10
}
# ======================================================================


# ======================================================================
# LOGGING
# ======================================================================
function Write-Log {
    param(
        [string]$Message,
        [string]$Color = 'White'
    )

    if ($Automated) {
        Write-Output $Message
    }
    else {
        Write-Host $Message -ForegroundColor $Color
    }
}


# ======================================================================
# TIME PARSING AND SCHEDULING HELPERS
# ======================================================================
function Get-CurrentUtcDateTime {
    param([string]$ExternalDateTime)

    if ($ExternalDateTime) {
        try {
            return [datetime]::Parse($ExternalDateTime).ToUniversalTime()
        }
        catch {
            try {
                return [datetime]::ParseExact($ExternalDateTime, 'dd/MM/yyyy HH:mm:ss', $null).ToUniversalTime()
            }
            catch {
                Write-Log "Failed to parse CurrentDateTimeUtc ('$ExternalDateTime'). Using system time (UTC) instead." 'Red'
                return (Get-Date).ToUniversalTime()
            }
        }
    }
    else {
        return (Get-Date).ToUniversalTime()
    }
}

function Test-ScheduleMonth {
    param([datetime]$DateTime, [array]$Months)
    $monthName = $DateTime.ToString('MMMM')
    return ($Months.Count -eq 0) -or ($Months -contains $monthName)
}

function Test-ScheduleWeekday {
    param([datetime]$DateTime, [array]$Weekdays)
    $weekdayName = $DateTime.DayOfWeek.ToString()
    return ($Weekdays.Count -eq 0) -or ($Weekdays -contains $weekdayName)
}

function Test-ScheduleTime {
    param([datetime]$DateTime, [array]$Times)
    $timeString = $DateTime.ToString('HH:mm')
    return ($Times.Count -eq 0) -or ($Times -contains $timeString)
}

function Test-Schedule {
    param(
        [datetime]$DateTime,
        [array]$Months,
        [array]$Weekdays,
        [array]$Times
    )
    return (Test-ScheduleMonth -DateTime $DateTime -Months $Months) -and
           (Test-ScheduleWeekday -DateTime $DateTime -Weekdays $Weekdays) -and
           (Test-ScheduleTime -DateTime $DateTime -Times $Times)
}

function Test-Interval {
    param([datetime]$LastRun, [datetime]$Now, [int]$MinIntervalMinutes)
    return $Now -ge $LastRun.AddMinutes($MinIntervalMinutes)
}


# ======================================================================
# MAIN SCHEDULING CHECK
# ======================================================================
function Test-ShouldExecute {
    param(
        [switch]$Automated,
        [string]$CurrentDateTimeUtc,
        [hashtable]$Config,
        [string]$LastRunFilePath
    )

    $result = @{
        ShouldExecute = $true
        Now           = $null
    }

    $now = Get-CurrentUtcDateTime -ExternalDateTime $CurrentDateTimeUtc
    $result.Now = $now

    if ($Automated) {
        Write-Log "Automated: $Automated" 'Green'
        Write-Log "Current UTC Time used: $now" 'Green'

        if (-not (Test-Schedule -DateTime $now -Months $Config.RunMonth -Weekdays $Config.RunWeekday -Times $Config.RunTime)) {
            Write-Log "Execution skipped due to schedule (Month: $($Config.RunMonth), Weekday: $($Config.RunWeekday), Time: $($Config.RunTime))" 'Yellow'
            $result.ShouldExecute = $false
            return $result
        }
    }

    if ($LastRunFilePath -and (Test-Path $LastRunFilePath)) {
        $lastRun = Get-Content $LastRunFilePath | Select-Object -First 1
        if ($lastRun) {
            [datetime]$lastRunDT = [datetime]::Parse($lastRun)
            if (-not (Test-Interval -LastRun $lastRunDT -Now $now -MinIntervalMinutes $Config.MinIntervalMinutes)) {
                Write-Log "Last run at $lastRunDT. Interval not reached." 'Yellow'
                $result.ShouldExecute = $false
            }
        }
    }

    return $result
}


# ======================================================================
# LOCK FILE HANDLING
# ======================================================================
function New-LockGuard {
    param([string]$LockFile)

    if (Test-Path $LockFile) {
        Write-Log "Guard: Existing lock file ($LockFile). Skipping execution." 'Red'
        return $false
    }

    try {
        New-Item -Path $LockFile -ItemType File -Force | Out-Null
        return $true
    }
    catch {
        Write-Log "Guard: Failed to create lock file ($LockFile). Skipping." 'Red'
        return $false
    }
}

function Remove-LockGuard {
    param([string]$LockFile)
    if (Test-Path $LockFile) {
        Remove-Item $LockFile -Force
        Write-Log "Lock file removed: $LockFile" 'Cyan'
    }
}


# ======================================================================
# BUSINESS LOGIC PLACEHOLDER
# ======================================================================
function Run-BusinessLogic {
    # Put your actual logic here
    Write-Log "Executing business logic..." 'Green'

    # ...
    # ...
}


# ======================================================================
# MAIN EXECUTION FLOW
# ======================================================================
$scriptPath   = $MyInvocation.MyCommand.Path
$lastRunFile  = [System.IO.Path]::ChangeExtension($scriptPath, ".lastRun")
$lockFile     = [System.IO.Path]::ChangeExtension($scriptPath, ".lock")

$schedule = Test-ShouldExecute -Automated:$Automated -CurrentDateTimeUtc $CurrentDateTimeUtc -Config $Config -LastRunFilePath $lastRunFile

if (-not $schedule.ShouldExecute) {
    Write-Log "Execution skipped." 'Yellow'
    return
}

if (-not (New-LockGuard -LockFile $lockFile)) {
    return
}

try {
    $schedule.Now.ToString("o") | Set-Content $lastRunFile
    Run-BusinessLogic
}
finally {
    Remove-LockGuard -LockFile $lockFile
}
```

Thanks to that, it's possible to create standalone scripts or automated scheduled scripts, which will be executed according to the script managed schedule logic.

For every new scheduled script:
* Copy the template.
* Modify only the Config block and Run-BusinessLogic.
* Leave everything else untouched.

Done — all scheduling, locking, and logging works automatically.

### Thread organization

Every script and program is launched in its **own thread**, so if one crashes, others are able to continue:

```
    Unified Scheduler Service Thread
    ├── Powershell
    │   ├── /Scripts/SomeStuff_1/StartScript.ps1 Thread
    │   ├── /Scripts/SomeStuff_2/StartScript.ps1 Thread
    │   └── ...
    └── Processes
        ├── /Programs/SomeStuff_1/Program.exe
        ├── /Programs/SomeStuff_2/Program.exe
        └── ...
```

> By default It's set to execute only **signed** scrips, but if you don't care about your environment security, it's possible to launch them in **unrestricted** mode.
>
> Continue to read to see other possible settings...

## Configurations

Here are all currently available configurations inside `appsettings.json`:

```json
{
  //...

  "Configurations": {
    "ServiceName": "UScheduler",
    "Description": "Windows service, which allows you to invoke PowerShell Scripts and Processes",
    "DisplayName": "Unified Scheduler Service",

    "Powershell": [
      {
        "Path": "C:\\UScheduler\\Scripts\\Demo\\StartScript.ps1",
        "Signed": true
      }
    ],

    "Processes": [
      {
        "Path": "C:\\UScheduler\\Programs\\syncthing-windows-amd64-v1.27.1\\syncthing.exe",
        "Args": [],
        "RestartOnFailure": true
      }
    ]
  }
}
```

Let's see each one:

* ServiceName - System service name. I suggest to use short names without spaces or other strange characters. See [What are valid characters in a Windows service (key) name?](https://stackoverflow.com/questions/801280/what-are-valid-characters-in-a-windows-service-key-name).
* Description - Description you wants to give to this service. Just put something very serious and technically complex to admire what kind of DUDE you are!
* DisplayName - Same thing like for ServiceName, but you are free to use spaces.
* Powershell:
  * ScriptsPath - Specify script to launch.
  * SignedScripts - **true** for **AllSigned** or **false** for **Unrestricted**.
* Processes:
  * Path - Specify program to launch.
  * Args - Program command line arguments
  * RestartOnFailure - Allows to restart if something went wrong with program.