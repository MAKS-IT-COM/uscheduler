#requires -Version 7.0
#requires -PSEdition Core

<#
.SYNOPSIS
    .NET Helm publish plugin — package and push charts versioned from DotNetReleaseVersion.

.DESCRIPTION
    The chart in the repo should keep placeholder version and appVersion (e.g. 0.0.0); this plugin
    overwrites them with the bare semver from shared context (DotNetReleaseVersion / shared.version,
    e.g. 3.3.4 — no leading v), falling back to stripping v/V from shared.tag if version is missing,
    then runs helm package and helm push, then restores Chart.yaml.

    Optional pushLatest (default false when omitted): when true, after the versioned push, copies the chart
    to a :latest tag in the same OCI repository using the oras CLI (https://oras.land). Requires oras on PATH.
#>

if (-not (Get-Command Import-PluginDependency -ErrorAction SilentlyContinue)) {
    $srcDir = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
        $pluginSupportModulePath = Join-Path $srcDir "modules/Engine/PluginSupport.psm1"
    if (Test-Path $pluginSupportModulePath -PathType Leaf) {
        Import-Module $pluginSupportModulePath -Force -Global -ErrorAction Stop
    }
}

function Get-RegistryCredentialsFromEnv {
    param(
        [Parameter(Mandatory = $true)]
        [string]$EnvVarName
    )

    $raw = [Environment]::GetEnvironmentVariable($EnvVarName)
    if ([string]::IsNullOrWhiteSpace($raw)) {
        throw "Environment variable '$EnvVarName' is not set."
    }

    try {
        $decoded = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($raw))
    }
    catch {
        throw "Failed to decode '$EnvVarName' as Base64 (expected base64('username:password')): $($_.Exception.Message)"
    }

    $parts = $decoded -split ':', 2
    if ($parts.Count -ne 2 -or [string]::IsNullOrWhiteSpace($parts[0]) -or [string]::IsNullOrWhiteSpace($parts[1])) {
        throw "Decoded '$EnvVarName' must be in the form 'username:password'."
    }

    return @{ User = $parts[0]; Password = $parts[1] }
}

