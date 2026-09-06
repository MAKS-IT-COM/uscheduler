#requires -Version 7.0
#requires -PSEdition Core

function Get-RepoUtilsSrcDirectory {
    return (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent)
}

function Get-RepoUtilsModulesDirectory {
    return Split-Path $PSScriptRoot -Parent
}

if (-not (Get-Command Write-Log -ErrorAction SilentlyContinue)) {
    $loggingModulePath = Join-Path (Get-RepoUtilsModulesDirectory) "Logging.psm1"
    if (Test-Path $loggingModulePath -PathType Leaf) {
        Import-Module $loggingModulePath -Force
    }
}

function Test-IsEngineRuntimeModuleName {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ModuleName
    )

    # Host engine runtime under modules/ (and optional modules/Extensions/) — never dual-homed under plugins/.
    $engineNames = [System.Collections.Generic.HashSet[string]]::new(
        [string[]]@(
            'ChangelogSupport',
            'ExternalCommandSupport',
            'GitTools',
            'Logging',
            'ScriptConfig',
            'TestRunner',
            'EngineContext',
            'PluginSupport',
            'VaultSupport',
            'ReleaseSupport',
            'TestSupport'
        ),
        [System.StringComparer]::OrdinalIgnoreCase
    )

    return $engineNames.Contains($ModuleName)
}

function Get-PluginDependencyGroupDirectories {
    param(
        [Parameter(Mandatory = $true)]
        [string]$PluginsRoot
    )

    if (-not (Test-Path -LiteralPath $PluginsRoot -PathType Container)) {
        return @()
    }

    # Prefer Shared (helpers), then stock host groups; any other plugins/{Group}/ is discovered.
    $preferred = @('Shared', 'Platform', 'DotNet', 'Npm', 'Desktop')
    $dirs = [System.Collections.Generic.List[string]]::new()
    foreach ($name in $preferred) {
        $path = Join-Path $PluginsRoot $name
        if (Test-Path -LiteralPath $path -PathType Container) {
            $dirs.Add($path)
        }
    }

    Get-ChildItem -LiteralPath $PluginsRoot -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -notin $preferred } |
        Sort-Object Name |
        ForEach-Object { $dirs.Add($_.FullName) }

    return @($dirs)
}

function Import-PluginDependency {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ModuleName,

        [Parameter(Mandatory = $true)]
        [string]$RequiredCommand
    )

    if (Get-Command $RequiredCommand -ErrorAction SilentlyContinue) {
        return
    }

    $modulesDir = Get-RepoUtilsModulesDirectory
    $engineModuleDir = $PSScriptRoot
    $srcDir = Get-RepoUtilsSrcDirectory
    $pluginsRoot = Join-Path $srcDir 'plugins'
    $candidatePaths = [System.Collections.Generic.List[string]]::new()

    if (Test-IsEngineRuntimeModuleName -ModuleName $ModuleName) {
        # Engine runtime: modules/ only (no plugins/ fallback). Optional Extensions/ for layered hosts.
        $candidatePaths.Add((Join-Path $modulesDir "$ModuleName.psm1"))
        $candidatePaths.Add((Join-Path $engineModuleDir "$ModuleName.psm1"))
        $extensionsDir = Join-Path $modulesDir 'Extensions'
        $candidatePaths.Add((Join-Path $extensionsDir "$ModuleName.psm1"))
    }
    else {
        # Plugin helpers: plugins/{Group}/ only (no modules/ legacy shadow). Groups are discovered.
        foreach ($groupDir in Get-PluginDependencyGroupDirectories -PluginsRoot $pluginsRoot) {
            $candidatePaths.Add((Join-Path $groupDir "$ModuleName.psm1"))
        }
    }

    foreach ($modulePath in $candidatePaths) {
        if (Test-Path -LiteralPath $modulePath -PathType Leaf) {
            Import-Module $modulePath -Force -Global -ErrorAction Stop
            break
        }
    }

    if (-not (Get-Command $RequiredCommand -ErrorAction SilentlyContinue)) {
        throw "Required command '$RequiredCommand' is still unavailable after importing module '$ModuleName'."
    }
}

function Get-ConfiguredPlugins {
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$Settings
    )

    if (-not $Settings.PSObject.Properties['plugins'] -or $null -eq $Settings.plugins) {
        return @()
    }

    if ($Settings.plugins -is [System.Collections.IEnumerable] -and -not ($Settings.plugins -is [string])) {
        return @($Settings.plugins)
    }

    return @($Settings.plugins)
}

function Get-PluginStageLabel {
    param(
        [Parameter(Mandatory = $true)]
        $Plugin
    )

    if (-not $Plugin.PSObject.Properties['stageLabel'] -or [string]::IsNullOrWhiteSpace([string]$Plugin.stageLabel)) {
        return 'release'
    }

    return [string]$Plugin.stageLabel
}

