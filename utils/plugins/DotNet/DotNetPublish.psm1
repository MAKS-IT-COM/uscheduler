#requires -Version 7.0
#requires -PSEdition Core

<#
.SYNOPSIS
    .NET publish plugin for producing application release artifacts.

.DESCRIPTION
    This plugin publishes configured .NET projects into the artifacts directory
    and appends those publish folders to shared archive inputs so later plugins
    can zip them next to any earlier pack outputs. Existing NuGet package facts
    (packageFile) are left unchanged.

    Optional runtimeIdentifiers (or runtimeIdentifier) produce per-RID folders
    under artifactsDir/<ProjectName>/<rid> for desktop installers (Windows MSI /
    Linux Flatpak). When RIDs are set, selfContained defaults to true.
#>

if (-not (Get-Command Import-PluginDependency -ErrorAction SilentlyContinue)) {
    $srcDir = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
        $pluginSupportModulePath = Join-Path $srcDir "modules/Engine/PluginSupport.psm1"
    if (Test-Path $pluginSupportModulePath -PathType Leaf) {
        Import-Module $pluginSupportModulePath -Force -Global -ErrorAction Stop
    }
}

function Get-DotNetPublishRuntimeIdentifiers {
    param(
        [Parameter(Mandatory = $true)]
        $PluginSettings
    )

    $rids = [System.Collections.Generic.List[string]]::new()
    if ($PluginSettings.PSObject.Properties['runtimeIdentifiers'] -and $null -ne $PluginSettings.runtimeIdentifiers) {
        foreach ($item in @($PluginSettings.runtimeIdentifiers)) {
            $value = [string]$item
            if (-not [string]::IsNullOrWhiteSpace($value)) {
                $rids.Add($value.Trim())
            }
        }
    }
    elseif ($PluginSettings.PSObject.Properties['runtimeIdentifier'] -and -not [string]::IsNullOrWhiteSpace([string]$PluginSettings.runtimeIdentifier)) {
        $rids.Add(([string]$PluginSettings.runtimeIdentifier).Trim())
    }

    return @($rids)
}

