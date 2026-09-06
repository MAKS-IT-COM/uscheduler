#requires -Version 7.0
#requires -PSEdition Core

<#
.SYNOPSIS
    Loads release version from an SDK-style .csproj into shared context.

.DESCRIPTION
    Dedicated version-loading plugin. Reads <Version> from the first configured
    projectFiles .csproj, or from the nearest Directory.Build.props when the
    csproj omits it. Accepts SemVer prerelease (0.1.0-alpha.1 / beta / rc). Writes
    version plus the resolved projectFiles (csproj paths for later pack/publish)
    to the shared runtime context. Declares providesVersion = $true so the engine
    can discover it as the single release version source.
#>

if (-not (Get-Command Import-PluginDependency -ErrorAction SilentlyContinue)) {
    $srcDir = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
        $pluginSupportModulePath = Join-Path $srcDir "modules/Engine/PluginSupport.psm1"
    if (Test-Path $pluginSupportModulePath -PathType Leaf) {
        Import-Module $pluginSupportModulePath -Force -Global -ErrorAction Stop
    }
}

function ConvertTo-MsbuildPropertyStringInternal {
    param(
        $Value
    )

    if ($null -eq $Value) {
        return $null
    }

    if ($Value -is [System.Xml.XmlElement]) {
        return [string]$Value.InnerText
    }

    return [string]$Value
}

function Get-CsprojPropertyValueInternal {
    param(
        [Parameter(Mandatory = $true)]
        [xml]$Csproj,

        [Parameter(Mandatory = $true)]
        [string]$PropertyName
    )

    # SDK-style .csproj files can have multiple PropertyGroup nodes.
    # Use the first group that defines the requested property.
    $propNode = $Csproj.Project.PropertyGroup |
        Where-Object { $_.$PropertyName } |
        Select-Object -First 1

    if ($propNode) {
        return ConvertTo-MsbuildPropertyStringInternal -Value $propNode.$PropertyName
    }

    return $null
}

function Get-DirectoryBuildPropsVersionInternal {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProjectPath
    )

    # MSBuild uses the first Directory.Build.props found walking up from the project directory.
    $dir = [System.IO.Path]::GetDirectoryName((Resolve-Path -LiteralPath $ProjectPath))
    while (-not [string]::IsNullOrWhiteSpace($dir)) {
        $propsPath = Join-Path $dir 'Directory.Build.props'
        if (Test-Path -LiteralPath $propsPath -PathType Leaf) {
            [xml]$props = Get-Content -LiteralPath $propsPath
            return Get-CsprojPropertyValueInternal -Csproj $props -PropertyName 'Version'
        }

        $parent = [System.IO.Directory]::GetParent($dir)
        if ($null -eq $parent) {
            break
        }

        $dir = $parent.FullName
    }

    return $null
}

function Get-CsprojVersionInternal {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProjectPath
    )

    if (-not (Test-Path $ProjectPath -PathType Leaf)) {
        throw "DotNetReleaseVersion: project file not found at '$ProjectPath'."
    }

    if ([System.IO.Path]::GetExtension($ProjectPath) -ne ".csproj") {
        throw "DotNetReleaseVersion: configured project file is not a .csproj file: '$ProjectPath'."
    }

    [xml]$csproj = Get-Content $ProjectPath
    $version = Get-CsprojPropertyValueInternal -Csproj $csproj -PropertyName "Version"
    if (-not [string]::IsNullOrWhiteSpace([string]$version)) {
        return [string]$version
    }

    $version = Get-DirectoryBuildPropsVersionInternal -ProjectPath $ProjectPath
    if (-not [string]::IsNullOrWhiteSpace([string]$version)) {
        return [string]$version
    }

    throw "DotNetReleaseVersion: <Version> not found in '$ProjectPath' or a parent Directory.Build.props."
}

function Get-PluginMetadata {
    return [pscustomobject]@{ providesVersion = $true }
}

function Invoke-Plugin {
    param(
        [Parameter(Mandatory = $true)]
        $Settings
    )

    Import-PluginDependency -ModuleName "Logging" -RequiredCommand "Write-Log"
    Import-PluginDependency -ModuleName "EngineContext" -RequiredCommand "Set-EngineState"

    $shared = $Settings.context
    $projectFiles = @(Resolve-RelativePaths -Value $Settings.projectFiles -BasePath $shared.scriptDir)
    if ($projectFiles.Count -eq 0) {
        throw "DotNetReleaseVersion plugin requires 'projectFiles' (first .csproj with <Version>) in scriptSettings.json."
    }

    Write-Log -Level "INFO" -Message "Reading version from SDK-style project file (projectFiles)..."
    $version = Get-CsprojVersionInternal -ProjectPath $projectFiles[0]
    Import-PluginDependency -ModuleName "ChangelogSupport" -RequiredCommand "Test-ReleaseSemver"
    if (-not (Test-ReleaseSemver -Version $version)) {
        throw "DotNetReleaseVersion: version '$version' is not a valid semver (X.Y.Z or X.Y.Z-prerelease)."
    }

    Set-EngineState -Context $shared -Name 'version' -Value $version
    Set-EngineFact -Context $shared -Namespace 'dotnet' -Name 'projectFiles' -Value $projectFiles -Overwrite Replace -LegacyProperty 'projectFiles'
    Write-Log -Level "OK" -Message "  Release version loaded by DotNetReleaseVersion plugin: $version"
}

Export-ModuleMember -Function Invoke-Plugin, Get-PluginMetadata