function Get-PluginBranches {
    param(
        [Parameter(Mandatory = $true)]
        $Plugin
    )

    if (-not $Plugin.PSObject.Properties['branches'] -or $null -eq $Plugin.branches) {
        return @()
    }

    if ($Plugin.branches -is [System.Collections.IEnumerable] -and -not ($Plugin.branches -is [string])) {
        return @($Plugin.branches | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    }

    if ([string]::IsNullOrWhiteSpace([string]$Plugin.branches)) {
        return @()
    }

    return @([string]$Plugin.branches)
}

function Test-PluginAllowedOnBranch {
    param(
        [Parameter(Mandatory = $true)]
        $Plugin,

        [Parameter(Mandatory = $true)]
        [string]$CurrentBranch
    )

    $allowedBranches = Get-PluginBranches -Plugin $Plugin
    if ($allowedBranches.Count -eq 0) {
        return $true
    }

    if ($allowedBranches -contains '*') {
        return $true
    }

    return $allowedBranches -contains $CurrentBranch
}

function Get-PluginMetadataObject {
    param(
        [Parameter(Mandatory = $true)]
        $Plugin,

        [Parameter(Mandatory = $true)]
        [string]$EngineDirectory
    )

    $modulePath = Resolve-PluginModulePath -Plugin $Plugin -EngineDirectory $EngineDirectory
    if (-not (Test-Path $modulePath -PathType Leaf)) {
        return $null
    }

    try {
        $moduleInfo = Import-Module $modulePath -Force -PassThru -ErrorAction Stop
        $metadataCommand = Get-Command -Name 'Get-PluginMetadata' -Module $moduleInfo.Name -ErrorAction SilentlyContinue
        if (-not $metadataCommand) {
            return $null
        }

        return & $metadataCommand
    }
    catch {
        return $null
    }
}

function Test-PluginCompatible {
    <#
    .SYNOPSIS
        Applies an optional compatibility policy supplied by an extension.
    #>
    param(
        [Parameter(Mandatory = $true)]
        $Plugin,

        [Parameter(Mandatory = $true)]
        [string]$EngineDirectory,

        [Parameter(Mandatory = $false)]
        [bool]$WriteLogs = $true
    )

    $extensionTest = Get-Command Test-ExtensionPluginCompatibility -ErrorAction SilentlyContinue
    if ($extensionTest) {
        return & $extensionTest @PSBoundParameters
    }

    return $true
}

function Test-PluginMutatesRemote {
    param(
        [Parameter(Mandatory = $true)]
        $Plugin,

        [Parameter(Mandatory = $false)]
        [string]$EngineDirectory
    )

    if ($null -eq $Plugin -or [string]::IsNullOrWhiteSpace([string]$Plugin.name)) {
        return $false
    }

    if ([string]::IsNullOrWhiteSpace($EngineDirectory)) {
        if ($Plugin.PSObject.Properties.Name -contains 'context' -and $null -ne $Plugin.context -and $Plugin.context.scriptDir) {
            $EngineDirectory = [string]$Plugin.context.scriptDir
        }
        elseif ($Plugin.PSObject.Properties.Name -contains 'scriptDir' -and -not [string]::IsNullOrWhiteSpace([string]$Plugin.scriptDir)) {
            $EngineDirectory = [string]$Plugin.scriptDir
        }
    }

    if ([string]::IsNullOrWhiteSpace($EngineDirectory)) {
        return $false
    }

    $modulePath = Resolve-PluginModulePath -Plugin $Plugin -EngineDirectory $EngineDirectory
    if (-not (Test-Path $modulePath -PathType Leaf)) {
        return $false
    }

    try {
        $moduleInfo = Import-Module $modulePath -Force -PassThru -ErrorAction Stop
        $metadataCommand = Get-Command -Name 'Get-PluginMetadata' -Module $moduleInfo.Name -ErrorAction SilentlyContinue
        if (-not $metadataCommand) {
            return $false
        }

        $metadata = & $metadataCommand
        if ($null -eq $metadata) {
            return $false
        }

        if ($metadata.PSObject.Properties.Name -contains 'mutatesRemote') {
            return [bool]$metadata.mutatesRemote
        }
    }
    catch {
        return $false
    }

    return $false
}

function Get-RepoUtilsEnvironmentVariable {
    <#
    .SYNOPSIS
        Reads a named environment variable from Process, then Windows User, then Machine.

    .DESCRIPTION
        Process wins (CICD sandbox inject, `$env:Name`, explicit session values). When the
        current process was started before a User-level pack was set, User/Machine still
        apply so laptop releases do not require a new shell. An explicit process value —
        including empty JSON `{}` — shadows User/Machine.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    if ([string]::IsNullOrWhiteSpace($Name)) {
        throw "Environment variable name is required."
    }

    $processValue = [Environment]::GetEnvironmentVariable($Name, 'Process')
    # Empty string is what SetEnvironmentVariable($null, Process) leaves behind;
    # treat it as unset so Windows User packs still apply. Explicit '{}' shadows User.
    if (-not [string]::IsNullOrWhiteSpace($processValue)) {
        return $processValue
    }

    foreach ($target in @('User', 'Machine')) {
        try {
            $value = [Environment]::GetEnvironmentVariable($Name, $target)
        }
        catch {
            continue
        }

        if (-not [string]::IsNullOrWhiteSpace($value)) {
            return $value
        }
    }

    return $null
}

function Get-RepoUtilsSecretsEnvNames {
    <#
    .SYNOPSIS
        Reads declared pack environment variable names from scriptSettings / engine context.
    #>
    param(
        [Parameter(Mandatory = $false)]
        $Settings
    )

    $sharedName = $null
    $packName = $null
    if ($null -ne $Settings) {
        if ($Settings.PSObject.Properties.Name -contains 'repoUtilsSecretsShared') {
            $sharedName = [string]$Settings.repoUtilsSecretsShared
        }

        if ($Settings.PSObject.Properties.Name -contains 'repoUtilsSecrets') {
            $packName = [string]$Settings.repoUtilsSecrets
        }
    }

    $sharedName = if ($null -eq $sharedName) { '' } else { $sharedName.Trim() }
    $packName = if ($null -eq $packName) { '' } else { $packName.Trim() }
    if ([string]::IsNullOrWhiteSpace($sharedName) -or [string]::IsNullOrWhiteSpace($packName)) {
        throw "scriptSettings.json must declare repoUtilsSecretsShared and repoUtilsSecrets (environment variable names, e.g. RepoUtilsSecretsShared / RepoUtilsSecrets)."
    }

    return [pscustomobject]@{
        SharedEnv = $sharedName
        PackEnv   = $packName
    }
}

function ConvertFrom-RepoUtilsSecretsPackJson {
    <#
    .SYNOPSIS
        Parses a RepoUtilsSecrets JSON object. Empty input is {}. Bare non-JSON throws.
    #>
    param(
        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string]$Raw,

        [Parameter(Mandatory = $true)]
        [string]$SourceName
    )

    if ([string]::IsNullOrWhiteSpace($Raw)) {
        return [pscustomobject]@{}
    }

    $trimmed = $Raw.Trim()
    if (-not $trimmed.StartsWith('{')) {
        throw "${SourceName} must be a JSON object (RepoUtilsSecrets pack), not a bare string."
    }

    try {
        $parsed = $trimmed | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        throw "${SourceName} is not valid JSON: $($_.Exception.Message)"
    }

    if ($null -eq $parsed -or $parsed -is [System.Collections.IEnumerable]) {
        throw "${SourceName} JSON must be an object."
    }

    return $parsed
}

