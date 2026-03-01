#requires -Version 7.0
#requires -PSEdition Core

if (-not (Get-Command Write-Log -ErrorAction SilentlyContinue)) {
    $loggingModulePath = Join-Path (Split-Path $PSScriptRoot -Parent) "Logging.psm1"
    if (Test-Path $loggingModulePath -PathType Leaf) {
        Import-Module $loggingModulePath -Force
    }
}

if (-not (Get-Command Get-CurrentBranch -ErrorAction SilentlyContinue)) {
    $gitToolsModulePath = Join-Path (Split-Path $PSScriptRoot -Parent) "GitTools.psm1"
    if (Test-Path $gitToolsModulePath -PathType Leaf) {
        Import-Module $gitToolsModulePath -Force
    }
}

if (-not (Get-Command Get-PluginStage -ErrorAction SilentlyContinue) -or -not (Get-Command Test-IsPublishPlugin -ErrorAction SilentlyContinue)) {
    $pluginSupportModulePath = Join-Path $PSScriptRoot "PluginSupport.psm1"
    if (Test-Path $pluginSupportModulePath -PathType Leaf) {
        Import-Module $pluginSupportModulePath -Force
    }
}

if (-not (Get-Command New-DotNetReleaseContext -ErrorAction SilentlyContinue)) {
    $dotNetProjectSupportModulePath = Join-Path $PSScriptRoot "DotNetProjectSupport.psm1"
    if (Test-Path $dotNetProjectSupportModulePath -PathType Leaf) {
        Import-Module $dotNetProjectSupportModulePath -Force
    }
}

function Assert-WorkingTreeClean {
    param(
        [Parameter(Mandatory = $true)]
        [bool]$IsReleaseBranch
    )

    $gitStatus = Get-GitStatusShort
    if ($gitStatus) {
        if ($IsReleaseBranch) {
            Write-Error "Working directory has uncommitted changes. Commit or stash them before releasing."
            Write-Log -Level "WARN" -Message "Uncommitted files:"
            $gitStatus | ForEach-Object { Write-Log -Level "WARN" -Message "  $_" }
            exit 1
        }

        Write-Log -Level "WARN" -Message "  Uncommitted changes detected (allowed on dev branch)."
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

    Write-Log -Level "STEP" -Message "Verifying tag is pushed to remote..."
    $remoteTagExists = Test-RemoteTagExists -Tag $SharedSettings.Tag -Remote "origin"
    if (-not $remoteTagExists) {
        Write-Log -Level "WARN" -Message "  Tag $($SharedSettings.Tag) not found on remote. Pushing..."
        Push-TagToRemote -Tag $SharedSettings.Tag -Remote "origin"
    }
    else {
        Write-Log -Level "OK" -Message "  Tag exists on remote."
    }

    if (-not $SharedSettings.PSObject.Properties['ReleaseDir'] -or [string]::IsNullOrWhiteSpace([string]$SharedSettings.ReleaseDir)) {
        $SharedSettings | Add-Member -NotePropertyName ReleaseDir -NotePropertyValue $ArtifactsDirectory -Force
    }
}

function New-EngineContext {
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$Plugins,

        [Parameter(Mandatory = $true)]
        [string]$ScriptDir,

        [Parameter(Mandatory = $true)]
        [string]$UtilsDir
    )

    $dotNetContext = New-DotNetReleaseContext -Plugins $Plugins -ScriptDir $ScriptDir

    $currentBranch = Get-CurrentBranch
    $releaseBranches = @(
        $Plugins |
            Where-Object { Test-IsPublishPlugin -Plugin $_ } |
            ForEach-Object { Get-PluginBranches -Plugin $_ } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            Select-Object -Unique
    )

    $isReleaseBranch = $releaseBranches -contains $currentBranch
    $isNonReleaseBranch = -not $isReleaseBranch

    Assert-WorkingTreeClean -IsReleaseBranch:$isReleaseBranch

    $version = $dotNetContext.Version

    if ($isReleaseBranch) {
        $tag = Get-CurrentCommitTag -Version $version

        if ($tag -notmatch '^v(\d+\.\d+\.\d+)$') {
            Write-Error "Tag '$tag' does not match expected format 'vX.Y.Z' (e.g., v$version)."
            exit 1
        }

        $tagVersion = $Matches[1]
        if ($tagVersion -ne $version) {
            Write-Error "Tag version ($tagVersion) does not match the project version ($version)."
            Write-Log -Level "WARN" -Message "  Either update the tag or the project version."
            exit 1
        }

        Write-Log -Level "OK" -Message "  Tag found: $tag (matches project version)"
    }
    else {
        $tag = "v$version"
        Write-Log -Level "INFO" -Message "  Using version from the package project (no tag required on non-release branches)."
    }

    return [pscustomobject]@{
        ScriptDir = $ScriptDir
        UtilsDir = $UtilsDir
        CurrentBranch = $currentBranch
        Version = $version
        Tag = $tag
        ProjectFiles = $dotNetContext.ProjectFiles
        ArtifactsDirectory = $dotNetContext.ArtifactsDirectory
        IsReleaseBranch = $isReleaseBranch
        IsNonReleaseBranch = $isNonReleaseBranch
        ReleaseBranches = $releaseBranches
        NonReleaseBranches = @()
        PublishCompleted = $false
    }
}

function Get-PreferredReleaseBranch {
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$EngineContext
    )

    if ($EngineContext.ReleaseBranches.Count -gt 0) {
        return $EngineContext.ReleaseBranches[0]
    }

    return "main"
}

Export-ModuleMember -Function Assert-WorkingTreeClean, Initialize-ReleaseStageContext, New-EngineContext, Get-PreferredReleaseBranch
