#requires -Version 7.0
#requires -PSEdition Core

<#
.SYNOPSIS
    Customizes the staged release bundle after build artifacts are produced.

.DESCRIPTION
    Recreates the legacy release bundle layout by:
    - publishing all configured .NET projects into bundle/bin/<ProjectName>
    - copying the Scripts folder into bundle/Scripts
    - rewriting appsettings.json for the bundled runtime layout
    - optionally creating a launcher batch file

    The plugin then updates the shared release context so CreateArchive zips the
    fully prepared bundle directory instead of the raw publish output.
#>

if (-not (Get-Command Import-PluginDependency -ErrorAction SilentlyContinue)) {
    $pluginSupportModulePath = Join-Path (Split-Path $PSScriptRoot -Parent) "PluginSupport.psm1"
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

function Get-ProjectPropertyValueInternal {
    param(
        [Parameter(Mandatory = $true)]
        [xml]$Csproj,

        [Parameter(Mandatory = $true)]
        [string]$PropertyName
    )

    $propNode = $Csproj.Project.PropertyGroup |
        Where-Object { $_.$PropertyName } |
        Select-Object -First 1

    if ($propNode) {
        return $propNode.$PropertyName
    }

    return $null
}

function Resolve-ProjectExeNameInternal {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProjectPath
    )

    [xml]$csproj = Get-Content $ProjectPath
    $assemblyName = Get-ProjectPropertyValueInternal -Csproj $csproj -PropertyName "AssemblyName"

    if (-not [string]::IsNullOrWhiteSpace([string]$assemblyName)) {
        return [string]$assemblyName
    }

    return [System.IO.Path]::GetFileNameWithoutExtension($ProjectPath)
}

function Find-ProjectBySuffixInternal {
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$PublishedProjects,

        [Parameter(Mandatory = $false)]
        [string]$Suffix
    )

    if ([string]::IsNullOrWhiteSpace($Suffix)) {
        return $null
    }

    return $PublishedProjects |
        Where-Object { $_.ProjectPath -like "*$Suffix" } |
        Select-Object -First 1
}

function Set-JsonFileContentInternal {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [object]$Value
    )

    $jsonOutput = $Value | ConvertTo-Json -Depth 20
    Set-Content -Path $Path -Value $jsonOutput -Encoding UTF8
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

