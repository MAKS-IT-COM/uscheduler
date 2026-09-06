#requires -Version 7.0
#requires -PSEdition Core

<#
.SYNOPSIS
    Publishes npm workspace packages to the npm registry.

.DESCRIPTION
    Publishes packages in configured order using RepoUtilsSecrets slot Npm.
    Uses a temporary .npmrc in the workspace root.
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
    Import-PluginDependency -ModuleName "ChangelogSupport" -RequiredCommand "Get-ReleaseSemverPrereleaseLabel"

    $pluginSettings = $Settings
    $shared = $Settings.context

    $dryRun = Test-PluginSkipsRemoteMutation -Plugin $pluginSettings -SharedSettings $shared

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

    $npmDistTag = $null
    if (-not [string]::IsNullOrWhiteSpace([string]$pluginSettings.npmDistTag)) {
        $npmDistTag = [string]$pluginSettings.npmDistTag
    }
    else {
        $npmDistTag = Get-ReleaseSemverPrereleaseLabel -Version ([string]$shared.version)
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

    $npmSecret = Resolve-PluginSecretName -PluginSettings $pluginSettings -PropertyName 'npmSecret' -PluginDisplayName 'NpmPublish' -Required

    Import-Module (Join-Path $PSScriptRoot 'NpmPackageSupport.psm1') -Force
    $useWorkspaces = Test-NpmWorkspacesConfigured -WorkspaceRoot $workspaceRoot
    if (-not $useWorkspaces -and $publishOrder.Count -gt 1) {
        throw "NpmPublish plugin requires npm workspaces when publishing more than one package."
    }

    if ($dryRun) {
        foreach ($packageName in $publishOrder) {
            $tagNote = if ([string]::IsNullOrWhiteSpace($npmDistTag)) { 'latest' } else { $npmDistTag }
            Write-Log -Level "INFO" -Message "Dry run: would publish npm package '$packageName' to $registry (dist-tag $tagNote)"
        }
        return
    }

    $npmToken = Get-RepoUtilsSecretSlot -Name $npmSecret -Settings $shared
    if ([string]::IsNullOrWhiteSpace($npmToken)) {
        throw "npm API key is not set. Set RepoUtilsSecrets slot '$npmSecret' (npmSecret)."
    }

    $registryHost = ([uri]$registry).Host
    $tempNpmRcPath = Join-Path $workspaceRoot ".npmrc.release-temp"
    $npmRcContent = @"
registry=$registry
//$registryHost/:_authToken=$npmToken
"@

    Push-Location $workspaceRoot
    try {
        Set-Content -Path $tempNpmRcPath -Value $npmRcContent -Encoding UTF8 -NoNewline

        foreach ($packageName in $publishOrder) {
            Write-Log -Level "STEP" -Message "Publishing npm package '$packageName'..."
            $publishArgs = @('publish')
            if ($useWorkspaces) {
                $publishArgs += @('-w', $packageName)
            }
            else {
                Assert-NpmRootPackageName -WorkspaceRoot $workspaceRoot -ExpectedPackageName $packageName
            }
            $publishArgs += @('--access', $access, '--userconfig', $tempNpmRcPath)
            if (-not [string]::IsNullOrWhiteSpace($npmDistTag)) {
                $publishArgs += @('--tag', $npmDistTag)
                Write-Log -Level "INFO" -Message "  Using npm dist-tag '$npmDistTag' (prerelease)."
            }

            npm @publishArgs

            if ($LASTEXITCODE -ne 0) {
                throw "Failed to publish npm package '$packageName'."
            }
            Write-Log -Level "OK" -Message "  Published $packageName."
        }

        Write-Log -Level "OK" -Message "  npm publish completed."
        Import-PluginDependency -ModuleName "EngineContext" -RequiredCommand "Add-EnginePublishCompletion"
        Add-EnginePublishCompletion -Context $shared -Publisher 'NpmPublish'
    }
    finally {
        if (Test-Path $tempNpmRcPath -PathType Leaf) {
            Remove-Item -Path $tempNpmRcPath -Force -ErrorAction SilentlyContinue
        }
        Pop-Location
    }
}

function Get-PluginMetadata {
    [pscustomobject]@{ mutatesRemote = $true }
}

Export-ModuleMember -Function Invoke-Plugin, Get-PluginMetadata
