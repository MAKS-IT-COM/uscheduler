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

if (-not (Get-Command Resolve-ReleaseVersion -ErrorAction SilentlyContinue)) {
    $engineContextModulePath = Join-Path $PSScriptRoot "EngineContext.psm1"
    if (Test-Path $engineContextModulePath -PathType Leaf) {
        Import-Module $engineContextModulePath -Force
    }
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
        [object[]]$RemainingPlugins,

        [Parameter(Mandatory = $true)]
        [psobject]$SharedSettings,

        [Parameter(Mandatory = $true)]
        [string]$ArtifactsDirectory,

        [Parameter(Mandatory = $true)]
        [string]$Version
    )

    if (-not $SharedSettings.PSObject.Properties['releaseDir'] -or [string]::IsNullOrWhiteSpace([string]$SharedSettings.releaseDir)) {
        $SharedSettings | Add-Member -NotePropertyName releaseDir -NotePropertyValue $ArtifactsDirectory -Force
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
        [psobject]$Settings
    )

    $resolvedVersion = Resolve-ReleaseVersion -Plugins $Plugins -ScriptDir $ScriptDir
    $version = $resolvedVersion.version
    $versionSource = $resolvedVersion.source
    $releaseRelative = '..\..\..\release'
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

    $isReleaseBranch = $releaseBranches -contains $currentBranch
    $isNonReleaseBranch = -not $isReleaseBranch

    Assert-WorkingTreeClean

    $tag = "v$version"
    Write-Log -Level "INFO" -Message "  Release tag default from ${versionSource}: $tag (ReleasePublishGuard may replace from git when publish is allowed)."

    return [pscustomobject]@{
        scriptDir = $ScriptDir
        srcDir = $SrcDir
        utilsDir = $SrcDir
        currentBranch = $currentBranch
        version = $version
        tag = $tag
        artifactsDirectory = $artifactsDirectory
        isReleaseBranch = $isReleaseBranch
        isNonReleaseBranch = $isNonReleaseBranch
        releaseBranches = $releaseBranches
        publishCompleted = $false
        skipPublishPlugins = $false
    }
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
