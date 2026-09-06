#requires -Version 7.0
#requires -PSEdition Core

$modulesDir = Split-Path $PSScriptRoot -Parent

if (-not (Get-Command Write-Log -ErrorAction SilentlyContinue)) {
    $loggingModulePath = Join-Path $modulesDir "Logging.psm1"
    if (Test-Path $loggingModulePath -PathType Leaf) {
        Import-Module $loggingModulePath -Force
    }
}

if (-not (Get-Command Get-CurrentBranch -ErrorAction SilentlyContinue)) {
    $gitToolsModulePath = Join-Path $modulesDir "GitTools.psm1"
    if (Test-Path $gitToolsModulePath -PathType Leaf) {
        Import-Module $gitToolsModulePath -Force
    }
}

if (-not (Get-Command Get-PluginStageLabel -ErrorAction SilentlyContinue) -or -not (Get-Command Test-IsPublishPlugin -ErrorAction SilentlyContinue)) {
    $pluginSupportModulePath = Join-Path $PSScriptRoot "PluginSupport.psm1"
    if (Test-Path $pluginSupportModulePath -PathType Leaf) {
        Import-Module $pluginSupportModulePath -Force
    }
}

if (-not (Get-Command Resolve-RelativePaths -ErrorAction SilentlyContinue) -or -not (Get-Command Set-EngineState -ErrorAction SilentlyContinue)) {
    $engineContextModulePath = Join-Path $PSScriptRoot "EngineContext.psm1"
    if (Test-Path $engineContextModulePath -PathType Leaf) {
        Import-Module $engineContextModulePath -Force
    }
}

function Get-EnabledVersionPlugins {
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$Plugins,

        [Parameter(Mandatory = $true)]
        [string]$ScriptDir
    )

    $versionPlugins = @()
    foreach ($plugin in $Plugins) {
        if ($null -eq $plugin -or [string]::IsNullOrWhiteSpace([string]$plugin.name)) {
            continue
        }

        if (-not $plugin.enabled) {
            continue
        }

        $metadata = Get-PluginMetadataObject -Plugin $plugin -EngineDirectory $ScriptDir
        if ($null -eq $metadata) {
            continue
        }

        if (($metadata.PSObject.Properties.Name -contains 'providesVersion') -and [bool]$metadata.providesVersion) {
            $versionPlugins += $plugin
        }
    }

    return @($versionPlugins)
}

function Invoke-VersionPlugin {
    param(
        [Parameter(Mandatory = $true)]
        $Plugin,

        [Parameter(Mandatory = $true)]
        [psobject]$Context,

        [Parameter(Mandatory = $true)]
        [string]$EngineDirectory
    )

    $modulePath = Resolve-PluginModulePath -Plugin $Plugin -EngineDirectory $EngineDirectory
    if (-not (Test-Path $modulePath -PathType Leaf)) {
        throw "Version plugin '$($Plugin.name)' module not found at: $modulePath"
    }

    $moduleInfo = Import-Module $modulePath -Force -PassThru -ErrorAction Stop
    $invokeCommand = Get-Command -Name "Invoke-Plugin" -Module $moduleInfo.Name -ErrorAction Stop
    $pluginSettings = New-PluginInvocationSettings -Plugin $Plugin -SharedSettings $Context
    & $invokeCommand -Settings $pluginSettings
}

function Resolve-EngineContextVersion {
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$Plugins,

        [Parameter(Mandatory = $true)]
        [psobject]$Context,

        [Parameter(Mandatory = $true)]
        [string]$ScriptDir
    )

    $versionPlugins = @(Get-EnabledVersionPlugins -Plugins $Plugins -ScriptDir $ScriptDir)
    if ($versionPlugins.Count -eq 0) {
        throw "Configure exactly one enabled release version plugin (declares providesVersion in Get-PluginMetadata), e.g. DotNetReleaseVersion (projectFiles), NpmReleaseVersion (packageJsonPath), or FileReleaseVersion (versionFilePath)."
    }

    if ($versionPlugins.Count -gt 1) {
        $names = ($versionPlugins | ForEach-Object { [string]$_.name }) -join ', '
        throw "Configure only one enabled release version plugin. Found: $names."
    }

    $versionPlugin = $versionPlugins[0]
    Invoke-VersionPlugin -Plugin $versionPlugin -Context $Context -EngineDirectory $ScriptDir

    $version = Get-EngineState -Context $Context -Name 'version'
    if ($null -eq $version -or [string]::IsNullOrWhiteSpace([string]$version)) {
        throw "Version plugin '$($versionPlugin.name)' did not set a version on the engine context."
    }

    return [string]$versionPlugin.name
}

function Assert-WorkingTreeClean {
    $gitStatus = Get-GitStatusShort
    if (-not [string]::IsNullOrWhiteSpace([string]$gitStatus)) {
        Write-Log -Level "WARN" -Message "  Uncommitted changes detected (use ReleasePublishGuard requireCleanWorkingTree to block publish)."
        foreach ($line in @([string]$gitStatus -split "`r?`n")) {
            if (-not [string]::IsNullOrWhiteSpace($line)) {
                Write-Log -Level "WARN" -Message "  $line"
            }
        }
        return
    }

    Write-Log -Level "OK" -Message "  Working directory is clean."
}

