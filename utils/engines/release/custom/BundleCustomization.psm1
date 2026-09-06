#requires -Version 7.0
#requires -PSEdition Core

<#
.SYNOPSIS
    Stages Scripts and release appsettings into DotNetPublish RID folders.

.DESCRIPTION
    Does not publish. Copies src/Scripts into each MaksIT.UScheduler RID output,
    rewrites worker seed appsettings for the bundled layout, and
    writes Windows/Linux launchers. The portable zip is the win-x64 bundle folder
    A flat installer payload (worker + UI + Scripts) is staged for WiX.
#>

if (-not (Get-Command Import-PluginDependency -ErrorAction SilentlyContinue)) {
    $srcDir = Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent
    $pluginSupportModulePath = Join-Path $srcDir "modules/Engine/PluginSupport.psm1"
    if (Test-Path $pluginSupportModulePath -PathType Leaf) {
        Import-Module $pluginSupportModulePath -Force -Global -ErrorAction Stop
    }
}

function Resolve-PluginPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$BasePath
    )

    return [System.IO.Path]::GetFullPath((Join-Path $BasePath $Path))
}

function Ensure-NotePropertyInternal {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Target,

        [Parameter(Mandatory = $true)]
        [string]$PropertyName,

        [Parameter(Mandatory = $true)]
        [object]$PropertyValue
    )

    if ($Target.PSObject.Properties[$PropertyName]) {
        $Target.$PropertyName = $PropertyValue
        return
    }

    $Target | Add-Member -MemberType NoteProperty -Name $PropertyName -Value $PropertyValue
}

function Set-JsonFileContentInternal {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [object]$Value
    )

    Set-Content -Path $Path -Value ($Value | ConvertTo-Json -Depth 20) -Encoding UTF8
}

function Get-PublishOutputInternal {
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$Outputs,

        [Parameter(Mandatory = $true)]
        [string]$ProjectName,

        [Parameter(Mandatory = $true)]
        [string]$RuntimeIdentifier
    )

    return @(
        $Outputs |
            Where-Object {
                [string]$_.projectName -eq $ProjectName -and
                [string]$_.runtimeIdentifier -eq $RuntimeIdentifier
            } |
            Select-Object -First 1
    )[0]
}

