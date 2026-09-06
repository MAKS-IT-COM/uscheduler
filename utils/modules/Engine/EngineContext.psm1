#requires -Version 7.0
#requires -PSEdition Core

<#
.SYNOPSIS
    Generic engine helpers: path resolution and the shared context facts API.

.DESCRIPTION
    Engine-owned state stays on the context object (version, tag, skipPublishPlugins, …).
    Plugin-published values go under $context.facts[namespace][name] via Set/Get/Test-EngineFact.
    During migration, -LegacyProperty on Set dual-writes flat properties; Get falls back to them.

    Version plugins declare providesVersion = $true; New-EngineContext discovers the single enabled one.
#>

if (-not (Get-Command Write-Log -ErrorAction SilentlyContinue)) {
    $loggingModulePath = Join-Path (Split-Path $PSScriptRoot -Parent) "Logging.psm1"
    if (Test-Path $loggingModulePath -PathType Leaf) {
        Import-Module $loggingModulePath -Force
    }
}

$script:EngineStateAllowlist = @(
    'version'
    'tag'
    'skipPublishPlugins'
    'releaseDir'
    'artifactsDirectory'
    'deployMode'
    'orchestrator'
)

function Resolve-RelativePaths {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Value,

        [Parameter(Mandatory = $true)]
        [string]$BasePath
    )

    if ($null -eq $Value) {
        return @()
    }

    $rawPaths = @()
    if ($Value -is [System.Collections.IEnumerable] -and -not ($Value -is [string])) {
        $rawPaths += $Value
    }
    else {
        $rawPaths += $Value
    }

    $resolved = @()
    foreach ($p in $rawPaths) {
        if ([string]::IsNullOrWhiteSpace([string]$p)) {
            continue
        }

        $resolved += [System.IO.Path]::GetFullPath((Join-Path $BasePath ([string]$p)))
    }

    return @($resolved)
}

function Initialize-EngineFactsBag {
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$Context
    )

    if (-not ($Context.PSObject.Properties.Name -contains 'facts') -or $null -eq $Context.facts) {
        $Context | Add-Member -NotePropertyName facts -NotePropertyValue ([ordered]@{}) -Force
    }
}

function Assert-EngineFactNamespace {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Namespace
    )

    if ($Namespace -eq 'engine') {
        throw "Namespace 'engine' is reserved; use Set-EngineState / Get-EngineState for engine-owned fields."
    }

    if ($Namespace -cnotmatch '^[a-z][a-z0-9]*$') {
        throw "Invalid facts namespace '$Namespace'. Use lowercase alphanumeric starting with a letter (e.g. 'test', 'dotnet')."
    }
}

function Assert-EngineFactName {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    if ($Name -cnotmatch '^[a-zA-Z][a-zA-Z0-9_]*$') {
        throw "Invalid fact name '$Name'. Use letters, digits, underscore; must start with a letter."
    }
}

function Test-EngineFactValuePresent {
    param(
        [AllowNull()]
        $Value
    )

    if ($null -eq $Value) {
        return $false
    }

    if ($Value -is [string] -and [string]::IsNullOrWhiteSpace($Value)) {
        return $false
    }

    return $true
}

function Set-EngineFact {
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$Context,

        [Parameter(Mandatory = $true)]
        [string]$Namespace,

        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [AllowNull()]
        $Value,

        [ValidateSet('Error', 'Replace', 'Keep')]
        [string]$Overwrite = 'Error',

        [Parameter(Mandatory = $false)]
        [string]$LegacyProperty
    )

    Assert-EngineFactNamespace -Namespace $Namespace
    Assert-EngineFactName -Name $Name
    Initialize-EngineFactsBag -Context $Context

    if (-not $Context.facts.Contains($Namespace)) {
        $Context.facts[$Namespace] = [ordered]@{}
    }

    $bag = $Context.facts[$Namespace]
    $exists = $bag.Contains($Name)
    if ($exists) {
        if ($Overwrite -eq 'Keep') {
            if (-not [string]::IsNullOrWhiteSpace($LegacyProperty) -and -not ($Context.PSObject.Properties.Name -contains $LegacyProperty)) {
                $Context | Add-Member -NotePropertyName $LegacyProperty -NotePropertyValue $bag[$Name] -Force
            }
            return
        }

        if ($Overwrite -eq 'Error') {
            throw "Fact ${Namespace}.${Name} already set (use -Overwrite Replace or Keep)."
        }
    }

    $bag[$Name] = $Value

    if (-not [string]::IsNullOrWhiteSpace($LegacyProperty)) {
        $Context | Add-Member -NotePropertyName $LegacyProperty -NotePropertyValue $Value -Force
    }
}