function Invoke-Plugin {
    param(
        [Parameter(Mandatory = $true)]
        $Settings
    )

    Import-PluginDependency -ModuleName "Logging" -RequiredCommand "Write-Log"
    Import-PluginDependency -ModuleName "ScriptConfig" -RequiredCommand "Assert-Command"

    $pluginSettings = $Settings
    $shared = $Settings.context

    Assert-Command helm

    $pushLatest = if ($null -ne $pluginSettings.pushLatest) { [bool]$pluginSettings.pushLatest } else { $false }

    if ([string]::IsNullOrWhiteSpace($pluginSettings.chartPath)) {
        throw "DotNetHelmPush plugin requires 'chartPath' (chart directory, relative to engines/release folder)."
    }

    if ([string]::IsNullOrWhiteSpace($pluginSettings.ociRepository)) {
        throw "DotNetHelmPush plugin requires 'ociRepository' (e.g. oci://cr.maks-it.com/charts)."
    }

    if ([string]::IsNullOrWhiteSpace($pluginSettings.credentialsEnvVar)) {
        throw "DotNetHelmPush plugin requires 'credentialsEnvVar' (name of env var holding base64 username:password)."
    }

    $scriptDir = $shared.ScriptDir
    $chartDir = [System.IO.Path]::GetFullPath((Join-Path $scriptDir ([string]$pluginSettings.chartPath)))
    $chartYaml = Join-Path $chartDir 'Chart.yaml'

    if (-not (Test-Path $chartYaml -PathType Leaf)) {
        throw "Chart.yaml not found at: $chartYaml"
    }

    $chartVersion = $null
    if ($shared.PSObject.Properties.Name -contains 'version' -and -not [string]::IsNullOrWhiteSpace([string]$shared.version)) {
        $chartVersion = ([string]$shared.version).Trim() -replace '^[vV]', ''
    }
    if ([string]::IsNullOrWhiteSpace($chartVersion) -and $shared.PSObject.Properties.Name -contains 'tag') {
        $chartVersion = ([string]$shared.tag).Trim() -replace '^[vV]', ''
    }
    if ([string]::IsNullOrWhiteSpace($chartVersion)) {
        throw "Could not derive chart version: need shared.version (DotNetReleaseVersion) or shared.tag (e.g. v3.3.4)."
    }

    $creds = Get-RegistryCredentialsFromEnv -EnvVarName ([string]$pluginSettings.credentialsEnvVar)
    $ociRepository = [string]$pluginSettings.ociRepository.TrimEnd('/')

    $chartNameLine = Select-String -LiteralPath $chartYaml -Pattern '^\s*name:\s*(.+)\s*$' | Select-Object -First 1
    if (-not $chartNameLine -or $chartNameLine.Matches.Count -lt 1) {
        throw "Could not read chart name from Chart.yaml."
    }
    $chartName = $chartNameLine.Matches[0].Groups[1].Value.Trim()

    $backupPath = "$chartYaml.bak"
    Copy-Item -LiteralPath $chartYaml -Destination $backupPath -Force

    try {
        $content = Get-Content -LiteralPath $chartYaml -Raw
        $content = $content `
            -replace '(?m)^\s*version:\s*.*$', "version: $chartVersion" `
            -replace '(?m)^\s*appVersion:\s*.*$', "appVersion: `"$chartVersion`""
        Set-Content -LiteralPath $chartYaml -Value $content

        Write-Log -Level "STEP" -Message "Linting Helm chart at $chartDir ..."
        helm lint $chartDir
        if ($LASTEXITCODE -ne 0) {
            throw "helm lint failed."
        }

        $packageDest = $scriptDir
        Write-Log -Level "STEP" -Message "Packaging Helm chart..."
        $packageOutput = helm package $chartDir --destination $packageDest 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0) {
            throw "helm package failed. Output: $packageOutput"
        }

        $chartPackage = Join-Path $packageDest "$chartName-$chartVersion.tgz"
        if (-not (Test-Path -LiteralPath $chartPackage -PathType Leaf)) {
            throw "Expected chart package not found: $chartPackage (helm output: $packageOutput)"
        }

        Write-Log -Level "STEP" -Message "Pushing $chartPackage to $ociRepository ..."
        helm push $chartPackage $ociRepository --username $creds.User --password $creds.Password
        if ($LASTEXITCODE -ne 0) {
            throw "helm push failed."
        }

        if ($pushLatest) {
            Assert-Command oras
            if ($ociRepository -notmatch '^oci://([^/]+)') {
                throw "Could not parse registry host from ociRepository: $ociRepository"
            }
            $registryHost = $Matches[1]
            $baseRef = "$($ociRepository.TrimEnd('/'))/$chartName"
            $srcRef = "${baseRef}:$chartVersion"
            $dstRef = "${baseRef}:latest"

            Write-Log -Level "STEP" -Message "Tagging chart as latest (oras copy)..."
            Write-Log -Level "INFO" -Message "  $srcRef -> $dstRef"

            $loginOut = $creds.Password | & oras login $registryHost -u $creds.User --password-stdin 2>&1
            if ($LASTEXITCODE -ne 0) {
                throw "oras login failed for ${registryHost}: $loginOut"
            }

            $copyOut = & oras copy $srcRef $dstRef 2>&1
            if ($LASTEXITCODE -ne 0) {
                throw "oras copy failed: $copyOut"
            }

            & oras logout $registryHost 2>&1 | Out-Null
            Write-Log -Level "OK" -Message "  Chart latest tag pushed."
        }

        Remove-Item -LiteralPath $chartPackage -Force -ErrorAction SilentlyContinue
        Write-Log -Level "OK" -Message "  Helm chart push completed."
    }
    finally {
        if (Test-Path -LiteralPath $backupPath -PathType Leaf) {
            Move-Item -LiteralPath $backupPath -Destination $chartYaml -Force
        }
    }

    $shared | Add-Member -NotePropertyName publishCompleted -NotePropertyValue $true -Force
}

Export-ModuleMember -Function Invoke-Plugin
