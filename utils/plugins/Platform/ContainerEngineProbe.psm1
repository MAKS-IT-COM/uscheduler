#requires -Version 7.0
#requires -PSEdition Core

<#
.SYNOPSIS
    Probes docker/podman availability and sets mandatory shared engine state for the pipeline.

.DESCRIPTION
    Must be the first enabled plugin. Sets containerEngineProbeCompleted, activeContainerEngine,
    dockerEngineAvailable, podmanEngineAvailable, and compose CLI fields on shared context.
    Fails the pipeline when no usable engine is found.
#>

if (-not (Get-Command Import-PluginDependency -ErrorAction SilentlyContinue)) {
    $srcDir = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    $pluginSupportModulePath = Join-Path $srcDir 'modules/Engine/PluginSupport.psm1'
    if (Test-Path $pluginSupportModulePath -PathType Leaf) {
        Import-Module $pluginSupportModulePath -Force -Global -ErrorAction Stop
    }
}

function Invoke-Plugin {
    param(
        [Parameter(Mandatory = $true)]
        $Settings
    )

    Import-PluginDependency -ModuleName 'Logging' -RequiredCommand 'Write-Log'
    Import-PluginDependency -ModuleName 'ContainerEngineSupport' -RequiredCommand 'Resolve-ActiveContainerEngineState'

    $shared = $Settings.context

    Write-Log -Level 'STEP' -Message 'Probing container engine availability...'
    $state = Resolve-ActiveContainerEngineState
    Set-ContainerEngineSharedState -SharedSettings $shared -State $state

    $display = Get-ContainerEngineDisplayName -Engine (Get-SharedContainerEngineInvocation -SharedSettings $shared)
    Write-Log -Level 'OK' -Message "  Active engine: $display"
    Write-Log -Level 'INFO' -Message "  docker CLI available: $($state.DockerEngineAvailable); podman CLI available: $($state.PodmanEngineAvailable)"
    if ([string]::IsNullOrWhiteSpace([string]$state.ComposeExecutable)) {
        Write-Log -Level 'INFO' -Message '  Compose CLI: not available (Compose plugins will fail if enabled).'
    }
    else {
        Write-Log -Level 'INFO' -Message "  Compose CLI: $($state.ComposeExecutable) $($state.ComposeBaseArgs -join ' ')"
    }
}

function Get-PluginMetadata {
    [pscustomobject]@{ mutatesRemote = $false }
}

Export-ModuleMember -Function Invoke-Plugin, Get-PluginMetadata