function ConvertTo-OrdinalPropertyMap {
    param($Object)

    $map = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::Ordinal)
    if ($null -eq $Object) {
        return $map
    }

    if ($Object -is [System.Collections.IDictionary]) {
        foreach ($key in @($Object.Keys)) {
            $name = [string]$key
            if ([string]::IsNullOrWhiteSpace($name)) {
                continue
            }

            $map[$name] = $Object[$key]
        }

        return $map
    }

    foreach ($property in $Object.PSObject.Properties) {
        if ($property.MemberType -notin @('NoteProperty', 'Property')) {
            continue
        }

        $map[[string]$property.Name] = $property.Value
    }

    return $map
}

function ConvertFrom-OrdinalPropertyMap {
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.Generic.Dictionary[string, object]]$Map
    )

    $properties = [ordered]@{}
    foreach ($key in $Map.Keys) {
        $properties[$key] = $Map[$key]
    }

    return [pscustomobject]$properties
}

function Merge-RepoUtilsSecretsPackObjects {
    <#
    .SYNOPSIS
        Appsettings-style merge: org-pack first, slug overlay. Nested merge for any object-valued slot (typically ContainerRegistry).
    #>
    param(
        $Base,
        $Overlay
    )

    $result = ConvertTo-OrdinalPropertyMap -Object $Base
    $overlayMap = ConvertTo-OrdinalPropertyMap -Object $Overlay
    foreach ($key in @($overlayMap.Keys)) {
        if (-not (Test-ContainerRegistryCatalogKey -Key $key)) {
            throw "RepoUtilsSecrets pack key '$key' must be PascalCase (e.g. GitClone, ContainerRegistry)."
        }

        $overlayValue = $overlayMap[$key]
        $overlayIsObject = ($null -ne $overlayValue) -and -not ($overlayValue -is [string]) -and -not ($overlayValue -is [ValueType]) -and -not ($overlayValue -is [System.Collections.IEnumerable])
        if ($overlayIsObject) {
            $baseCatalog = $null
            if ($result.ContainsKey($key)) {
                $baseCatalog = $result[$key]
            }

            $mergedCatalog = ConvertTo-OrdinalPropertyMap -Object $baseCatalog
            $overlayCatalogMap = ConvertTo-OrdinalPropertyMap -Object $overlayValue
            foreach ($catalogKey in @($overlayCatalogMap.Keys)) {
                if (-not (Test-ContainerRegistryCatalogKey -Key $catalogKey)) {
                    throw "Catalog key '$catalogKey' in pack slot '$key' must be PascalCase (e.g. Harbor, InCluster)."
                }

                $mergedCatalog[$catalogKey] = $overlayCatalogMap[$catalogKey]
            }

            $result[$key] = ConvertFrom-OrdinalPropertyMap -Map $mergedCatalog
            continue
        }

        $result[$key] = $overlayValue
    }

    foreach ($key in @($result.Keys)) {
        if (-not (Test-ContainerRegistryCatalogKey -Key $key)) {
            throw "RepoUtilsSecrets pack key '$key' must be PascalCase (e.g. GitClone, ContainerRegistry)."
        }
    }

    return ConvertFrom-OrdinalPropertyMap -Map $result
}

