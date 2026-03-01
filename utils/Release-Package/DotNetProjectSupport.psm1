#requires -Version 7.0
#requires -PSEdition Core

if (-not (Get-Command Write-Log -ErrorAction SilentlyContinue)) {
    $loggingModulePath = Join-Path (Split-Path $PSScriptRoot -Parent) "Logging.psm1"
    if (Test-Path $loggingModulePath -PathType Leaf) {
        Import-Module $loggingModulePath -Force
    }
}

if (-not (Get-Command Get-PluginPathListSetting -ErrorAction SilentlyContinue)) {
    $pluginSupportModulePath = Join-Path $PSScriptRoot "PluginSupport.psm1"
    if (Test-Path $pluginSupportModulePath -PathType Leaf) {
        Import-Module $pluginSupportModulePath -Force
    }
}

function Get-DotNetProjectPropertyValue {
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
        return $propNode.$PropertyName
    }

    return $null
}

function Get-DotNetProjectVersions {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$ProjectFiles
    )

    Write-Log -Level "INFO" -Message "Reading version(s) from .NET project files..."
    $projectVersions = @{}

    foreach ($projectPath in $ProjectFiles) {
        if (-not (Test-Path $projectPath -PathType Leaf)) {
            Write-Error "Project file not found at: $projectPath"
            exit 1
        }

        if ([System.IO.Path]::GetExtension($projectPath) -ne ".csproj") {
            Write-Error "Configured project file is not a .csproj file: $projectPath"
            exit 1
        }

        [xml]$csproj = Get-Content $projectPath
        $version = Get-DotNetProjectPropertyValue -Csproj $csproj -PropertyName "Version"

        if (-not $version) {
            Write-Error "Version not found in $projectPath"
            exit 1
        }

        $projectVersions[$projectPath] = $version
        Write-Log -Level "OK" -Message "  $([System.IO.Path]::GetFileName($projectPath)): $version"
    }

    return $projectVersions
}

function New-DotNetReleaseContext {
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$Plugins,

        [Parameter(Mandatory = $true)]
        [string]$ScriptDir
    )

    # The array wrapper is intentional: without it, one configured project can collapse to a string,
    # and later indexing [0] would return only the first character of the path.
    $projectFiles = @(Get-PluginPathListSetting -Plugins $Plugins -PropertyName "projectFiles" -BasePath $ScriptDir)
    $artifactsDirectory = Get-PluginPathSetting -Plugins $Plugins -PropertyName "artifactsDir" -BasePath $ScriptDir

    if ($projectFiles.Count -eq 0) {
        Write-Error "No .NET project files configured in plugin settings. Add 'projectFiles' to a relevant plugin."
        exit 1
    }

    if ([string]::IsNullOrWhiteSpace($artifactsDirectory)) {
        Write-Error "No artifacts directory configured in plugin settings. Add 'artifactsDir' to a relevant plugin."
        exit 1
    }

    $projectVersions = Get-DotNetProjectVersions -ProjectFiles $projectFiles
    # The first configured project is treated as the canonical version source for the release.
    $version = $projectVersions[$projectFiles[0]]

    return [pscustomobject]@{
        ProjectFiles = $projectFiles
        ArtifactsDirectory = $artifactsDirectory
        Version = $version
    }
}

Export-ModuleMember -Function Get-DotNetProjectPropertyValue, Get-DotNetProjectVersions, New-DotNetReleaseContext