function Invoke-Plugin {
    param(
        [Parameter(Mandatory = $true)]
        $Settings
    )

    Import-PluginDependency -ModuleName "Logging" -RequiredCommand "Write-Log"
    Import-PluginDependency -ModuleName "ScriptConfig" -RequiredCommand "Assert-Command"
    Import-PluginDependency -ModuleName "EngineContext" -RequiredCommand "Set-EngineFact"
    Import-PluginDependency -ModuleName "ExternalCommandSupport" -RequiredCommand "Invoke-ExternalCommand"

    $pluginSettings = $Settings
    $sharedSettings = $Settings.context
    $scriptDir = $sharedSettings.scriptDir
    $projectFiles = @()

    Assert-Command dotnet

    if ($pluginSettings.PSObject.Properties['projectFiles'] -and $null -ne $pluginSettings.projectFiles) {
        $projectFiles = @(Resolve-RelativePaths -Value $pluginSettings.projectFiles -BasePath $scriptDir)
    }
    else {
        $fromFact = Get-EngineFact -Context $sharedSettings -Namespace 'dotnet' -Name 'projectFiles' -LegacyProperty @('projectFiles')
        if ($null -ne $fromFact) {
            $projectFiles = @($fromFact)
        }
        elseif ($sharedSettings.PSObject.Properties['projectFiles'] -and $null -ne $sharedSettings.projectFiles) {
            $projectFiles = @($sharedSettings.projectFiles)
        }
    }

    if ($projectFiles.Count -eq 0) {
        throw "DotNetPublish plugin requires projectFiles in plugin settings or projectFiles on shared context."
    }

    if ($pluginSettings.PSObject.Properties['artifactsDir'] -and -not [string]::IsNullOrWhiteSpace([string]$pluginSettings.artifactsDir)) {
        $artifactsDirectory = [System.IO.Path]::GetFullPath((Join-Path $scriptDir ([string]$pluginSettings.artifactsDir)))
        Set-EngineState -Context $sharedSettings -Name 'artifactsDirectory' -Value $artifactsDirectory
        Set-EngineState -Context $sharedSettings -Name 'releaseDir' -Value $artifactsDirectory
    }
    else {
        $artifactsDirectory = $sharedSettings.artifactsDirectory
    }

    if ([string]::IsNullOrWhiteSpace([string]$artifactsDirectory)) {
        throw "DotNetPublish plugin requires artifactsDir in plugin settings or artifactsDirectory on shared context."
    }

    if (!(Test-Path $artifactsDirectory)) {
        New-Item -ItemType Directory -Path $artifactsDirectory | Out-Null
    }

    $existing = Get-EngineFact -Context $sharedSettings -Namespace 'release' -Name 'archiveInputs' -LegacyProperty @('releaseArchiveInputs')
    $archiveInputs = [System.Collections.Generic.List[object]]::new()
    if ($null -ne $existing) {
        foreach ($item in @($existing)) {
            if ($null -ne $item) {
                $archiveInputs.Add($item)
            }
        }
    }

    $runtimeIdentifiers = @(Get-DotNetPublishRuntimeIdentifiers -PluginSettings $pluginSettings)
    $selfContained = $null
    if ($pluginSettings.PSObject.Properties['selfContained'] -and $null -ne $pluginSettings.selfContained) {
        $selfContained = [bool]$pluginSettings.selfContained
    }
    elseif ($runtimeIdentifiers.Count -gt 0) {
        $selfContained = $true
    }

    $publishSingleFile = $false
    if ($pluginSettings.PSObject.Properties['publishSingleFile'] -and $null -ne $pluginSettings.publishSingleFile) {
        $publishSingleFile = [bool]$pluginSettings.publishSingleFile
    }

    $additionalArguments = @()
    if ($pluginSettings.PSObject.Properties['additionalPublishArguments'] -and $null -ne $pluginSettings.additionalPublishArguments) {
        $additionalArguments = @($pluginSettings.additionalPublishArguments | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    }

    $publishOutputs = [System.Collections.Generic.List[object]]::new()
    $ridLoop = @($null)
    if ($runtimeIdentifiers.Count -gt 0) {
        $ridLoop = @($runtimeIdentifiers)
    }

    foreach ($publishProjectPath in $projectFiles) {
        $projectName = [System.IO.Path]::GetFileNameWithoutExtension($publishProjectPath)
        $projectRoot = Join-Path $artifactsDirectory $projectName

        foreach ($runtimeIdentifier in $ridLoop) {
            $publishDir = if ([string]::IsNullOrWhiteSpace([string]$runtimeIdentifier)) {
                $projectRoot
            }
            else {
                Join-Path $projectRoot ([string]$runtimeIdentifier)
            }

            if (Test-Path $publishDir) {
                Remove-Item -Path $publishDir -Recurse -Force
            }

            $ridLabel = if ([string]::IsNullOrWhiteSpace([string]$runtimeIdentifier)) { 'current runtime' } else { [string]$runtimeIdentifier }
            Write-Log -Level "STEP" -Message "Publishing release artifact ($projectName / $ridLabel)..."
            $dotnetPublishArguments = @(
                'publish', $publishProjectPath, '-c', 'Release', '-o', $publishDir, '--nologo'
            )
            if (-not [string]::IsNullOrWhiteSpace([string]$runtimeIdentifier)) {
                $dotnetPublishArguments += @('-r', [string]$runtimeIdentifier)
            }

            if ($null -ne $selfContained) {
                if ($selfContained) {
                    $dotnetPublishArguments += '--self-contained'
                }
                else {
                    $dotnetPublishArguments += '--no-self-contained'
                }
            }

            if ($publishSingleFile) {
                $dotnetPublishArguments += '-p:PublishSingleFile=true'
            }

            if ($additionalArguments.Count -gt 0) {
                $dotnetPublishArguments += $additionalArguments
            }

            Invoke-ExternalCommand -Name dotnet -ArgumentList $dotnetPublishArguments | Out-Null

            $publishedItems = @(Get-ChildItem -Path $publishDir -Force -ErrorAction SilentlyContinue)
            if ($publishedItems.Count -eq 0) {
                throw "dotnet publish completed, but no files were produced in: $publishDir"
            }

            Write-Log -Level "OK" -Message "  Published artifact ready: $publishDir"
            $archiveInputs.Add($publishDir)
            $publishOutputs.Add([pscustomobject]@{
                    projectName        = $projectName
                    runtimeIdentifier  = [string]$runtimeIdentifier
                    directory          = $publishDir
                })
        }
    }

    Set-EngineFact -Context $sharedSettings -Namespace 'release' -Name 'archiveInputs' -Value @($archiveInputs) -Overwrite Replace -LegacyProperty 'releaseArchiveInputs'
    Set-EngineFact -Context $sharedSettings -Namespace 'dotnet' -Name 'publishOutputs' -Value @($publishOutputs) -Overwrite Replace
}

Export-ModuleMember -Function Invoke-Plugin, Get-DotNetPublishRuntimeIdentifiers