function Get-MergedRepoUtilsSecretsPack {
    <#
    .SYNOPSIS
        Merges $env:RepoUtilsSecretsShared then $env:RepoUtilsSecrets (names from settings).
    #>
    param(
        [Parameter(Mandatory = $false)]
        $Settings
    )

    $names = Get-RepoUtilsSecretsEnvNames -Settings $Settings
    $sharedRaw = Get-RepoUtilsEnvironmentVariable -Name $names.SharedEnv
    $packRaw = Get-RepoUtilsEnvironmentVariable -Name $names.PackEnv
    $sharedObject = ConvertFrom-RepoUtilsSecretsPackJson -Raw $sharedRaw -SourceName $names.SharedEnv
    $packObject = ConvertFrom-RepoUtilsSecretsPackJson -Raw $packRaw -SourceName $names.PackEnv
    return Merge-RepoUtilsSecretsPackObjects -Base $sharedObject -Overlay $packObject
}

function Get-RepoUtilsSecretSlot {
    <#
    .SYNOPSIS
        Reads a scalar pack slot (GitClone, NuGet, Npm, CosignKey, …) after merge.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $false)]
        $Settings,

        [switch]$AllowMissing
    )

    if ([string]::IsNullOrWhiteSpace($Name) -or -not (Test-ContainerRegistryCatalogKey -Key $Name)) {
        throw "RepoUtilsSecrets slot '$Name' must be PascalCase (e.g. GitClone, NuGet)."
    }

    $merged = Get-MergedRepoUtilsSecretsPack -Settings $Settings
    $match = $null
    foreach ($property in $merged.PSObject.Properties) {
        if ($property.MemberType -notin @('NoteProperty', 'Property')) {
            continue
        }

        if ([string]::Equals([string]$property.Name, $Name, [System.StringComparison]::Ordinal)) {
            $match = $property
            break
        }
    }

    if ($null -eq $match) {
        if ($AllowMissing) {
            return $null
        }

        throw "RepoUtilsSecrets slot '$Name' is missing after merging org-pack and slug-pack."
    }

    $value = $match.Value
    if ($value -is [string] -or $null -eq $value -or $value -is [ValueType]) {
        $text = if ($null -eq $value) { '' } else { [string]$value }
        if ([string]::IsNullOrWhiteSpace($text) -and -not $AllowMissing) {
            throw "RepoUtilsSecrets slot '$Name' is empty."
        }

        if ([string]::IsNullOrWhiteSpace($text)) {
            return $null
        }

        return $text
    }

    throw "RepoUtilsSecrets slot '$Name' must be a string (nested maps are only allowed for ContainerRegistry)."
}

function Copy-RepoUtilsSecretsEnvNamesToContext {
    param(
        [Parameter(Mandatory = $true)]
        $Context,

        [Parameter(Mandatory = $false)]
        $Settings
    )

    if ($null -eq $Settings) {
        return $Context
    }

    foreach ($name in @('repoUtilsSecretsShared', 'repoUtilsSecrets', 'vaultRepoUtilsApplication')) {
        if ($Settings.PSObject.Properties.Name -contains $name -and -not [string]::IsNullOrWhiteSpace([string]$Settings.$name)) {
            $Context | Add-Member -NotePropertyName $name -NotePropertyValue ([string]$Settings.$name).Trim() -Force
        }
    }

    return $Context
}

function Test-ContainerRegistryCatalogKey {
    <#
    .SYNOPSIS
        True when Key is PascalCase (Harbor, InCluster), matching env-slot names.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Key
    )

    return $Key -cmatch '^[A-Z][A-Za-z0-9]*$'
}

