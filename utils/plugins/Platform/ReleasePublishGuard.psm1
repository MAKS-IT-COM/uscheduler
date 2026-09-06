#requires -Version 7.0
#requires -PSEdition Core

<#
.SYNOPSIS
    Central gate before remote-mutation plugins (see each plugin's Get-PluginMetadata).

.DESCRIPTION
    Place this plugin immediately before any publish plugins in scriptSettings.json. It sets
    shared context skipPublishPlugins to false when all configured requirements pass, or true
    when they do not (whenRequirementsNotMet: skip). Publish plugins no longer use per-plugin
    branch lists; put allowed branches here instead.

    Typical checks: allowed branches, optional clean working tree, exact semver tag on HEAD
    (vX.Y.Z or vX.Y.Z-prerelease such as v0.1.0-alpha.1 / v0.1.0-beta.1 / v0.1.0-rc.1),
    tag version vs release version, optional push tag to remote.

    The engine preflight no longer reads git tags; this plugin sets context.tag from the
    git tag on HEAD when required. Shared context version always remains from DotNetReleaseVersion.
#>

if (-not (Get-Command Import-PluginDependency -ErrorAction SilentlyContinue)) {
    $srcDir = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
        $pluginSupportModulePath = Join-Path $srcDir "modules/Engine/PluginSupport.psm1"
    if (Test-Path $pluginSupportModulePath -PathType Leaf) {
        Import-Module $pluginSupportModulePath -Force -Global -ErrorAction Stop
    }
}

function Get-ExactTagOnHeadSilentlyInternal {
    $raw = & git describe --tags --exact-match HEAD 2>&1
    if ($LASTEXITCODE -ne 0) {
        return $null
    }
    $s = ($raw | Out-String).Trim()
    if ([string]::IsNullOrWhiteSpace($s)) {
        return $null
    }
    return $s
}

function Invoke-NotMetInternal {
    param(
        [Parameter(Mandatory = $true)]
        $Shared,

        [Parameter(Mandatory = $true)]
        [string]$When,

        [Parameter(Mandatory = $true)]
        [string]$Reason
    )

    if (Get-Command Set-EngineState -ErrorAction SilentlyContinue) {
        Set-EngineState -Context $Shared -Name 'skipPublishPlugins' -Value $true
    }
    else {
        $Shared | Add-Member -NotePropertyName skipPublishPlugins -NotePropertyValue $true -Force
    }

    if ($When -eq 'fail') {
        throw "ReleasePublishGuard: $Reason"
    }

    Write-Log -Level "WARN" -Message "  Publish suppressed: $Reason"
}

function Invoke-Plugin {
    param(
        [Parameter(Mandatory = $true)]
        $Settings
    )

    Import-PluginDependency -ModuleName "Logging" -RequiredCommand "Write-Log"
    Import-PluginDependency -ModuleName "PluginSupport" -RequiredCommand "Get-PluginBranches"
    Import-PluginDependency -ModuleName "EngineContext" -RequiredCommand "Set-EngineState"

    Import-PluginDependency -ModuleName "GitTools" -RequiredCommand "Get-GitStatusShort"
    Import-PluginDependency -ModuleName "GitTools" -RequiredCommand "Test-RemoteTagExists"
    Import-PluginDependency -ModuleName "GitTools" -RequiredCommand "Push-TagToRemote"
    Import-PluginDependency -ModuleName "ChangelogSupport" -RequiredCommand "Get-ChangelogSemverPattern"

    $pluginSettings = $Settings
    $shared = $Settings.context
    $when = 'skip'
    if ($null -ne $pluginSettings.whenRequirementsNotMet) {
        $when = [string]$pluginSettings.whenRequirementsNotMet
    }
    if ($when -notin @('skip', 'fail')) {
        throw "ReleasePublishGuard: whenRequirementsNotMet must be 'skip' or 'fail'."
    }

    Set-EngineState -Context $shared -Name 'skipPublishPlugins' -Value $false

    Write-Log -Level "STEP" -Message "Release publish guard..."

    $allowed = @(Get-PluginBranches -Plugin $pluginSettings)
    if ($allowed.Count -gt 0 -and $allowed -notcontains '*' -and $allowed -notcontains $shared.currentBranch) {
        Invoke-NotMetInternal -Shared $shared -When $when -Reason "branch '$($shared.currentBranch)' is not in the guard branches list."
        return
    }

    $requireClean = $false
    if ($null -ne $pluginSettings.requireCleanWorkingTree) {
        $requireClean = [bool]$pluginSettings.requireCleanWorkingTree
    }
    if ($requireClean) {
        $dirtyRaw = Get-GitStatusShort
        if (-not [string]::IsNullOrWhiteSpace([string]$dirtyRaw)) {
            Invoke-NotMetInternal -Shared $shared -When $when -Reason "working tree is not clean (requireCleanWorkingTree is true)."
            return
        }
    }

    $requireTag = $true
    if ($null -ne $pluginSettings.requireExactTagOnHead) {
        $requireTag = [bool]$pluginSettings.requireExactTagOnHead
    }

    $tag = $null
    if ($requireTag) {
        $tag = Get-ExactTagOnHeadSilentlyInternal
        if ([string]::IsNullOrWhiteSpace($tag)) {
            Invoke-NotMetInternal -Shared $shared -When $when -Reason "no exact semver tag on HEAD (git describe --tags --exact-match)."
            return
        }

        $tagPattern = '^v(' + (Get-ChangelogSemverPattern) + ')$'
        if ($tag -notmatch $tagPattern) {
            Invoke-NotMetInternal -Shared $shared -When $when -Reason "tag '$tag' must match vX.Y.Z or vX.Y.Z-prerelease (e.g. v0.1.0-alpha.1, v0.1.0-beta.1, v0.1.0-rc.1)."
            return
        }

        $tagVersion = $Matches[1]
        $mustMatch = $true
        if ($null -ne $pluginSettings.tagVersionMustMatchReleaseVersion) {
            $mustMatch = [bool]$pluginSettings.tagVersionMustMatchReleaseVersion
        }
        elseif ($null -ne $pluginSettings.tagVersionMustMatchNpmRelease) {
            $mustMatch = [bool]$pluginSettings.tagVersionMustMatchNpmRelease
        }
        elseif ($null -ne $pluginSettings.tagVersionMustMatchDotNetRelease) {
            $mustMatch = [bool]$pluginSettings.tagVersionMustMatchDotNetRelease
        }
        if ($mustMatch -and $tagVersion -ne [string]$shared.version) {
            Invoke-NotMetInternal -Shared $shared -When $when -Reason "tag version $tagVersion does not match release version $($shared.version)."
            return
        }

        Set-EngineState -Context $shared -Name 'tag' -Value $tag
    }

    $ensureRemote = $true
    if ($null -ne $pluginSettings.ensureTagOnRemote) {
        $ensureRemote = [bool]$pluginSettings.ensureTagOnRemote
    }
    if ($ensureRemote -and $requireTag -and -not [string]::IsNullOrWhiteSpace($tag)) {
        $remote = 'origin'
        if (-not [string]::IsNullOrWhiteSpace([string]$pluginSettings.remoteName)) {
            $remote = [string]$pluginSettings.remoteName
        }

        Write-Log -Level "STEP" -Message "Verifying tag on remote '$remote'..."
        if (-not (Test-RemoteTagExists -Tag $tag -Remote $remote)) {
            Write-Log -Level "WARN" -Message "  Tag $tag not on remote. Pushing..."
            Push-TagToRemote -Tag $tag -Remote $remote
        }
        else {
            Write-Log -Level "OK" -Message "  Tag exists on remote."
        }
    }

    Write-Log -Level "OK" -Message "  Publish guard passed; publish plugins will run."
}

Export-ModuleMember -Function Invoke-Plugin
