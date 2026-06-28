#requires -Version 7.0
#requires -PSEdition Core

<#
.SYNOPSIS
    Loads npm workspace release version into shared context.

.DESCRIPTION
    Reads semver from the configured workspace package.json and writes it to
    shared context version. Optionally synchronizes version fields across
    workspace package manifests before build/publish.
#>

if (-not (Get-Command Import-PluginDependency -ErrorAction SilentlyContinue)) {
    $srcDir = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
        $pluginSupportModulePath = Join-Path $srcDir "modules/Engine/PluginSupport.psm1"
    if (Test-Path $pluginSupportModulePath -PathType Leaf) {
        Import-Module $pluginSupportModulePath -Force -Global -ErrorAction Stop
    }
}

function Get-PackageJsonVersionInternal {
    param(
        [Parameter(Mandatory = $true)]
        [string]$PackageJsonPath
    )

    if (-not (Test-Path $PackageJsonPath -PathType Leaf)) {
        throw "NpmReleaseVersion: package.json not found at '$PackageJsonPath'."
    }

    $json = Get-Content -Path $PackageJsonPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $version = [string]$json.version
    if ([string]::IsNullOrWhiteSpace($version)) {
        throw "NpmReleaseVersion: 'version' is missing in '$PackageJsonPath'."
    }

    if ($version -notmatch '^\d+\.\d+\.\d+') {
        throw "NpmReleaseVersion: version '$version' in '$PackageJsonPath' is not a valid semver."
    }

    return $version
}

function Set-PackageJsonVersionInternal {
    param(
        [Parameter(Mandatory = $true)]
        [string]$PackageJsonPath,

        [Parameter(Mandatory = $true)]
        [string]$Version
    )

    $raw = Get-Content -Path $PackageJsonPath -Raw -Encoding UTF8
    $json = $raw | ConvertFrom-Json
    $json.version = $Version
    ($json | ConvertTo-Json -Depth 100) + [Environment]::NewLine | Set-Content -Path $PackageJsonPath -Encoding UTF8 -NoNewline
}

function Invoke-Plugin {
    param(
        [Parameter(Mandatory = $true)]
        $Settings
    )

    Import-PluginDependency -ModuleName "Logging" -RequiredCommand "Write-Log"
    Import-PluginDependency -ModuleName "EngineContext" -RequiredCommand "Resolve-RelativePaths"

    $pluginSettings = $Settings
    $shared = $Settings.context

    $packageJsonPaths = @(Resolve-RelativePaths -Value $pluginSettings.packageJsonPath -BasePath $shared.scriptDir)
    if ($packageJsonPaths.Count -eq 0) {
        throw "NpmReleaseVersion plugin requires 'packageJsonPath' in scriptSettings.json."
    }
    $packageJsonPath = $packageJsonPaths[0]

    $version = Get-PackageJsonVersionInternal -PackageJsonPath $packageJsonPath
    $syncWorkspaceVersions = $false
    if ($null -ne $pluginSettings.syncWorkspaceVersions) {
        $syncWorkspaceVersions = [bool]$pluginSettings.syncWorkspaceVersions
    }

    if ($syncWorkspaceVersions) {
        $workspaceRoot = Split-Path -Parent $packageJsonPath
        $packageManifests = Get-ChildItem -Path (Join-Path $workspaceRoot 'packages') -Recurse -Filter package.json -File -ErrorAction SilentlyContinue
        foreach ($manifest in $packageManifests) {
            Set-PackageJsonVersionInternal -PackageJsonPath $manifest.FullName -Version $version
        }
        Write-Log -Level "OK" -Message "  Synchronized workspace package versions to $version."
    }

    $shared | Add-Member -NotePropertyName version -NotePropertyValue $version -Force
    $shared | Add-Member -NotePropertyName npmWorkspaceRoot -NotePropertyValue (Split-Path -Parent $packageJsonPath) -Force
    $shared | Add-Member -NotePropertyName npmPackageJsonPath -NotePropertyValue $packageJsonPath -Force
    Write-Log -Level "OK" -Message "  Release version loaded by NpmReleaseVersion plugin: $version"
}

Export-ModuleMember -Function Invoke-Plugin