function Initialize-ReleaseStageContext {
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$SharedSettings,

        [Parameter(Mandatory = $true)]
        [string]$ArtifactsDirectory
    )

    if (-not $SharedSettings.PSObject.Properties['releaseDir'] -or [string]::IsNullOrWhiteSpace([string]$SharedSettings.releaseDir)) {
        if (Get-Command Set-EngineState -ErrorAction SilentlyContinue) {
            Set-EngineState -Context $SharedSettings -Name 'releaseDir' -Value $ArtifactsDirectory
        }
        else {
            $SharedSettings | Add-Member -NotePropertyName releaseDir -NotePropertyValue $ArtifactsDirectory -Force
        }
    }
}

function New-EngineContext {
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$Plugins,

        [Parameter(Mandatory = $true)]
        [string]$ScriptDir,

        [Parameter(Mandatory = $true)]
        [string]$SrcDir,

        [Parameter(Mandatory = $false)]
        [psobject]$Settings,

        [Parameter(Mandatory = $false)]
        [psobject]$ExtensionData
    )

    $releaseRelative = '..\..\..\releases'
    $artifactsDirectory = [System.IO.Path]::GetFullPath((Join-Path $ScriptDir $releaseRelative))

    $currentBranch = Get-CurrentBranch

    $releaseBranches = @()
    foreach ($p in $Plugins) {
        if (-not $p.enabled) { continue }
        if ([string]$p.name -ne 'ReleasePublishGuard') { continue }
        foreach ($b in (Get-PluginBranches -Plugin $p)) {
            $releaseBranches += $b
        }
    }
    $releaseBranches = @($releaseBranches | Where-Object { $_ -ne '*' -and -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
    if ($releaseBranches.Count -eq 0) {
        foreach ($p in ($Plugins | Where-Object { Test-IsPublishPlugin -Plugin $_ })) {
            if (-not $p.enabled) { continue }
            foreach ($b in (Get-PluginBranches -Plugin $p)) {
                $releaseBranches += $b
            }
        }
        $releaseBranches = @($releaseBranches | Where-Object { $_ -ne '*' -and -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
    }
    if ($releaseBranches.Count -eq 0) {
        $releaseBranches = @('main')
    }

    $isNonReleaseBranch = -not ($releaseBranches -contains $currentBranch)

    Assert-WorkingTreeClean

    $context = [pscustomobject]@{
        scriptDir = $ScriptDir
        srcDir = $SrcDir
        utilsDir = $SrcDir
        currentBranch = $currentBranch
        artifactsDirectory = $artifactsDirectory
        isNonReleaseBranch = $isNonReleaseBranch
        releaseBranches = $releaseBranches
        skipPublishPlugins = $false
        facts = [ordered]@{}
    }
    $context = Copy-RepoUtilsSecretsEnvNamesToContext -Context $context -Settings $Settings

    $versionSource = Resolve-EngineContextVersion -Plugins $Plugins -Context $context -ScriptDir $ScriptDir
    $version = [string](Get-EngineState -Context $context -Name 'version' -Required)
    $tag = "v$version"
    Set-EngineState -Context $context -Name 'tag' -Value $tag
    Write-Log -Level "INFO" -Message "  Release tag default from ${versionSource}: $tag (ReleasePublishGuard may replace from git when publish is allowed)."

    $dryRunPlugins = @(
        $Plugins |
            Where-Object {
                $_.enabled -and
                ($_.PSObject.Properties.Name -contains 'dryRun') -and
                $null -ne $_.dryRun -and
                [bool]$_.dryRun -and
                (Test-PluginMutatesRemote -Plugin $_ -EngineDirectory $ScriptDir)
            } |
            ForEach-Object { [string]$_.name }
    )
    if ($dryRunPlugins.Count -gt 0) {
        Write-Log -Level "INFO" -Message "  Plugin dryRun (validate only): $($dryRunPlugins -join ', ')"
    }

    $expandContext = Get-Command Expand-ExtensionEngineContext -ErrorAction SilentlyContinue
    if ($expandContext) {
        $expandParams = @{
            Context = $context
            ScriptDir = $ScriptDir
            Settings = $Settings
        }
        if ($PSBoundParameters.ContainsKey('ExtensionData')) {
            $expandParams['ExtensionData'] = $ExtensionData
        }

        return & $expandContext @expandParams
    }

    return $context
}

function Get-PreferredReleaseBranch {
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$EngineContext
    )

    if ($EngineContext.releaseBranches.Count -gt 0) {
        return $EngineContext.releaseBranches[0]
    }

    return "main"
}

Export-ModuleMember -Function Assert-WorkingTreeClean, Initialize-ReleaseStageContext, New-EngineContext, Get-PreferredReleaseBranch