function Resolve-PluginSecretName {
    <#
    .SYNOPSIS
        Reads a plugin setting that names a RepoUtilsSecrets pack subkey.

    .DESCRIPTION
        Settings such as githubSecret / nugetSecret / npmSecret / containerRegistrySecret /
        cosignKeySecret hold the PascalCase pack slot to read (e.g. GitClone, NuGet).
        They are not environment variable names.

    .PARAMETER PluginSettings
        Plugin settings object from scriptSettings.json.

    .PARAMETER PropertyName
        Settings property that holds the pack subkey name (e.g. 'githubSecret').

    .PARAMETER PluginDisplayName
        Plugin name used in required/validation errors.

    .PARAMETER Required
        Throw when the property is missing or blank.
    #>
    param(
        [Parameter(Mandatory = $true)]
        $PluginSettings,

        [Parameter(Mandatory = $true)]
        [string]$PropertyName,

        [Parameter(Mandatory = $false)]
        [string]$PluginDisplayName,

        [switch]$Required
    )

    $display = if ([string]::IsNullOrWhiteSpace($PluginDisplayName)) { 'Plugin' } else { $PluginDisplayName }
    $value = $null
    if ($null -ne $PluginSettings -and $PluginSettings.PSObject.Properties.Name -contains $PropertyName) {
        $raw = [string]$PluginSettings.$PropertyName
        if (-not [string]::IsNullOrWhiteSpace($raw)) {
            $value = $raw.Trim()
        }
    }

    if ([string]::IsNullOrWhiteSpace($value)) {
        if ($Required) {
            throw "$display requires '$PropertyName' (PascalCase pack subkey, e.g. GitClone, NuGet, ContainerRegistry)."
        }

        return $null
    }

    if (-not (Test-ContainerRegistryCatalogKey -Key $value)) {
        throw "$display '$PropertyName' '$value' must be PascalCase (e.g. GitClone, NuGet, ContainerRegistry)."
    }

    return $value
}

function Assert-RetiredContainerRegistrySettingsAbsent {
    <#
    .SYNOPSIS
        Throws when obsolete per-registry secret settings are present.
    #>
    param(
        $Object,
        [Parameter(Mandatory = $true)]
        [string]$Context
    )

    if ($null -eq $Object) {
        return
    }

    $retired = @(
        'imagesCredentialsSecret',
        'additionalImageRegistries',
        'additionalImageRegistryUrls',
        'additionalImagesCredentialsSecret',
        'helmOciCredentialsSecret'
    )

    foreach ($name in $retired) {
        $present = $false
        if ($Object -is [System.Collections.IDictionary]) {
            $present = $Object.Contains($name)
        }
        elseif ($Object.PSObject.Properties.Name -contains $name) {
            $present = $true
        }

        if ($present) {
            throw "${Context}: '$name' is not supported. Use the ContainerRegistry JSON catalog with PascalCase containerRegistryKey / helmRegistryKey."
        }
    }
}

function ConvertFrom-RegistryCredentialPayload {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Payload,

        [Parameter(Mandatory = $true)]
        [string]$ContextName
    )

    try {
        $decoded = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($Payload.Trim()))
    }
    catch {
        throw "Failed to decode '$ContextName' as Base64 (expected base64('username:password')): $($_.Exception.Message)"
    }

    $parts = $decoded -split ':', 2
    if ($parts.Count -ne 2 -or [string]::IsNullOrWhiteSpace($parts[0]) -or [string]::IsNullOrWhiteSpace($parts[1])) {
        throw "Decoded '$ContextName' must be in the form 'username:password'."
    }

    return @{ User = $parts[0]; Password = $parts[1] }
}

