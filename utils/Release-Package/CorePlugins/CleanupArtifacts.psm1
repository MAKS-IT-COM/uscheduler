#requires -Version 7.0
#requires -PSEdition Core

<#
.SYNOPSIS
    Cleanup plugin for removing generated artifacts after pipeline completion.

.DESCRIPTION
    This plugin removes files from the configured artifacts directory using
    glob patterns. It is typically placed at the end of the Release stage so
    cleanup becomes explicit and opt-in per repository.
#>

if (-not (Get-Command Import-PluginDependency -ErrorAction SilentlyContinue)) {
    $pluginSupportModulePath = Join-Path (Split-Path $PSScriptRoot -Parent) "PluginSupport.psm1"
    if (Test-Path $pluginSupportModulePath -PathType Leaf) {
        Import-Module $pluginSupportModulePath -Force -Global -ErrorAction Stop
    }
}

function Get-CleanupPatternsInternal {
    param(
        [Parameter(Mandatory = $false)]
        $ConfiguredPatterns
    )

    if ($null -eq $ConfiguredPatterns) {
        return @('*.nupkg', '*.snupkg')
    }

    if ($ConfiguredPatterns -is [System.Collections.IEnumerable] -and -not ($ConfiguredPatterns -is [string])) {
        return @($ConfiguredPatterns | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
    }

    if ([string]::IsNullOrWhiteSpace([string]$ConfiguredPatterns)) {
        return @('*.nupkg', '*.snupkg')
    }

    return @([string]$ConfiguredPatterns)
}

function Get-ExcludePatternsInternal {
    param(
        [Parameter(Mandatory = $false)]
        $ConfiguredPatterns
    )

    if ($null -eq $ConfiguredPatterns) {
        return @()
    }

    if ($ConfiguredPatterns -is [System.Collections.IEnumerable] -and -not ($ConfiguredPatterns -is [string])) {
        return @($ConfiguredPatterns | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
    }

    if ([string]::IsNullOrWhiteSpace([string]$ConfiguredPatterns)) {
        return @()
    }

    return @([string]$ConfiguredPatterns)
}

function Invoke-Plugin {
    param(
        [Parameter(Mandatory = $true)]
        $Settings
    )

    Import-PluginDependency -ModuleName "Logging" -RequiredCommand "Write-Log"

    $pluginSettings = $Settings
    $sharedSettings = $Settings.Context
    $artifactsDirectory = $sharedSettings.ArtifactsDirectory
    $patterns = Get-CleanupPatternsInternal -ConfiguredPatterns $pluginSettings.includePatterns
    $excludePatterns = Get-ExcludePatternsInternal -ConfiguredPatterns $pluginSettings.excludePatterns

    if ([string]::IsNullOrWhiteSpace($artifactsDirectory)) {
        throw "CleanupArtifacts plugin requires an artifacts directory in the shared context."
    }

    if (-not (Test-Path $artifactsDirectory -PathType Container)) {
        Write-Log -Level "WARN" -Message "  Artifacts directory not found: $artifactsDirectory"
        return
    }

    Write-Log -Level "STEP" -Message "Cleaning generated artifacts..."

    $itemsToRemove = @()
    foreach ($pattern in $patterns) {
        $matchedItems = @(
            Get-ChildItem -Path $artifactsDirectory -Force -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -like $pattern }
        )

        if ($excludePatterns.Count -gt 0) {
            $matchedItems = @(
                $matchedItems |
                    Where-Object {
                        $item = $_
                        -not ($excludePatterns | Where-Object { $item.Name -like $_ } | Select-Object -First 1)
                    }
            )
        }

        $itemsToRemove += @($matchedItems)
    }

    $itemsToRemove = @($itemsToRemove | Sort-Object FullName -Unique)

    if ($itemsToRemove.Count -eq 0) {
        Write-Log -Level "INFO" -Message "  No artifacts matched cleanup rules."
        return
    }

    foreach ($item in $itemsToRemove) {
        Remove-Item -Path $item.FullName -Recurse -Force -ErrorAction SilentlyContinue
        Write-Log -Level "OK" -Message "  Removed: $($item.Name)"
    }
}

Export-ModuleMember -Function Invoke-Plugin
