#requires -Version 7.0
#requires -PSEdition Core

<#
.SYNOPSIS
    .NET Docker publish plugin — build and push container images for .NET apps.

.DESCRIPTION
    Logs in with credentials from a Base64-encoded username:password environment variable,
    builds each configured image once, then tags and pushes: bare semver from DotNetReleaseVersion
    (e.g. 3.3.4), v-prefixed alias (v3.3.4) when different, optional exact shared.tag if it differs,
    and optional latest.

    Release image tags align with shared.version (same bare semver as Helm chart/OCI when used together); not from Chart.yaml.
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

function Set-EnvVersionValue {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath,

        [Parameter(Mandatory = $true)]
        [string]$Version
    )

    $content = Get-Content -LiteralPath $FilePath -Raw
    if ($content -match '(?m)^\s*VITE_APP_VERSION\s*=') {
        $content = $content -replace '(?m)^\s*VITE_APP_VERSION\s*=.*$', "VITE_APP_VERSION=$Version"
    }
    else {
        $separator = if ($content -match "(\r?\n)$") { '' } else { [Environment]::NewLine }
        $content = "$content${separator}VITE_APP_VERSION=$Version"
    }

    Set-Content -LiteralPath $FilePath -Value $content -NoNewline
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

    Assert-Command docker

    if ([string]::IsNullOrWhiteSpace($pluginSettings.registryUrl)) {
        throw "DotNetDockerPush plugin requires 'registryUrl' (registry hostname, no scheme)."
    }

    if ([string]::IsNullOrWhiteSpace($pluginSettings.credentialsEnvVar)) {
        throw "DotNetDockerPush plugin requires 'credentialsEnvVar' (name of env var holding base64 username:password)."
    }

    if ([string]::IsNullOrWhiteSpace($pluginSettings.projectName)) {
        throw "DotNetDockerPush plugin requires 'projectName' (image path segment after registry)."
    }

    if ([string]::IsNullOrWhiteSpace($pluginSettings.contextPath)) {
        throw "DotNetDockerPush plugin requires 'contextPath' (Docker build context, relative to engines/release folder)."
    }

    if (-not $pluginSettings.images -or @($pluginSettings.images).Count -eq 0) {
        throw "DotNetDockerPush plugin requires a non-empty 'images' array with 'service' and 'dockerfile' per entry."
    }

    $scriptDir = $shared.scriptDir
    $contextPath = [System.IO.Path]::GetFullPath((Join-Path $scriptDir ([string]$pluginSettings.contextPath)))
    if (-not (Test-Path $contextPath -PathType Container)) {
        throw "Docker context directory not found: $contextPath"
    }

    $registryUrl = [string]$pluginSettings.registryUrl.TrimEnd('/')
    $creds = Get-RegistryCredentialsFromEnv -EnvVarName ([string]$pluginSettings.credentialsEnvVar)

    $bareVersion = $null
    if ($shared.PSObject.Properties.Name -contains 'version' -and -not [string]::IsNullOrWhiteSpace([string]$shared.version)) {
        $bareVersion = ([string]$shared.version).Trim() -replace '^[vV]', ''
    }
    if ([string]::IsNullOrWhiteSpace($bareVersion) -and $shared.PSObject.Properties.Name -contains 'tag') {
        $bareVersion = ([string]$shared.tag).Trim() -replace '^[vV]', ''
    }
    if ([string]::IsNullOrWhiteSpace($bareVersion)) {
        throw "DotNetDockerPush: could not derive version tag (need shared.version from DotNetReleaseVersion or shared.tag)."
    }

    $imageTags = New-Object System.Collections.Generic.List[string]
    function Add-ImageTag([System.Collections.Generic.List[string]]$List, [string]$Tag) {
        if ([string]::IsNullOrWhiteSpace($Tag)) { return }
        if (-not $List.Contains($Tag)) { [void]$List.Add($Tag) }
    }
    Add-ImageTag $imageTags $bareVersion
    Add-ImageTag $imageTags "v$bareVersion"
    if ($shared.PSObject.Properties.Name -contains 'tag') {
        Add-ImageTag $imageTags ([string]$shared.tag).Trim()
    }
    $pushLatest = if ($null -ne $pluginSettings.pushLatest) { [bool]$pluginSettings.pushLatest } else { $true }
    if ($pushLatest) {
        Add-ImageTag $imageTags 'latest'
    }

    Write-Log -Level "STEP" -Message "Docker login to $registryUrl..."
    $loginResult = $creds.Password | docker login $registryUrl -u $creds.User --password-stdin 2>&1
    if ($LASTEXITCODE -ne 0 -or ($loginResult -notmatch 'Login Succeeded')) {
        throw "Docker login failed for ${registryUrl}: $loginResult"
    }

    try {
        foreach ($img in @($pluginSettings.images)) {
            if ($null -eq $img.service -or $null -eq $img.dockerfile) {
                throw "Each images[] entry must define 'service' and 'dockerfile'."
            }

            $service = [string]$img.service
            $dockerfileRel = [string]$img.dockerfile

            $imgContextPath = $contextPath
            if ($img.PSObject.Properties.Name -contains 'contextPath' -and -not [string]::IsNullOrWhiteSpace([string]$img.contextPath)) {
                $imgContextPath = [System.IO.Path]::GetFullPath((Join-Path $scriptDir ([string]$img.contextPath)))
                if (-not (Test-Path $imgContextPath -PathType Container)) {
                    throw "Docker context directory not found for image '$service': $imgContextPath"
                }
            }

            $dockerfilePath = [System.IO.Path]::GetFullPath((Join-Path $imgContextPath $dockerfileRel))
            if (-not (Test-Path $dockerfilePath -PathType Leaf)) {
                throw "Dockerfile not found: $dockerfilePath"
            }
            $baseName = "$registryUrl/$($pluginSettings.projectName)/$service"

            $versionEnvFiles = @()
            if ($img.PSObject.Properties.Name -contains 'versionEnvFiles' -and $null -ne $img.versionEnvFiles) {
                foreach ($relativeEnvFile in @($img.versionEnvFiles)) {
                    if ([string]::IsNullOrWhiteSpace([string]$relativeEnvFile)) {
                        continue
                    }

                    $envFilePath = [System.IO.Path]::GetFullPath((Join-Path $imgContextPath ([string]$relativeEnvFile)))
                    if (-not (Test-Path -LiteralPath $envFilePath -PathType Leaf)) {
                        throw "Configured versionEnvFiles entry not found: $envFilePath"
                    }

                    $backupPath = "$envFilePath.repoutils.bak"
                    Copy-Item -LiteralPath $envFilePath -Destination $backupPath -Force
                    $versionEnvFiles += [pscustomobject]@{
                        FilePath = $envFilePath
                        BackupPath = $backupPath
                    }
                }
            }

            try {
                foreach ($envFile in $versionEnvFiles) {
                    Write-Log -Level "INFO" -Message "Temporarily setting VITE_APP_VERSION=$bareVersion in $($envFile.FilePath)"
                    Set-EnvVersionValue -FilePath $envFile.FilePath -Version $bareVersion
                }

                $primaryRef = "${baseName}:$($imageTags[0])"
                Write-Log -Level "STEP" -Message "Building $primaryRef ..."
                docker build -t $primaryRef -f $dockerfilePath $imgContextPath
                if ($LASTEXITCODE -ne 0) {
                    throw "Docker build failed for $primaryRef"
                }

                Write-Log -Level "STEP" -Message "Pushing $primaryRef ..."
                docker push $primaryRef
                if ($LASTEXITCODE -ne 0) {
                    throw "Docker push failed for $primaryRef"
                }

                for ($ti = 1; $ti -lt $imageTags.Count; $ti++) {
                    $aliasRef = "${baseName}:$($imageTags[$ti])"
                    Write-Log -Level "STEP" -Message "Tagging and pushing $aliasRef ..."
                    docker tag $primaryRef $aliasRef
                    if ($LASTEXITCODE -ne 0) {
                        throw "Docker tag failed: $primaryRef -> $aliasRef"
                    }
                    docker push $aliasRef
                    if ($LASTEXITCODE -ne 0) {
                        throw "Docker push failed for $aliasRef"
                    }
                }
            }
            finally {
                foreach ($envFile in $versionEnvFiles) {
                    if (Test-Path -LiteralPath $envFile.BackupPath -PathType Leaf) {
                        Move-Item -LiteralPath $envFile.BackupPath -Destination $envFile.FilePath -Force
                    }
                }
                foreach ($envFile in $versionEnvFiles) {
                    if (Test-Path -LiteralPath $envFile.BackupPath -PathType Leaf) {
                        Remove-Item -LiteralPath $envFile.BackupPath -Force -ErrorAction SilentlyContinue
                    }
                }
            }
        }
    }
    finally {
        docker logout $registryUrl 2>&1 | Out-Null
    }

    Write-Log -Level "OK" -Message "  Docker push completed."
    $shared | Add-Member -NotePropertyName publishCompleted -NotePropertyValue $true -Force
}

Export-ModuleMember -Function Invoke-Plugin