function Get-ContainerRegistryCatalogObject {
    <#
    .SYNOPSIS
        Validates a PascalCase JSON map of Base64(username:password) values.
    #>
    param(
        [Parameter(Mandatory = $true)]
        $Catalog,

        [Parameter(Mandatory = $false)]
        [string]$SourceName = 'ContainerRegistry'
    )

    if ($Catalog -is [string]) {
        $raw = [string]$Catalog
        $trimmed = $raw.Trim()
        if (-not $trimmed.StartsWith('{')) {
            throw "$SourceName must be a JSON catalog object { `"Harbor`": `"<Base64>`", `"InCluster`": `"<Base64>`" }."
        }

        try {
            $Catalog = $trimmed | ConvertFrom-Json -ErrorAction Stop
        }
        catch {
            throw "$SourceName is not valid JSON: $($_.Exception.Message)"
        }
    }

    if ($null -eq $Catalog -or $Catalog -is [string] -or $Catalog -is [ValueType] -or $Catalog -is [System.Collections.IEnumerable]) {
        throw "$SourceName JSON catalog must be an object of PascalCase keys to Base64(username:password)."
    }

    $keyCount = 0
    foreach ($property in $Catalog.PSObject.Properties) {
        if ($property.MemberType -notin @('NoteProperty', 'Property')) {
            continue
        }

        $keyCount++
        $keyName = [string]$property.Name
        if (-not (Test-ContainerRegistryCatalogKey -Key $keyName)) {
            throw "Catalog key '$keyName' in '$SourceName' must be PascalCase (e.g. Harbor, InCluster)."
        }
    }

    if ($keyCount -eq 0) {
        throw "$SourceName JSON catalog has no PascalCase keys."
    }

    return $Catalog
}

function Get-RegistryCredentialsFromRuntime {
    <#
    .SYNOPSIS
        Loads container-registry username/password from the merged RepoUtilsSecrets pack.

    .DESCRIPTION
        Reads a nested catalog slot (named by -Slot, typically ContainerRegistry) after
        org-pack + slug-pack merge. -Key (PascalCase, ordinal match) selects an entry.

    .PARAMETER Key
        PascalCase catalog key (e.g. Harbor). Required.

    .PARAMETER Slot
        PascalCase pack subkey that holds the catalog object (from containerRegistrySecret).

    .PARAMETER SharedSettings
        Engine shared context (must declare repoUtilsSecretsShared / repoUtilsSecrets).

    .OUTPUTS
        Hashtable with User and Password keys (decoded credential material).
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Key,

        [Parameter(Mandatory = $true)]
        [string]$Slot,

        [Parameter(Mandatory = $false)]
        [psobject]$SharedSettings
    )

    if ([string]::IsNullOrWhiteSpace($Slot) -or -not (Test-ContainerRegistryCatalogKey -Key $Slot)) {
        throw "containerRegistrySecret '$Slot' must be PascalCase (e.g. ContainerRegistry)."
    }

    if ([string]::IsNullOrWhiteSpace($Key)) {
        throw "Pass -Key (PascalCase, e.g. Harbor) to select an entry in pack slot '$Slot'."
    }

    if (-not (Test-ContainerRegistryCatalogKey -Key $Key)) {
        throw "containerRegistryKey '$Key' must be PascalCase (e.g. Harbor, InCluster)."
    }

    $merged = Get-MergedRepoUtilsSecretsPack -Settings $SharedSettings
    $catalogProperty = $null
    foreach ($property in $merged.PSObject.Properties) {
        if ($property.MemberType -notin @('NoteProperty', 'Property')) {
            continue
        }

        if ([string]::Equals([string]$property.Name, $Slot, [System.StringComparison]::Ordinal)) {
            $catalogProperty = $property
            break
        }
    }

    if ($null -eq $catalogProperty -or $null -eq $catalogProperty.Value) {
        throw "RepoUtilsSecrets slot '$Slot' is missing after merging org-pack and slug-pack."
    }

    $catalog = Get-ContainerRegistryCatalogObject -Catalog $catalogProperty.Value -SourceName $Slot

    $match = $null
    foreach ($property in $catalog.PSObject.Properties) {
        if ($property.MemberType -notin @('NoteProperty', 'Property')) {
            continue
        }

        if ([string]::Equals([string]$property.Name, $Key, [System.StringComparison]::Ordinal)) {
            $match = $property
            break
        }
    }

    if ($null -eq $match) {
        throw "Catalog key '$Key' was not found in '$Slot' (ordinal PascalCase match)."
    }

    $payload = [string]$match.Value
    if ([string]::IsNullOrWhiteSpace($payload)) {
        throw "Catalog key '$Key' in '$Slot' is empty."
    }

    return ConvertFrom-RegistryCredentialPayload -Payload $payload -ContextName "$Slot.$Key"
}

function Resolve-EngineDirectoryFromSharedSettings {
    param(
        [Parameter(Mandatory = $true)]
        $SharedSettings
    )

    if ($SharedSettings.PSObject.Properties.Name -contains 'engineScriptDir' -and -not [string]::IsNullOrWhiteSpace([string]$SharedSettings.engineScriptDir)) {
        return [string]$SharedSettings.engineScriptDir
    }

    return [string]$SharedSettings.scriptDir
}

function Test-PluginSkipsRemoteMutation {
    param(
        [Parameter(Mandatory = $true)]
        $Plugin,

        [Parameter(Mandatory = $true)]
        [psobject]$SharedSettings
    )

    $engineDirectory = Resolve-EngineDirectoryFromSharedSettings -SharedSettings $SharedSettings
    if (-not (Test-PluginMutatesRemote -Plugin $Plugin -EngineDirectory $engineDirectory)) {
        return $false
    }

    return ($Plugin.PSObject.Properties.Name -contains 'dryRun' -and $null -ne $Plugin.dryRun -and [bool]$Plugin.dryRun)
}

function Test-IsPublishPlugin {
    param(
        [Parameter(Mandatory = $true)]
        $Plugin,

        [Parameter(Mandatory = $false)]
        [string]$EngineDirectory
    )

    return Test-PluginMutatesRemote -Plugin $Plugin -EngineDirectory $EngineDirectory
}

function Get-PluginSettingValue {
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$Plugins,

        [Parameter(Mandatory = $true)]
        [string]$PropertyName
    )

    foreach ($plugin in $Plugins) {
        if ($null -eq $plugin -or [string]::IsNullOrWhiteSpace($plugin.name)) {
            continue
        }

        if (-not $plugin.PSObject.Properties[$PropertyName]) {
            continue
        }

        $value = $plugin.$PropertyName
        if ($null -eq $value) {
            continue
        }

        if ($value -is [string] -and [string]::IsNullOrWhiteSpace($value)) {
            continue
        }

        return $value
    }

    return $null
}

function Get-PluginPathListSetting {
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$Plugins,

        [Parameter(Mandatory = $true)]
        [string]$PropertyName,

        [Parameter(Mandatory = $true)]
        [string]$BasePath
    )

    $rawPaths = @()
    $value = Get-PluginSettingValue -Plugins $Plugins -PropertyName $PropertyName

    if ($null -eq $value) {
        return @()
    }

    if ($value -is [System.Collections.IEnumerable] -and -not ($value -is [string])) {
        $rawPaths += $value
    }
    else {
        $rawPaths += $value
    }

    $resolvedPaths = @()
    foreach ($path in $rawPaths) {
        if ([string]::IsNullOrWhiteSpace([string]$path)) {
            continue
        }

        $resolvedPaths += [System.IO.Path]::GetFullPath((Join-Path $BasePath ([string]$path)))
    }

    return @($resolvedPaths)
}

function Get-PluginPathSetting {
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$Plugins,

        [Parameter(Mandatory = $true)]
        [string]$PropertyName,

        [Parameter(Mandatory = $true)]
        [string]$BasePath
    )

    $value = Get-PluginSettingValue -Plugins $Plugins -PropertyName $PropertyName
    if ($null -eq $value -or [string]::IsNullOrWhiteSpace([string]$value)) {
        return $null
    }

    return [System.IO.Path]::GetFullPath((Join-Path $BasePath ([string]$value)))
}

function Get-ArchiveNamePattern {
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$Plugins,

        [Parameter(Mandatory = $true)]
        [string]$CurrentBranch
    )

    foreach ($plugin in $Plugins) {
        if ($null -eq $plugin -or [string]::IsNullOrWhiteSpace($plugin.name)) {
            continue
        }

        if (-not $plugin.enabled) {
            continue
        }

        if (-not (Test-PluginAllowedOnBranch -Plugin $plugin -CurrentBranch $CurrentBranch)) {
            continue
        }

        if ($plugin.PSObject.Properties['zipNamePattern'] -and -not [string]::IsNullOrWhiteSpace([string]$plugin.zipNamePattern)) {
            return [string]$plugin.zipNamePattern
        }
    }

    return "release-{version}.zip"
}

function Resolve-PluginModulePath {
    param(
        [Parameter(Mandatory = $true)]
        $Plugin,

        [Parameter(Mandatory = $true)]
        [string]$EngineDirectory
    )

    $srcDir = Split-Path (Split-Path $EngineDirectory -Parent) -Parent
    $pluginsRoot = Join-Path $srcDir "plugins"
    $pluginFileName = "{0}.psm1" -f $Plugin.name
    $candidatePaths = [System.Collections.Generic.List[string]]::new()
    $candidatePaths.Add((Join-Path (Join-Path $EngineDirectory "custom") $pluginFileName))

    $preferredGroups = @('Platform', 'DotNet', 'Npm', 'Desktop')
    $candidatePaths.Add((Join-Path (Join-Path $pluginsRoot $preferredGroups[0]) $pluginFileName))

    if (Get-Command Get-ExtensionPluginModulePaths -ErrorAction SilentlyContinue) {
        foreach ($extensionPath in Get-ExtensionPluginModulePaths -PluginsRoot $pluginsRoot -PluginFileName $pluginFileName) {
            $candidatePaths.Add($extensionPath)
        }
    }

    foreach ($group in $preferredGroups[1..($preferredGroups.Count - 1)]) {
        $candidatePaths.Add((Join-Path (Join-Path $pluginsRoot $group) $pluginFileName))
    }

    $reservedPluginDirs = @($preferredGroups + @('Shared'))
    if (Test-Path -LiteralPath $pluginsRoot -PathType Container) {
        Get-ChildItem -LiteralPath $pluginsRoot -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -notin $reservedPluginDirs } |
            Sort-Object Name |
            ForEach-Object {
                $candidatePaths.Add((Join-Path $_.FullName $pluginFileName))
            }
    }

    foreach ($candidatePath in $candidatePaths) {
        if (Test-Path $candidatePath -PathType Leaf) {
            return $candidatePath
        }
    }

    return $candidatePaths[0]
}

function Test-PluginRunnable {
    param(
        [Parameter(Mandatory = $true)]
        $Plugin,

        [Parameter(Mandatory = $true)]
        [psobject]$SharedSettings,

        [Parameter(Mandatory = $true)]
        [string]$EngineDirectory,

        [Parameter(Mandatory = $false)]
        [bool]$WriteLogs = $true
    )

    if ($null -eq $Plugin -or [string]::IsNullOrWhiteSpace($Plugin.name)) {
        if ($WriteLogs) {
            Write-Log -Level "WARN" -Message "Skipping plugin entry with no name."
        }
        return $false
    }

    if (-not $Plugin.enabled) {
        if ($WriteLogs) {
            Write-Log -Level "WARN" -Message "Skipping plugin '$($Plugin.name)' (disabled)."
        }
        return $false
    }

    $pluginModulePath = Resolve-PluginModulePath -Plugin $Plugin -EngineDirectory $EngineDirectory
    if (-not (Test-Path $pluginModulePath -PathType Leaf)) {
        if ($WriteLogs) {
            Write-Log -Level "ERROR" -Message "Plugin module not found: $pluginModulePath"
        }
        return $false
    }

    return $true
}

function New-PluginInvocationSettings {
    param(
        [Parameter(Mandatory = $true)]
        $Plugin,

        [Parameter(Mandatory = $true)]
        [psobject]$SharedSettings
    )

    $properties = @{}
    foreach ($property in $Plugin.PSObject.Properties) {
        $properties[$property.Name] = $property.Value
    }

    $properties['context'] = $SharedSettings
    return [pscustomobject]$properties
}

function Invoke-ConfiguredPlugin {
    param(
        [Parameter(Mandatory = $true)]
        $Plugin,

        [Parameter(Mandatory = $true)]
        [psobject]$SharedSettings,

        [Parameter(Mandatory = $true)]
        [string]$EngineDirectory
    )

    if (-not (Test-PluginRunnable -Plugin $Plugin -SharedSettings $SharedSettings -EngineDirectory $EngineDirectory -WriteLogs:$true)) {
        if ($Plugin.enabled) {
            return $false
        }

        return $true
    }

    $metadata = Get-PluginMetadataObject -Plugin $Plugin -EngineDirectory $EngineDirectory
    if ($null -ne $metadata -and ($metadata.PSObject.Properties.Name -contains 'providesVersion') -and [bool]$metadata.providesVersion) {
        $versionAlreadySet = $false
        if (Get-Command Get-EngineState -ErrorAction SilentlyContinue) {
            $existingVersion = Get-EngineState -Context $SharedSettings -Name 'version' -ErrorAction SilentlyContinue
            $versionAlreadySet = -not [string]::IsNullOrWhiteSpace([string]$existingVersion)
        }
        elseif (($SharedSettings.PSObject.Properties.Name -contains 'version') -and -not [string]::IsNullOrWhiteSpace([string]$SharedSettings.version)) {
            $versionAlreadySet = $true
        }

        if ($versionAlreadySet) {
            Write-Log -Level "INFO" -Message "Skipping plugin '$($Plugin.name)' (version already resolved during New-EngineContext)."
            return $true
        }

        # Test engine (and other hosts) may not resolve version in New-EngineContext; run the plugin now.
    }

    if ((Test-IsPublishPlugin -Plugin $Plugin) -and ($SharedSettings.PSObject.Properties.Name -contains 'skipPublishPlugins') -and $SharedSettings.skipPublishPlugins) {
        Write-Log -Level "INFO" -Message "Skipping plugin '$($Plugin.name)' (ReleasePublishGuard suppressed publish)."
        return $true
    }

    if (-not (Test-PluginCompatible -Plugin $Plugin -EngineDirectory $EngineDirectory -WriteLogs:$true)) {
        return $true
    }

    $pluginModulePath = Resolve-PluginModulePath -Plugin $Plugin -EngineDirectory $EngineDirectory
    Write-Log -Level "STEP" -Message "Running plugin '$($Plugin.name)'..."

    # Sink plugin success-stream output to the host so it cannot pollute this
    # function's return value. Otherwise `return $false` after CLI stdout becomes
    # @("helm-line…", $false), which is truthy under `if (-not $result)` and
    # causes RELEASE COMPLETE / exit 0 after a failed plugin.
    try {
        $moduleInfo = Import-Module $pluginModulePath -Force -PassThru -ErrorAction Stop
        $invokeCommand = Get-Command -Name "Invoke-Plugin" -Module $moduleInfo.Name -ErrorAction Stop
        $pluginSettings = New-PluginInvocationSettings -Plugin $Plugin -SharedSettings $SharedSettings

        & $invokeCommand -Settings $pluginSettings | ForEach-Object { Write-Host $_ }
        Write-Log -Level "OK" -Message "  Plugin '$($Plugin.name)' completed."
        return $true
    }
    catch {
        Write-Log -Level "ERROR" -Message "  Plugin '$($Plugin.name)' failed: $($_.Exception.Message)"
        return $false
    }
}

Export-ModuleMember -Function Import-PluginDependency, Get-ConfiguredPlugins, Get-PluginStageLabel, Get-PluginBranches, Get-PluginMetadataObject, Test-PluginCompatible, Test-PluginMutatesRemote, Get-RepoUtilsEnvironmentVariable, Get-RepoUtilsSecretsEnvNames, ConvertFrom-RepoUtilsSecretsPackJson, Merge-RepoUtilsSecretsPackObjects, Get-MergedRepoUtilsSecretsPack, Get-RepoUtilsSecretSlot, Copy-RepoUtilsSecretsEnvNamesToContext, Resolve-PluginSecretName, Test-ContainerRegistryCatalogKey, Assert-RetiredContainerRegistrySettingsAbsent, Get-ContainerRegistryCatalogObject, Get-RegistryCredentialsFromRuntime, Test-PluginSkipsRemoteMutation, Test-IsPublishPlugin, Get-PluginSettingValue, Get-PluginPathListSetting, Get-PluginPathSetting, Get-ArchiveNamePattern, Resolve-PluginModulePath, Test-PluginRunnable, New-PluginInvocationSettings, Invoke-ConfiguredPlugin