function Invoke-Plugin {
    param(
        [Parameter(Mandatory = $true)]
        $Settings
    )

    Import-PluginDependency -ModuleName "Logging" -RequiredCommand "Write-Log"

    $pluginSettings = $Settings
    $sharedSettings = $Settings.context
    $scriptDir = $sharedSettings.scriptDir

    if (-not (Get-Command Get-EngineFact -ErrorAction SilentlyContinue)) {
        throw "BundleCustomization requires Get-EngineFact (sync Community RepoUtils)."
    }

    $outputs = @(Get-EngineFact -Context $sharedSettings -Namespace 'dotnet' -Name 'publishOutputs' -Default @())
    if ($outputs.Count -eq 0) {
        throw "BundleCustomization requires DotNetPublish runtimeIdentifiers output. Run DotNetPublish first."
    }

    if (-not $pluginSettings.PSObject.Properties['scriptsPath'] -or [string]::IsNullOrWhiteSpace([string]$pluginSettings.scriptsPath)) {
        throw "BundleCustomization plugin requires a scriptsPath setting."
    }

    $scriptsSourcePath = Resolve-PluginPath -Path ([string]$pluginSettings.scriptsPath) -BasePath $scriptDir
    if (-not (Test-Path $scriptsSourcePath -PathType Container)) {
        throw "Scripts folder not found: $scriptsSourcePath"
    }

    $bundleDirectory = if ($pluginSettings.PSObject.Properties['bundleDir'] -and -not [string]::IsNullOrWhiteSpace([string]$pluginSettings.bundleDir)) {
        Resolve-PluginPath -Path ([string]$pluginSettings.bundleDir) -BasePath $scriptDir
    }
    else {
        Join-Path $sharedSettings.artifactsDirectory "bundle"
    }

    $workerWin = Get-PublishOutputInternal -Outputs $outputs -ProjectName 'MaksIT.UScheduler' -RuntimeIdentifier 'win-x64'
    $uiWin = Get-PublishOutputInternal -Outputs $outputs -ProjectName 'MaksIT.UScheduler.UI' -RuntimeIdentifier 'win-x64'
    if ($null -eq $workerWin -or $null -eq $uiWin) {
        throw "BundleCustomization expected win-x64 publish folders for MaksIT.UScheduler and MaksIT.UScheduler.UI."
    }

    Write-Log -Level "STEP" -Message "Preparing portable win-x64 bundle with Scripts..."

    if (Test-Path $bundleDirectory) {
        Remove-Item -Path $bundleDirectory -Recurse -Force
    }

    $workerDest = Join-Path $bundleDirectory "MaksIT.UScheduler"
    $uiDest = Join-Path $bundleDirectory "MaksIT.UScheduler.UI"
    New-Item -ItemType Directory -Path $workerDest, $uiDest | Out-Null
    Copy-Item -Path (Join-Path ([string]$workerWin.directory) '*') -Destination $workerDest -Recurse -Force
    Copy-Item -Path (Join-Path ([string]$uiWin.directory) '*') -Destination $uiDest -Recurse -Force

    $scriptsDestination = Join-Path $bundleDirectory "Scripts"
    Copy-Item -Path $scriptsSourcePath -Destination $scriptsDestination -Recurse
    Write-Log -Level "OK" -Message "  Scripts copied: $scriptsDestination"

    foreach ($linuxOut in @(
            Get-PublishOutputInternal -Outputs $outputs -ProjectName 'MaksIT.UScheduler' -RuntimeIdentifier 'linux-x64'
        )) {
        if ($null -eq $linuxOut) {
            continue
        }

        $linuxScripts = Join-Path ([string]$linuxOut.directory) "Scripts"
        if (Test-Path $linuxScripts) {
            Remove-Item -LiteralPath $linuxScripts -Recurse -Force
        }

        Copy-Item -Path $scriptsSourcePath -Destination $linuxScripts -Recurse
    }

    $projectConfig = $pluginSettings.projects
    if ($null -ne $projectConfig) {
        $uiAppSettingsFile = if ($projectConfig.PSObject.Properties['uiAppSettingsFile']) {
            [string]$projectConfig.uiAppSettingsFile
        }
        else {
            [string]$projectConfig.scheduleManagerAppSettingsFile
        }
        $uiServiceBinPath = if ($projectConfig.PSObject.Properties['uiServiceBinPath']) {
            [string]$projectConfig.uiServiceBinPath
        }
        else {
            [string]$projectConfig.scheduleManagerServiceBinPath
        }
        $uiAppSettingsPath = Join-Path $uiDest $uiAppSettingsFile
        if (Test-Path $uiAppSettingsPath -PathType Leaf) {
            $uiAppSettings = Get-Content $uiAppSettingsPath -Raw | ConvertFrom-Json
            if ($uiAppSettings.PSObject.Properties['USchedulerSettings'] -and $null -ne $uiAppSettings.USchedulerSettings) {
                Ensure-NotePropertyInternal -Target $uiAppSettings.USchedulerSettings -PropertyName "ServiceBinPath" -PropertyValue $uiServiceBinPath
                Set-JsonFileContentInternal -Path $uiAppSettingsPath -Value $uiAppSettings
                Write-Log -Level "OK" -Message "  Updated UI appsettings."
            }
        }

        $uSchedulerAppSettingsPath = Join-Path $workerDest ([string]$projectConfig.uschedulerAppSettingsFile)
        if (Test-Path $uSchedulerAppSettingsPath -PathType Leaf) {
            $uSchedulerAppSettings = Get-Content $uSchedulerAppSettingsPath -Raw | ConvertFrom-Json
            if (-not $uSchedulerAppSettings.PSObject.Properties['Configuration'] -or $null -eq $uSchedulerAppSettings.Configuration) {
                Ensure-NotePropertyInternal -Target $uSchedulerAppSettings -PropertyName "Configuration" -PropertyValue ([pscustomobject]@{})
            }

            Ensure-NotePropertyInternal -Target $uSchedulerAppSettings.Configuration -PropertyName "LogDir" -PropertyValue ([string]$projectConfig.uschedulerLogDir)

            $powerShellScripts = @(
                Get-ChildItem -Path $scriptsDestination -Filter "*.ps1" -Recurse -File |
                    Where-Object { $_.Directory.Name -ne "Utilities" } |
                    ForEach-Object {
                        $relativePath = $_.FullName.Substring($scriptsDestination.Length + 1).Replace('\', '/')
                        $scriptPath = "{0}/{1}" -f ([string]$projectConfig.scriptsRelativeToExe).TrimEnd('\', '/'), $relativePath
                        $folder = $_.Directory.Name
                        $platforms = @()
                        $description = $null
                        switch ($folder) {
                            'HyperV-Backup' {
                                $platforms = @('Windows')
                                $description = 'Exports and retains Hyper-V virtual machines.'
                            }
                            'Windows-Update' {
                                $platforms = @('Windows')
                                $description = 'Installs Windows updates on a schedule.'
                            }
                            'File-Sync' {
                                $platforms = @('Windows')
                                $description = 'Runs a FreeFileSync batch job.'
                            }
                            'Native-Sync' {
                                $description = 'Pure PowerShell folder sync (mirror, update, or two-way).'
                            }
                        }
                        $entry = [ordered]@{
                            Path     = $scriptPath
                            IsSigned = $false
                            Disabled = $true
                        }
                        if ($description) { $entry.Description = $description }
                        if ($platforms.Count -gt 0) { $entry.Platforms = $platforms }
                        [pscustomobject]$entry
                    }
            )

            Ensure-NotePropertyInternal -Target $uSchedulerAppSettings.Configuration -PropertyName "Powershell" -PropertyValue $powerShellScripts
            Set-JsonFileContentInternal -Path $uSchedulerAppSettingsPath -Value $uSchedulerAppSettings
            Write-Log -Level "OK" -Message "  Updated UScheduler appsettings ($($powerShellScripts.Count) script entries)."
        }
    }

    $batPath = Join-Path $bundleDirectory "Start-UScheduler.bat"
    Set-Content -Path $batPath -Value "@echo off`r`nstart `"`" `"%~dp0MaksIT.UScheduler.UI\MaksIT.UScheduler.UI.exe`"`r`n" -Encoding ASCII
    $shPath = Join-Path $bundleDirectory "start-uscheduler.sh"
    $shBody = @'
#!/bin/sh
DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
exec "$DIR/MaksIT.UScheduler.UI/MaksIT.UScheduler.UI" "$@"
'@
    Set-Content -Path $shPath -Value $shBody -Encoding utf8
    Write-Log -Level "OK" -Message "  Created launchers."

    $installerPayload = if ($pluginSettings.PSObject.Properties['installerPayloadDir'] -and -not [string]::IsNullOrWhiteSpace([string]$pluginSettings.installerPayloadDir)) {
        Resolve-PluginPath -Path ([string]$pluginSettings.installerPayloadDir) -BasePath $scriptDir
    }
    else {
        Join-Path $sharedSettings.artifactsDirectory "installer-payload"
    }

    Write-Log -Level "STEP" -Message "Preparing per-machine installer payload (worker + UI + Scripts)..."
    if (Test-Path $installerPayload) {
        Remove-Item -Path $installerPayload -Recurse -Force
    }

    New-Item -ItemType Directory -Path $installerPayload | Out-Null
    Copy-Item -Path (Join-Path ([string]$uiWin.directory) '*') -Destination $installerPayload -Recurse -Force
    Copy-Item -Path (Join-Path ([string]$workerWin.directory) '*') -Destination $installerPayload -Recurse -Force
    $payloadScripts = Join-Path $installerPayload "Scripts"
    if (Test-Path -LiteralPath $payloadScripts) {
        Remove-Item -LiteralPath $payloadScripts -Recurse -Force
    }
    Copy-Item -Path $scriptsSourcePath -Destination $payloadScripts -Recurse
    Write-Log -Level "OK" -Message "  Installer payload: $installerPayload"
    Write-Log -Level "OK" -Message "  Installer Scripts: $payloadScripts"

    Set-EngineFact -Context $sharedSettings -Namespace 'release' -Name 'archiveInputs' -Value @($bundleDirectory) -Overwrite Replace -LegacyProperty 'releaseArchiveInputs'
    Set-EngineFact -Context $sharedSettings -Namespace 'dotnet' -Name 'publishOutputs' -Value @() -Overwrite Replace

    Write-Log -Level "OK" -Message "Portable bundle ready: $bundleDirectory"
}

Export-ModuleMember -Function Invoke-Plugin
