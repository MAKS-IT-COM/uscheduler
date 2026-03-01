#requires -Version 7.0
#requires -PSEdition Core

<#
.SYNOPSIS
    Plugin-driven release engine.

.DESCRIPTION
    This script is the orchestration layer for release automation.
    It loads scriptsettings.json, evaluates the configured plugins in order,
    builds shared execution context, and invokes each plugin's Invoke-Plugin
    entrypoint with that plugin's own settings object plus runtime context.

    The engine is intentionally generic:
    - It does not embed release-provider-specific logic
    - It preserves plugin execution order from scriptsettings.json
    - It isolates plugin failures according to the stage/runtime policy
    - It keeps shared orchestration helpers in dedicated support modules

.REQUIREMENTS
    Tools (Required):
    - Shared support modules required by the engine
    - Any commands required by configured plugins or support helpers

.WORKFLOW
    1. Load and normalize plugin configuration
    2. Determine branch mode from configured plugin metadata
    3. Validate repository state and resolve the release version
    4. Build shared execution context
    5. Execute plugins one by one in configured order
    6. Initialize release-stage shared artifacts only when needed
    7. Report completion summary

.USAGE
    Configure plugin order and plugin settings in scriptsettings.json, then run:
        pwsh -File .\Release-Package.ps1

.CONFIGURATION
    All settings are stored in scriptsettings.json:
    - Plugins: Ordered plugin definitions and plugin-specific settings

.NOTES
    Plugin-specific behavior belongs in the plugin modules, not in this engine.
#>

# No parameters - behavior is controlled by configured plugin metadata:
# - non-release branches -> Run only the plugins allowed for those branches
# - release branches     -> Require a matching tag and allow release-stage plugins

# Get the directory of the current script (for loading settings and relative paths)
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

#region Import Modules

$utilsDir = Split-Path $scriptDir -Parent

# Import ScriptConfig module
$scriptConfigModulePath = Join-Path $utilsDir "ScriptConfig.psm1"
if (-not (Test-Path $scriptConfigModulePath)) {
    Write-Error "ScriptConfig module not found at: $scriptConfigModulePath"
    exit 1
}

Import-Module $scriptConfigModulePath -Force

# Import Logging module
$loggingModulePath = Join-Path $utilsDir "Logging.psm1"
if (-not (Test-Path $loggingModulePath)) {
    Write-Error "Logging module not found at: $loggingModulePath"
    exit 1
}

Import-Module $loggingModulePath -Force
# Import PluginSupport module
$pluginSupportModulePath = Join-Path $scriptDir "PluginSupport.psm1"
if (-not (Test-Path $pluginSupportModulePath)) {
    Write-Error "PluginSupport module not found at: $pluginSupportModulePath"
    exit 1
}

Import-Module $pluginSupportModulePath -Force

# Import DotNetProjectSupport module
$dotNetProjectSupportModulePath = Join-Path $scriptDir "DotNetProjectSupport.psm1"
if (-not (Test-Path $dotNetProjectSupportModulePath)) {
    Write-Error "DotNetProjectSupport module not found at: $dotNetProjectSupportModulePath"
    exit 1
}

Import-Module $dotNetProjectSupportModulePath -Force

# Import EngineSupport module
$engineSupportModulePath = Join-Path $scriptDir "EngineSupport.psm1"
if (-not (Test-Path $engineSupportModulePath)) {
    Write-Error "EngineSupport module not found at: $engineSupportModulePath"
    exit 1
}

Import-Module $engineSupportModulePath -Force

#endregion

#region Load Settings
$settings = Get-ScriptSettings -ScriptDir $scriptDir
$configuredPlugins = Get-ConfiguredPlugins -Settings $settings

#endregion

#region Configuration

$pluginsDir = Join-Path $scriptDir "CorePlugins"

#endregion

#endregion

#region Main

Write-Log -Level "STEP" -Message "=================================================="
Write-Log -Level "STEP" -Message "RELEASE ENGINE"
Write-Log -Level "STEP" -Message "=================================================="

#region Preflight

$plugins = $configuredPlugins
$engineContext = New-EngineContext -Plugins $plugins -ScriptDir $scriptDir -UtilsDir $utilsDir
Write-Log -Level "OK" -Message "All pre-flight checks passed!"
$sharedPluginSettings = $engineContext

#endregion

#region Plugin Execution

$releaseStageInitialized = $false

if ($plugins.Count -eq 0) {
    Write-Log -Level "WARN" -Message "No plugins configured in scriptsettings.json."
}
else {
    for ($pluginIndex = 0; $pluginIndex -lt $plugins.Count; $pluginIndex++) {
        $plugin = $plugins[$pluginIndex]
        $pluginStage = Get-PluginStage -Plugin $plugin

        if ((Test-IsPublishPlugin -Plugin $plugin) -and -not $releaseStageInitialized) {
            if (Test-PluginRunnable -Plugin $plugin -SharedSettings $sharedPluginSettings -PluginsDirectory $pluginsDir -WriteLogs:$false) {
                $remainingPlugins = @($plugins[$pluginIndex..($plugins.Count - 1)])
                Initialize-ReleaseStageContext -RemainingPlugins $remainingPlugins -SharedSettings $sharedPluginSettings -ArtifactsDirectory $engineContext.ArtifactsDirectory -Version $engineContext.Version
                $releaseStageInitialized = $true
            }
        }

        $continueOnError = $pluginStage -eq "Release"
        Invoke-ConfiguredPlugin -Plugin $plugin -SharedSettings $sharedPluginSettings -PluginsDirectory $pluginsDir -ContinueOnError:$continueOnError
    }
}

if (-not $releaseStageInitialized) {
    $noReleasePluginsLogLevel = if ($engineContext.IsNonReleaseBranch) { "INFO" } else { "WARN" }
    Write-Log -Level $noReleasePluginsLogLevel -Message "No release plugins executed for branch '$($engineContext.CurrentBranch)'."
}

#endregion

#region Summary
Write-Log -Level "OK" -Message "=================================================="
if ($engineContext.IsNonReleaseBranch) {
    Write-Log -Level "OK" -Message "NON-RELEASE RUN COMPLETE"
}
else {
    Write-Log -Level "OK" -Message "RELEASE COMPLETE"
}
Write-Log -Level "OK" -Message "=================================================="

Write-Log -Level "INFO" -Message "Artifacts location: $($engineContext.ArtifactsDirectory)"

if ($engineContext.IsNonReleaseBranch) {
    $preferredReleaseBranch = Get-PreferredReleaseBranch -EngineContext $engineContext
    Write-Log -Level "INFO" -Message "To execute release-stage plugins, rerun from an allowed release branch such as '$preferredReleaseBranch'."
}

#endregion

#endregion
