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
    sc.exe create "Unified Scheduler Service" binpath="%~dp0UScheduler.exe
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
        [string]$CurrentDateTime
    )

    if($CurrentDateTime) {
        [datetime]$CurrentDateTime = [datetime]::parseexact($CurrentDateTime, 'dd/MM/yyyy HH:mm:ss', $null)
    }

    Write-Host "Automated: $Automated" -ForegroundColor Green
    Write-Host "CurrentDateTime: $CurrentDateTime" -ForegroundColor Green
```

Thanks to that, it's possible to create standalone scripts or automated scheduled scripts, which will be executed according to the script managed schedule logic.

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