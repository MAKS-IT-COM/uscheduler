#requires -Version 7.0
#requires -PSEdition Core

<#
.SYNOPSIS
    Packs npm workspace packages into .tgz release artifacts.

.DESCRIPTION
    Runs npm pack for each configured workspace package and publishes the
    resulting tarball paths into shared release context (releaseAssetPaths)
    for the GitHub release plugin.
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
    Import-PluginDependency -ModuleName "EngineContext" -RequiredCommand "Set-EngineFact"

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
        throw "NpmPack plugin requires 'workspaceRoot' or a prior NpmReleaseVersion plugin run."
    }

    $artifactsDirectory = $null
    if ($pluginSettings.PSObject.Properties['artifactsDir'] -and -not [string]::IsNullOrWhiteSpace([string]$pluginSettings.artifactsDir)) {
        $artifactsDirectory = [System.IO.Path]::GetFullPath((Join-Path $shared.scriptDir ([string]$pluginSettings.artifactsDir)))
        Set-EngineState -Context $shared -Name 'artifactsDirectory' -Value $artifactsDirectory
    }
    elseif ($shared.PSObject.Properties['artifactsDirectory'] -and -not [string]::IsNullOrWhiteSpace([string]$shared.artifactsDirectory)) {
        $artifactsDirectory = [string]$shared.artifactsDirectory
    }
    else {
        throw "NpmPack plugin requires release-stage artifactsDirectory."
    }

    $packOrder = @()
    if ($pluginSettings.publishOrder) {
        if ($pluginSettings.publishOrder -is [System.Collections.IEnumerable] -and -not ($pluginSettings.publishOrder -is [string])) {
            $packOrder = @($pluginSettings.publishOrder | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
        }
        elseif (-not [string]::IsNullOrWhiteSpace([string]$pluginSettings.publishOrder)) {
            $packOrder = @([string]$pluginSettings.publishOrder)
        }
    }
    elseif ($pluginSettings.packOrder) {
        if ($pluginSettings.packOrder -is [System.Collections.IEnumerable] -and -not ($pluginSettings.packOrder -is [string])) {
            $packOrder = @($pluginSettings.packOrder | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
        }
        elseif (-not [string]::IsNullOrWhiteSpace([string]$pluginSettings.packOrder)) {
            $packOrder = @([string]$pluginSettings.packOrder)
        }
    }

    if ($packOrder.Count -eq 0) {
        throw "NpmPack plugin requires non-empty 'publishOrder' or 'packOrder' (workspace package names)."
    }

    Import-Module (Join-Path $PSScriptRoot 'NpmPackageSupport.psm1') -Force
    $useWorkspaces = Test-NpmWorkspacesConfigured -WorkspaceRoot $workspaceRoot
    if (-not $useWorkspaces -and $packOrder.Count -gt 1) {
        throw "NpmPack plugin requires npm workspaces when packing more than one package."
    }

    if (-not (Test-Path $artifactsDirectory -PathType Container)) {
        New-Item -ItemType Directory -Path $artifactsDirectory | Out-Null
    }

    $releaseAssetPaths = @()

    Push-Location $workspaceRoot
    try {
        foreach ($packageName in $packOrder) {
            Write-Log -Level "STEP" -Message "Packing npm package '$packageName'..."
            if ($useWorkspaces) {
                $tarballName = (npm pack -w $packageName --pack-destination $artifactsDirectory 2>$null | Select-Object -Last 1)
            }
            else {
                Assert-NpmRootPackageName -WorkspaceRoot $workspaceRoot -ExpectedPackageName $packageName
                $tarballName = (npm pack --pack-destination $artifactsDirectory 2>$null | Select-Object -Last 1)
            }

            if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace([string]$tarballName)) {
                throw "npm pack failed for '$packageName'."
            }

            $tarballPath = Join-Path $artifactsDirectory ([string]$tarballName).Trim()
            if (-not (Test-Path $tarballPath -PathType Leaf)) {
                throw "Could not locate pack output for '$packageName' at: $tarballPath"
            }

            $strayTarballPath = Join-Path $workspaceRoot ([string]$tarballName).Trim()
            if ((Test-Path $strayTarballPath -PathType Leaf) -and $strayTarballPath -ne $tarballPath) {
                Remove-Item -LiteralPath $strayTarballPath -Force -ErrorAction SilentlyContinue
            }

            Write-Log -Level "OK" -Message "  Package ready: $tarballPath"
            $releaseAssetPaths += $tarballPath
        }
    }
    finally {
        Pop-Location
    }

    Set-EngineState -Context $shared -Name 'releaseDir' -Value $artifactsDirectory
    Set-EngineFact -Context $shared -Namespace 'release' -Name 'assetPaths' -Value $releaseAssetPaths -Overwrite Replace -LegacyProperty 'releaseAssetPaths'
    if ($releaseAssetPaths.Count -gt 0) {
        $packageItem = Get-Item -LiteralPath $releaseAssetPaths[0]
        Set-EngineFact -Context $shared -Namespace 'npm' -Name 'packageFile' -Value $packageItem -Overwrite Replace -LegacyProperty 'packageFile'
    }

    Write-Log -Level "OK" -Message "  npm pack completed ($($releaseAssetPaths.Count) tarball(s))."
}

Export-ModuleMember -Function Invoke-Plugin