function Invoke-Plugin {
    param(
        [Parameter(Mandatory = $true)]
        $Settings
    )

    Import-PluginDependency -ModuleName "Logging" -RequiredCommand "Write-Log"
    Import-PluginDependency -ModuleName "ScriptConfig" -RequiredCommand "Assert-Command"

    $pluginSettings = $Settings
    $sharedSettings = $Settings.Context

    if (-not $sharedSettings.PSObject.Properties['ProjectFiles'] -or $sharedSettings.ProjectFiles.Count -eq 0) {
        throw "BundleCustomization plugin requires project files in the shared context."
    }

    $scriptDir = $sharedSettings.ScriptDir
    $projectFiles = @($sharedSettings.ProjectFiles)
    $bundleDirectory = if ($pluginSettings.PSObject.Properties['bundleDir'] -and -not [string]::IsNullOrWhiteSpace([string]$pluginSettings.bundleDir)) {
        Resolve-PluginPath -Path ([string]$pluginSettings.bundleDir) -BasePath $scriptDir
    }
    else {
        Join-Path $sharedSettings.ArtifactsDirectory "bundle"
    }

    if (-not $pluginSettings.PSObject.Properties['scriptsPath'] -or [string]::IsNullOrWhiteSpace([string]$pluginSettings.scriptsPath)) {
        throw "BundleCustomization plugin requires a scriptsPath setting."
    }

    $scriptsSourcePath = Resolve-PluginPath -Path ([string]$pluginSettings.scriptsPath) -BasePath $scriptDir
    if (-not (Test-Path $scriptsSourcePath -PathType Container)) {
        throw "Scripts folder not found: $scriptsSourcePath"
    }

    Assert-Command dotnet

    Write-Log -Level "STEP" -Message "Preparing customized release bundle..."

    if (Test-Path $bundleDirectory) {
        Remove-Item -Path $bundleDirectory -Recurse -Force
    }

    New-Item -ItemType Directory -Path $bundleDirectory | Out-Null

    $binDirectory = Join-Path $bundleDirectory "bin"
    New-Item -ItemType Directory -Path $binDirectory | Out-Null

    $publishedProjects = @()

    foreach ($projectPath in $projectFiles) {
        if (-not (Test-Path $projectPath -PathType Leaf)) {
            throw "Project file not found: $projectPath"
        }

        $projectName = [System.IO.Path]::GetFileNameWithoutExtension($projectPath)
        $projectBinDirectory = Join-Path $binDirectory $projectName

        Write-Log -Level "STEP" -Message "  Publishing $projectName into bundle..."
        dotnet publish $projectPath -c Release -o $projectBinDirectory --nologo
        if ($LASTEXITCODE -ne 0) {
            throw "dotnet publish failed for $projectPath."
        }

        $exeBaseName = Resolve-ProjectExeNameInternal -ProjectPath $projectPath
        $publishedProjects += [pscustomobject]@{
            ProjectPath = $projectPath
            ProjectName = $projectName
            BinDirectory = $projectBinDirectory
            ExeBaseName = $exeBaseName
        }

        Write-Log -Level "OK" -Message "    Published: $projectBinDirectory"
    }

    $scriptsDestination = Join-Path $bundleDirectory "Scripts"
    Copy-Item -Path $scriptsSourcePath -Destination $scriptsDestination -Recurse
    Write-Log -Level "OK" -Message "  Scripts copied: $scriptsDestination"

    if ($pluginSettings.PSObject.Properties['projects'] -and $null -ne $pluginSettings.projects) {
        $projectConfig = $pluginSettings.projects

        $scheduleManagerProject = Find-ProjectBySuffixInternal -PublishedProjects $publishedProjects -Suffix ([string]$projectConfig.scheduleManagerCsprojEndsWith)
        if ($null -ne $scheduleManagerProject) {
            $scheduleManagerAppSettingsFile = [string]$projectConfig.scheduleManagerAppSettingsFile
            $scheduleManagerAppSettingsPath = Join-Path $scheduleManagerProject.BinDirectory $scheduleManagerAppSettingsFile

            if (Test-Path $scheduleManagerAppSettingsPath -PathType Leaf) {
                $scheduleManagerAppSettings = Get-Content $scheduleManagerAppSettingsPath -Raw | ConvertFrom-Json
                if ($scheduleManagerAppSettings.PSObject.Properties['USchedulerSettings'] -and $null -ne $scheduleManagerAppSettings.USchedulerSettings) {
                    Ensure-NotePropertyInternal -Target $scheduleManagerAppSettings.USchedulerSettings -PropertyName "ServiceBinPath" -PropertyValue ([string]$projectConfig.scheduleManagerServiceBinPath)
                    Set-JsonFileContentInternal -Path $scheduleManagerAppSettingsPath -Value $scheduleManagerAppSettings
                    Write-Log -Level "OK" -Message "  Updated ScheduleManager appsettings."
                }
                else {
                    Write-Log -Level "WARN" -Message "  ScheduleManager appsettings has no USchedulerSettings section."
                }
            }
            else {
                Write-Log -Level "WARN" -Message "  ScheduleManager appsettings not found: $scheduleManagerAppSettingsPath"
            }
        }
        else {
            Write-Log -Level "WARN" -Message "  ScheduleManager project not found in configured project files."
        }

        $uSchedulerProject = Find-ProjectBySuffixInternal -PublishedProjects $publishedProjects -Suffix ([string]$projectConfig.uschedulerCsprojEndsWith)
        if ($null -ne $uSchedulerProject) {
            $uSchedulerAppSettingsFile = [string]$projectConfig.uschedulerAppSettingsFile
            $uSchedulerAppSettingsPath = Join-Path $uSchedulerProject.BinDirectory $uSchedulerAppSettingsFile

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
                            $relativePath = $_.FullName.Substring($scriptsDestination.Length + 1).Replace('/', '\')
                            $scriptPath = "{0}\{1}" -f ([string]$projectConfig.scriptsRelativeToExe), $relativePath

                            [pscustomobject]@{
                                Path = $scriptPath
                                IsSigned = $false
                                Disabled = $true
                            }
                        }
                )

                Ensure-NotePropertyInternal -Target $uSchedulerAppSettings.Configuration -PropertyName "Powershell" -PropertyValue $powerShellScripts
                Set-JsonFileContentInternal -Path $uSchedulerAppSettingsPath -Value $uSchedulerAppSettings

                Write-Log -Level "OK" -Message "  Updated UScheduler appsettings."
                if ($powerShellScripts.Count -gt 0) {
                    Write-Log -Level "INFO" -Message "    Added $($powerShellScripts.Count) bundled script entries."
                }
            }
            else {
                Write-Log -Level "WARN" -Message "  UScheduler appsettings not found: $uSchedulerAppSettingsPath"
            }
        }
        else {
            Write-Log -Level "WARN" -Message "  UScheduler project not found in configured project files."
        }
    }

    if ($pluginSettings.PSObject.Properties['launcher'] -and $null -ne $pluginSettings.launcher -and $pluginSettings.launcher.enabled) {
        $launcherSettings = $pluginSettings.launcher
        $launcherTarget = $null

        switch ([string]$launcherSettings.targetProject) {
            "scheduleManager" {
                $launcherTarget = Find-ProjectBySuffixInternal -PublishedProjects $publishedProjects -Suffix ([string]$pluginSettings.projects.scheduleManagerCsprojEndsWith)
            }
            "uscheduler" {
                $launcherTarget = Find-ProjectBySuffixInternal -PublishedProjects $publishedProjects -Suffix ([string]$pluginSettings.projects.uschedulerCsprojEndsWith)
            }
            default {
                Write-Log -Level "WARN" -Message "  Unknown launcher targetProject '$([string]$launcherSettings.targetProject)'."
            }
        }

        if ($null -ne $launcherTarget) {
            $launcherPath = Join-Path $bundleDirectory ([string]$launcherSettings.fileName)
            $launcherExePath = "%~dp0bin\$($launcherTarget.ProjectName)\$($launcherTarget.ExeBaseName).exe"
            $launcherContent = @"
@echo off
start "" "$launcherExePath"
"@

            Set-Content -Path $launcherPath -Value $launcherContent -Encoding ASCII
            Write-Log -Level "OK" -Message "  Created launcher: $launcherPath"
        }
        else {
            Write-Log -Level "WARN" -Message "  Launcher target project could not be resolved."
        }
    }

    $sharedSettings | Add-Member -NotePropertyName BundleDirectory -NotePropertyValue $bundleDirectory -Force
    $sharedSettings | Add-Member -NotePropertyName ReleaseArchiveInputs -NotePropertyValue @($bundleDirectory) -Force

    Write-Log -Level "OK" -Message "Customized release bundle ready: $bundleDirectory"
}

Export-ModuleMember -Function Invoke-Plugin
