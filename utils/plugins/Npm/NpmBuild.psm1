#requires -Version 7.0
#requires -PSEdition Core

<#
.SYNOPSIS
    Builds an npm workspace (install + build script).

.DESCRIPTION
    Runs npm ci (or npm install when useCi is false) and npm run build in the
    configured workspace root. Requires NpmReleaseVersion to have set
    shared npmWorkspaceRoot unless workspaceRoot is configured explicitly.
#>

if (-not (Get-Command Import-PluginDependency -ErrorAction SilentlyContinue)) {
    $srcDir = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
        $pluginSupportModulePath = Join-Path $srcDir "modules/Engine/PluginSupport.psm1"
    if (Test-Path $pluginSupportModulePath -PathType Leaf) {
        Import-Module $pluginSupportModulePath -Force -Global -ErrorAction Stop
    }
}

function Invoke-Plugin {
    param(
        [Parameter(Mandatory = $true)]
        $Settings
    )

    Import-PluginDependency -ModuleName "Logging" -RequiredCommand "Write-Log"
    Import-PluginDependency -ModuleName "ScriptConfig" -RequiredCommand "Assert-Command"
    Import-PluginDependency -ModuleName "EngineContext" -RequiredCommand "Resolve-RelativePaths"

    $pluginSettings = $Settings
    $shared = $Settings.context

    Assert-Command npm

    $workspaceRoot = $null
    if ($pluginSettings.workspaceRoot) {
        $workspaceRoots = @(Resolve-RelativePaths -Value $pluginSettings.workspaceRoot -BasePath $shared.scriptDir)
        $workspaceRoot = $workspaceRoots[0]
    }
    elseif ($shared.PSObject.Properties['npmWorkspaceRoot'] -and -not [string]::IsNullOrWhiteSpace([string]$shared.npmWorkspaceRoot)) {
        $workspaceRoot = [string]$shared.npmWorkspaceRoot
    }
    else {
        throw "NpmBuild plugin requires 'workspaceRoot' or a prior NpmReleaseVersion plugin run."
    }

    $useCi = $true
    if ($null -ne $pluginSettings.useCi) {
        $useCi = [bool]$pluginSettings.useCi
    }

    $buildScript = 'build'
    if (-not [string]::IsNullOrWhiteSpace([string]$pluginSettings.buildScript)) {
        $buildScript = [string]$pluginSettings.buildScript
    }

    Push-Location $workspaceRoot
    try {
        if ($useCi) {
            Write-Log -Level "STEP" -Message "Running npm ci in '$workspaceRoot'..."
            npm ci
            if ($LASTEXITCODE -ne 0) {
                throw "npm ci failed with exit code $LASTEXITCODE."
            }
        }
        else {
            Write-Log -Level "STEP" -Message "Running npm install in '$workspaceRoot'..."
            npm install
            if ($LASTEXITCODE -ne 0) {
                throw "npm install failed with exit code $LASTEXITCODE."
            }
        }

        Write-Log -Level "STEP" -Message "Running npm run $buildScript..."
        npm run $buildScript
        if ($LASTEXITCODE -ne 0) {
            throw "npm run $buildScript failed with exit code $LASTEXITCODE."
        }

        Write-Log -Level "OK" -Message "  npm build completed."
    }
    finally {
        Pop-Location
    }
}

Export-ModuleMember -Function Invoke-Plugin
