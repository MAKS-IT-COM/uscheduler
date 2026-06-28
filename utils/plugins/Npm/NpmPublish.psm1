#requires -Version 7.0
#requires -PSEdition Core

<#
.SYNOPSIS
    Publishes npm workspace packages to the npm registry.

.DESCRIPTION
    Publishes packages in configured order using an API key from an environment
    variable (for example NPMJS_MAKS_IT). Uses a temporary .npmrc in the
    workspace root for auth and supports --skip-duplicate semantics via npm.
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

    $npmApiKeyEnvVar = $pluginSettings.npmApiKey
    if ([string]::IsNullOrWhiteSpace($npmApiKeyEnvVar)) {
        throw "NpmPublish plugin requires 'npmApiKey' in scriptSettings.json (environment variable name)."
    }

    $npmApiKey = [System.Environment]::GetEnvironmentVariable($npmApiKeyEnvVar)
    if ([string]::IsNullOrWhiteSpace($npmApiKey)) {
        throw "npm API key is not set. Set '$npmApiKeyEnvVar' and rerun."
    }

    $workspaceRoot = $null
    if ($pluginSettings.workspaceRoot) {
        $workspaceRoots = @(Resolve-RelativePaths -Value $pluginSettings.workspaceRoot -BasePath $shared.scriptDir)
        $workspaceRoot = $workspaceRoots[0]
    }
    elseif ($shared.PSObject.Properties['npmWorkspaceRoot'] -and -not [string]::IsNullOrWhiteSpace([string]$shared.npmWorkspaceRoot)) {
        $workspaceRoot = [string]$shared.npmWorkspaceRoot
    }
    else {
        throw "NpmPublish plugin requires 'workspaceRoot' or a prior NpmReleaseVersion plugin run."
    }

    $registry = if ([string]::IsNullOrWhiteSpace([string]$pluginSettings.registry)) {
        'https://registry.npmjs.org'
    }
    else {
        [string]$pluginSettings.registry
    }

    $access = if ([string]::IsNullOrWhiteSpace([string]$pluginSettings.access)) {
        'public'
    }
    else {
        [string]$pluginSettings.access
    }

    $publishOrder = @()
    if ($pluginSettings.publishOrder) {
        if ($pluginSettings.publishOrder -is [System.Collections.IEnumerable] -and -not ($pluginSettings.publishOrder -is [string])) {
            $publishOrder = @($pluginSettings.publishOrder | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
        }
        elseif (-not [string]::IsNullOrWhiteSpace([string]$pluginSettings.publishOrder)) {
            $publishOrder = @([string]$pluginSettings.publishOrder)
        }
    }

    if ($publishOrder.Count -eq 0) {
        throw "NpmPublish plugin requires non-empty 'publishOrder' (workspace package names)."
    }

    $registryHost = ([uri]$registry).Host
    $tempNpmRcPath = Join-Path $workspaceRoot ".npmrc.release-temp"
    $npmRcContent = @"
registry=$registry
//$registryHost/:_authToken=$npmApiKey
"@

    Push-Location $workspaceRoot
    try {
        Set-Content -Path $tempNpmRcPath -Value $npmRcContent -Encoding UTF8 -NoNewline

        foreach ($packageName in $publishOrder) {
            Write-Log -Level "STEP" -Message "Publishing npm package '$packageName'..."
            npm publish -w $packageName --access $access --userconfig $tempNpmRcPath
            if ($LASTEXITCODE -ne 0) {
                throw "Failed to publish npm package '$packageName'."
            }
            Write-Log -Level "OK" -Message "  Published $packageName."
        }

        Write-Log -Level "OK" -Message "  npm publish completed."
        $shared | Add-Member -NotePropertyName publishCompleted -NotePropertyValue $true -Force
    }
    finally {
        if (Test-Path $tempNpmRcPath -PathType Leaf) {
            Remove-Item -Path $tempNpmRcPath -Force -ErrorAction SilentlyContinue
        }
        Pop-Location
    }
}

Export-ModuleMember -Function Invoke-Plugin