function Get-EngineFact {
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$Context,

        [Parameter(Mandatory = $true)]
        [string]$Namespace,

        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $false)]
        $Default,

        [switch]$Required,

        [Parameter(Mandatory = $false)]
        [string[]]$LegacyProperty
    )

    Assert-EngineFactNamespace -Namespace $Namespace
    Assert-EngineFactName -Name $Name
    Initialize-EngineFactsBag -Context $Context

    if ($Context.facts.Contains($Namespace) -and $Context.facts[$Namespace].Contains($Name)) {
        $value = $Context.facts[$Namespace][$Name]
        if (Test-EngineFactValuePresent -Value $value) {
            return $value
        }
    }

    foreach ($propertyName in @($LegacyProperty)) {
        if ([string]::IsNullOrWhiteSpace($propertyName)) {
            continue
        }

        if ($Context.PSObject.Properties.Name -contains $propertyName) {
            $legacyValue = $Context.$propertyName
            if (Test-EngineFactValuePresent -Value $legacyValue) {
                return $legacyValue
            }
        }
    }

    if ($Required) {
        throw "Required fact ${Namespace}.${Name} is missing."
    }

    if ($PSBoundParameters.ContainsKey('Default')) {
        return $Default
    }

    return $null
}

function Test-EngineFact {
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$Context,

        [Parameter(Mandatory = $true)]
        [string]$Namespace,

        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $false)]
        [string[]]$LegacyProperty
    )

    $value = Get-EngineFact -Context $Context -Namespace $Namespace -Name $Name -LegacyProperty $LegacyProperty
    return (Test-EngineFactValuePresent -Value $value)
}

function Set-EngineState {
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$Context,

        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [AllowNull()]
        $Value
    )

    if ($script:EngineStateAllowlist -notcontains $Name) {
        throw "Engine state key '$Name' is not allowlisted. Use Set-EngineFact for plugin outputs, or extend the engine allowlist for documented engine fields."
    }

    $Context | Add-Member -NotePropertyName $Name -NotePropertyValue $Value -Force
}

function Add-EnginePublishCompletion {
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$Context,

        [Parameter(Mandatory = $true)]
        [string]$Publisher
    )

    if ([string]::IsNullOrWhiteSpace($Publisher)) {
        throw "Publisher name is required."
    }

    $completedBy = @(Get-EngineFact -Context $Context -Namespace 'publish' -Name 'completedBy' -Default @())
    if ($completedBy -notcontains $Publisher) {
        $completedBy += $Publisher
    }

    Set-EngineFact -Context $Context -Namespace 'publish' -Name 'completedBy' -Value $completedBy -Overwrite Replace
    Set-EngineFact -Context $Context -Namespace 'publish' -Name 'completed' -Value $true -Overwrite Replace -LegacyProperty 'publishCompleted'
}

function Get-EngineState {
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$Context,

        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $false)]
        $Default,

        [switch]$Required
    )

    if ($script:EngineStateAllowlist -notcontains $Name) {
        throw "Engine state key '$Name' is not allowlisted."
    }

    if ($Context.PSObject.Properties.Name -contains $Name) {
        $value = $Context.$Name
        if (Test-EngineFactValuePresent -Value $value) {
            return $value
        }
    }

    if ($Required) {
        throw "Required engine state '$Name' is missing."
    }

    if ($PSBoundParameters.ContainsKey('Default')) {
        return $Default
    }

    return $null
}

function Add-ReleaseAssetPaths {
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$Context,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [string[]]$Path
    )

    $list = [System.Collections.Generic.List[string]]::new()
    $existing = Get-EngineFact -Context $Context -Namespace 'release' -Name 'assetPaths' -Default @() -LegacyProperty @('releaseAssetPaths')
    foreach ($item in @($existing)) {
        $value = [string]$item
        if (-not [string]::IsNullOrWhiteSpace($value) -and -not $list.Contains($value)) {
            $list.Add($value)
        }
    }

    foreach ($item in @($Path)) {
        $value = [string]$item
        if ([string]::IsNullOrWhiteSpace($value) -or $list.Contains($value)) {
            continue
        }

        $list.Add($value)
    }

    Set-EngineFact -Context $Context -Namespace 'release' -Name 'assetPaths' -Value @($list) -Overwrite Replace -LegacyProperty 'releaseAssetPaths'
}

Export-ModuleMember -Function `
    Resolve-RelativePaths, `
    Initialize-EngineFactsBag, `
    Set-EngineFact, `
    Get-EngineFact, `
    Test-EngineFact, `
    Set-EngineState, `
    Add-EnginePublishCompletion, `
    Add-ReleaseAssetPaths, `
    Get-EngineState
