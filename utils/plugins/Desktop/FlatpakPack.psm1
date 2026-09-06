#requires -Version 7.0
#requires -PSEdition Core

<#
.SYNOPSIS
    Linux Flatpak pack plugin for published .NET desktop apps (Community).

.DESCRIPTION
    Stages a linux-* DotNetPublish folder into a Flatpak layout (manifest,
    desktop file, metainfo, launch script). Prefers Flathub org.flatpak.Builder
    (current builder) over distro flatpak-builder. On Windows, native builder
    is tried first; if missing, the plugin builds via a pinned WSL distro
    (default Debian) on the Linux filesystem, then copies the bundle back.
    Docker Desktop WSL distros are never used. whenBuilderMissing skip|fail
    applies when neither native nor WSL builder is available.
#>

if (-not (Get-Command Import-PluginDependency -ErrorAction SilentlyContinue)) {
    $srcDir = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
        $pluginSupportModulePath = Join-Path $srcDir "modules/Engine/PluginSupport.psm1"
    if (Test-Path $pluginSupportModulePath -PathType Leaf) {
        Import-Module $pluginSupportModulePath -Force -Global -ErrorAction Stop
    }
}

function Get-FlatpakWhenBuilderMissing {
    param($PluginSettings)

    $value = [string](Get-PluginPropertyValue -PluginSettings $PluginSettings -Name 'whenBuilderMissing' -Default 'skip')
    if ($value -notin @('skip', 'fail')) {
        throw "FlatpakPack whenBuilderMissing must be 'skip' or 'fail'."
    }

    return $value
}

function Test-FlatpakBuilderMissingException {
    param(
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.ErrorRecord]$ErrorRecord
    )

    $message = [string]$ErrorRecord.Exception.Message
    if ($message -match '(?i)bash: line \d+') {
        return $false
    }

    if ($ErrorRecord.Exception -is [System.Management.Automation.CommandNotFoundException]) {
        return $true
    }

    if ($message -match '(?i)(not recognized|command not found|The term .+ is not recognized|marked unavailable)') {
        return $true
    }

    return $false
}

function Test-WslFallbackSkippable {
    param(
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.ErrorRecord]$ErrorRecord
    )

    if (Test-FlatpakBuilderMissingException -ErrorRecord $ErrorRecord) {
        return $true
    }

    $message = [string]$ErrorRecord.Exception.Message
    if ($message -match "(?i)WSL distro '.+' is not installed") {
        return $true
    }

    return $false
}

function Get-WslInstalledDistroNames {
    $output = Invoke-ExternalCommand -Name wsl -ArgumentList @('-l', '-q') -ThrowOnError:$false
    return @(ConvertFrom-WslListOutput -InputObject $output)
}

function Invoke-FlatpakBundleViaWsl {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Distro,

        [Parameter(Mandatory = $true)]
        [string]$WindowsStageRoot,

        [Parameter(Mandatory = $true)]
        [string]$WindowsBundlePath,

        [Parameter(Mandatory = $true)]
        [string]$AppId
    )

    Assert-WslDistroAllowedForFlatpak -Distro $Distro
    $installed = @(Get-WslInstalledDistroNames)
    if (-not (Test-WslDistroInstalled -Distro $Distro -InstalledNames $installed)) {
        throw "WSL distro '$Distro' is not installed. Install Debian with: wsl --install Debian --no-launch --web-download"
    }

    $script = ConvertTo-UnixLineEndings -Value (
        New-WslFlatpakBuildScript `
            -WindowsStageRoot $WindowsStageRoot `
            -WindowsBundlePath $WindowsBundlePath `
            -AppId $AppId
    )
    if (-not $script.EndsWith("`n")) {
        $script += "`n"
    }

    $tempScript = Join-Path ([System.IO.Path]::GetTempPath()) ("maksit-flatpak-" + [guid]::NewGuid().ToString('N') + ".sh")
    try {
        [System.IO.File]::WriteAllBytes($tempScript, [System.Text.UTF8Encoding]::new($false).GetBytes($script))
        $wslScript = ConvertTo-WslMountPath -WindowsPath $tempScript
        Invoke-ExternalCommand -Name wsl -ArgumentList @('-d', $Distro, '--', 'bash', $wslScript) | Out-Null
    }
    finally {
        if (Test-Path -LiteralPath $tempScript -PathType Leaf) {
            Remove-Item -LiteralPath $tempScript -Force -ErrorAction SilentlyContinue
        }
    }
}

function Invoke-HostFlatpakBuilder {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepoDir,

        [Parameter(Mandatory = $true)]
        [string]$BuildDir,

        [Parameter(Mandatory = $true)]
        [string]$ManifestPath
    )

    $hasFlathubBuilder = $false
    try {
        Invoke-ExternalCommand -Name flatpak -ArgumentList @('info', 'org.flatpak.Builder') -ThrowOnError:$false | Out-Null
        $hasFlathubBuilder = ($global:LASTEXITCODE -eq 0)
    }
    catch {
        if (-not (Test-FlatpakBuilderMissingException -ErrorRecord $_)) {
            throw
        }
    }

    if ($hasFlathubBuilder) {
        $stageRoot = [System.IO.Path]::GetDirectoryName($ManifestPath)
        Invoke-ExternalCommand -Name flatpak -ArgumentList @(
            'run',
            '--filesystem=host',
            '--share=network',
            "--cwd=$stageRoot",
            'org.flatpak.Builder',
            '--disable-rofiles-fuse',
            "--repo=$RepoDir",
            '--force-clean',
            $BuildDir,
            $ManifestPath
        ) | Out-Null
        return
    }

    Invoke-ExternalCommand -Name flatpak-builder -ArgumentList @(
        '--disable-rofiles-fuse',
        "--repo=$RepoDir",
        '--force-clean',
        $BuildDir,
        $ManifestPath
    ) | Out-Null
}

function Invoke-Plugin {
    param(
        [Parameter(Mandatory = $true)]
        $Settings
    )

    Import-PluginDependency -ModuleName "Logging" -RequiredCommand "Write-Log"
    Import-PluginDependency -ModuleName "EngineContext" -RequiredCommand "Add-ReleaseAssetPaths"
    Import-PluginDependency -ModuleName "ExternalCommandSupport" -RequiredCommand "Invoke-ExternalCommand"
    Import-PluginDependency -ModuleName "DesktopPackSupport" -RequiredCommand "New-WslFlatpakBuildScript"

    $pluginSettings = $Settings
    $sharedSettings = $Settings.context
    $scriptDir = $sharedSettings.scriptDir
    $version = [string]$sharedSettings.version
    $artifactsDirectory = $sharedSettings.artifactsDirectory

    $appId = [string](Get-PluginPropertyValue -PluginSettings $pluginSettings -Name 'appId')
    $appName = [string](Get-PluginPropertyValue -PluginSettings $pluginSettings -Name 'appName')
    if ([string]::IsNullOrWhiteSpace($appId)) {
        throw "FlatpakPack plugin requires appId (reverse-DNS, e.g. com.maks_it.Wvc210)."
    }

    Assert-FlatpakAppId -AppId $appId

    if ([string]::IsNullOrWhiteSpace($appName)) {
        throw "FlatpakPack plugin requires appName."
    }

    $command = [string](Get-PluginPropertyValue -PluginSettings $pluginSettings -Name 'command')
    $executableName = [string](Get-PluginPropertyValue -PluginSettings $pluginSettings -Name 'executableName')
    $runtimeIdentifier = [string](Get-PluginPropertyValue -PluginSettings $pluginSettings -Name 'runtimeIdentifier' -Default 'linux-x64')
    $publishDirSetting = [string](Get-PluginPropertyValue -PluginSettings $pluginSettings -Name 'publishDir')
    $iconSetting = [string](Get-PluginPropertyValue -PluginSettings $pluginSettings -Name 'iconPath')
    $summary = [string](Get-PluginPropertyValue -PluginSettings $pluginSettings -Name 'summary' -Default $appName)
    $projectLicense = [string](Get-PluginPropertyValue -PluginSettings $pluginSettings -Name 'projectLicense' -Default 'MIT')
    $categories = [string](Get-PluginPropertyValue -PluginSettings $pluginSettings -Name 'categories' -Default 'Utility;')
    $runtime = [string](Get-PluginPropertyValue -PluginSettings $pluginSettings -Name 'runtime' -Default 'org.freedesktop.Platform')
    $runtimeVersion = [string](Get-PluginPropertyValue -PluginSettings $pluginSettings -Name 'runtimeVersion' -Default '24.08')
    $sdk = [string](Get-PluginPropertyValue -PluginSettings $pluginSettings -Name 'sdk' -Default 'org.freedesktop.Sdk')
    $whenBuilderMissing = Get-FlatpakWhenBuilderMissing -PluginSettings $pluginSettings
    $wslDistro = [string](Get-PluginPropertyValue -PluginSettings $pluginSettings -Name 'wslDistro' -Default 'Debian')
    $useWslSetting = Get-PluginPropertyValue -PluginSettings $pluginSettings -Name 'useWsl' -Default $null
    $useWsl = if ($null -eq $useWslSetting) { [bool]$IsWindows } else { [bool]$useWslSetting }
    $buildBundle = $true
    if ($pluginSettings.PSObject.Properties['buildBundle'] -and $null -ne $pluginSettings.buildBundle) {
        $buildBundle = [bool]$pluginSettings.buildBundle
    }

    $attachSourceZip = $false
    if ($pluginSettings.PSObject.Properties['attachSourceZip'] -and $null -ne $pluginSettings.attachSourceZip) {
        $attachSourceZip = [bool]$pluginSettings.attachSourceZip
    }

    $finishArgs = @(Get-DefaultFlatpakFinishArgs)
    if ($pluginSettings.PSObject.Properties['finishArgs'] -and $null -ne $pluginSettings.finishArgs) {
        $finishArgs = @($pluginSettings.finishArgs | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    }

    if ([string]::IsNullOrWhiteSpace([string]$artifactsDirectory)) {
        throw "FlatpakPack plugin requires an artifacts directory in the shared context."
    }

    if (-not (Test-Path -LiteralPath $artifactsDirectory -PathType Container)) {
        New-Item -ItemType Directory -Path $artifactsDirectory | Out-Null
    }

    $publishDirectory = Resolve-DesktopPublishDirectory `
        -Context $sharedSettings `
        -RuntimeIdentifier $runtimeIdentifier `
        -PublishDir $publishDirSetting `
        -ScriptDir $scriptDir

    $executablePath = Resolve-DesktopExecutablePath `
        -PublishDirectory $publishDirectory `
        -ExecutableName $executableName
    $executableFileName = [System.IO.Path]::GetFileName($executablePath)
    if ([string]::IsNullOrWhiteSpace($command)) {
        $command = $executableFileName
    }

    $moduleName = ($appId.Split('.') | Select-Object -Last 1).ToLowerInvariant()
    $stageRoot = Join-Path $artifactsDirectory "flatpak-$moduleName"
    if (Test-Path -LiteralPath $stageRoot) {
        Remove-Item -LiteralPath $stageRoot -Recurse -Force
    }

    $filesRoot = Join-Path $stageRoot 'files'
    $libDir = Join-Path $filesRoot "lib\$moduleName"
    $binDir = Join-Path $filesRoot 'bin'
    $shareAppDir = Join-Path $filesRoot 'share\applications'
    $shareMetaDir = Join-Path $filesRoot 'share\metainfo'
    $shareIconDir = Join-Path $filesRoot 'share\icons\hicolor\256x256\apps'
    New-Item -ItemType Directory -Path $libDir, $binDir, $shareAppDir, $shareMetaDir, $shareIconDir -Force | Out-Null

    Write-Log -Level "STEP" -Message "Staging Flatpak layout from $publishDirectory"
    Copy-Item -Path (Join-Path $publishDirectory '*') -Destination $libDir -Recurse -Force

    $launchScript = New-FlatpakLaunchScript -ModuleName $moduleName -ExecutableFileName $executableFileName
    $launchPath = Join-Path $binDir $command
    [System.IO.File]::WriteAllText($launchPath, $launchScript.Replace("`r`n", "`n"), [System.Text.UTF8Encoding]::new($false))

    $desktopPath = Join-Path $shareAppDir "$appId.desktop"
    [System.IO.File]::WriteAllText(
        $desktopPath,
        (New-FlatpakDesktopEntry -AppId $appId -AppName $appName -Command $command -Categories $categories).Replace("`r`n", "`n"),
        [System.Text.UTF8Encoding]::new($false)
    )

    $metaPath = Join-Path $shareMetaDir "$appId.metainfo.xml"
    [System.IO.File]::WriteAllText(
        $metaPath,
        (New-FlatpakMetainfoXml -AppId $appId -AppName $appName -Summary $summary -ProjectLicense $projectLicense).Replace("`r`n", "`n"),
        [System.Text.UTF8Encoding]::new($false)
    )

    if (-not [string]::IsNullOrWhiteSpace($iconSetting)) {
        $iconPath = if ([System.IO.Path]::IsPathRooted($iconSetting)) {
            $iconSetting
        }
        else {
            [System.IO.Path]::GetFullPath((Join-Path $scriptDir $iconSetting))
        }

        if (-not (Test-Path -LiteralPath $iconPath -PathType Leaf)) {
            throw "FlatpakPack iconPath not found: $iconPath"
        }

        if ([System.IO.Path]::GetExtension($iconPath) -ine '.png') {
            Write-Log -Level "WARN" -Message "  Flatpak icon should be PNG; skipping copy of $iconPath"
        }
        else {
            Copy-Item -LiteralPath $iconPath -Destination (Join-Path $shareIconDir "$appId.png") -Force
        }
    }

    $buildCommands = @(
        'mkdir -p /app/lib /app/share',
        "cp -a lib/$moduleName /app/lib/$moduleName",
        'cp -a share /app/share',
        "install -Dm755 bin/$command /app/bin/$command",
        "chmod +x /app/lib/$moduleName/$executableFileName"
    )

    $manifest = New-FlatpakManifestObject `
        -AppId $appId `
        -Command $command `
        -ModuleName $moduleName `
        -Runtime $runtime `
        -RuntimeVersion $runtimeVersion `
        -Sdk $sdk `
        -FinishArgs $finishArgs `
        -BuildCommands $buildCommands

    $manifestPath = Join-Path $stageRoot 'manifest.json'
    $manifestJson = $manifest | ConvertTo-Json -Depth 8
    [System.IO.File]::WriteAllText($manifestPath, $manifestJson, [System.Text.UTF8Encoding]::new($false))

    $bundleNamePattern = [string](Get-PluginPropertyValue -PluginSettings $pluginSettings -Name 'bundleNamePattern' -Default '{name}-{version}.flatpak')
    $safeName = ($appName -replace '[^A-Za-z0-9._-]', '-').Trim('-')
    $bundleFileName = $bundleNamePattern.Replace('{version}', $version).Replace('{id}', $appId).Replace('{name}', $safeName)
    $bundlePath = Join-Path $artifactsDirectory $bundleFileName

    $builderBlock = (Get-FlatpakBuilderShellLines) -join "`n"
    $buildScript = @"
#!/bin/sh
set -e
cd "`$(dirname "`$0")"
$builderBlock
flatpak build-bundle "`$ROOT/repo" "../$bundleFileName" "$appId"
"@
    [System.IO.File]::WriteAllText((Join-Path $stageRoot 'build-flatpak.sh'), $buildScript.Replace("`r`n", "`n"), [System.Text.UTF8Encoding]::new($false))

    $assetPaths = [System.Collections.Generic.List[string]]::new()

    if ($attachSourceZip) {
        $sourceZipPattern = [string](Get-PluginPropertyValue -PluginSettings $pluginSettings -Name 'sourceZipNamePattern' -Default '{id}-{version}-flatpak-src.zip')
        $sourceZipName = $sourceZipPattern.Replace('{version}', $version).Replace('{id}', $appId).Replace('{name}', $safeName)
        $sourceZipPath = Join-Path $artifactsDirectory $sourceZipName
        if (Test-Path -LiteralPath $sourceZipPath -PathType Leaf) {
            Remove-Item -LiteralPath $sourceZipPath -Force
        }

        Compress-Archive -Path $stageRoot -DestinationPath $sourceZipPath -CompressionLevel Optimal -Force
        Write-Log -Level "OK" -Message "  Flatpak source archive: $sourceZipPath"
        $assetPaths.Add($sourceZipPath)
        Set-EngineFact -Context $sharedSettings -Namespace 'desktop' -Name 'flatpakSourcePath' -Value $sourceZipPath -Overwrite Replace
    }

    if ($buildBundle) {
        Write-Log -Level "STEP" -Message "Building Flatpak bundle..."
        $buildDir = Join-Path $stageRoot 'build-dir'
        $repoDir = Join-Path $stageRoot 'repo'
        $built = $false
        try {
            Invoke-HostFlatpakBuilder -RepoDir $repoDir -BuildDir $buildDir -ManifestPath $manifestPath

            if (Test-Path -LiteralPath $bundlePath -PathType Leaf) {
                Remove-Item -LiteralPath $bundlePath -Force
            }

            Invoke-ExternalCommand -Name flatpak -ArgumentList @(
                'build-bundle',
                $repoDir,
                $bundlePath,
                $appId
            ) | Out-Null

            if (-not (Test-Path -LiteralPath $bundlePath -PathType Leaf)) {
                throw "flatpak build-bundle completed but bundle was not produced: $bundlePath"
            }

            $built = $true
        }
        catch {
            if (-not (Test-FlatpakBuilderMissingException -ErrorRecord $_)) {
                throw
            }

            Write-Log -Level "INFO" -Message "  Native Flatpak builder not available (Flathub org.flatpak.Builder or distro flatpak-builder)."
        }

        if (-not $built -and $useWsl -and $IsWindows) {
            try {
                Write-Log -Level "STEP" -Message "Building Flatpak bundle via WSL distro $wslDistro (Linux filesystem, not Docker Desktop)..."
                if (Test-Path -LiteralPath $bundlePath -PathType Leaf) {
                    Remove-Item -LiteralPath $bundlePath -Force
                }

                Invoke-FlatpakBundleViaWsl `
                    -Distro $wslDistro `
                    -WindowsStageRoot $stageRoot `
                    -WindowsBundlePath $bundlePath `
                    -AppId $appId

                if (-not (Test-Path -LiteralPath $bundlePath -PathType Leaf)) {
                    throw "WSL flatpak build-bundle completed but bundle was not produced: $bundlePath"
                }

                $built = $true
            }
            catch {
                if ($whenBuilderMissing -eq 'skip' -and (Test-WslFallbackSkippable -ErrorRecord $_)) {
                    Write-Log -Level "WARN" -Message "  WSL Flatpak builder not available ($($_.Exception.Message)); skipped bundle."
                }
                else {
                    throw
                }
            }
        }

        if ($built) {
            Write-Log -Level "OK" -Message "  Flatpak bundle ready: $bundlePath"
            $assetPaths.Add($bundlePath)
            Set-EngineFact -Context $sharedSettings -Namespace 'desktop' -Name 'flatpakBundlePath' -Value $bundlePath -Overwrite Replace
        }
        elseif ($whenBuilderMissing -eq 'fail') {
            throw "Flatpak builder is not available (Flathub org.flatpak.Builder, distro flatpak-builder, or WSL distro $wslDistro)."
        }
        elseif (-not $useWsl -or -not $IsWindows) {
            Write-Log -Level "WARN" -Message "  Flatpak builder not available; skipped bundle. Install Flathub org.flatpak.Builder (preferred) or distro flatpak-builder."
        }
    }

    Set-EngineState -Context $sharedSettings -Name 'releaseDir' -Value $artifactsDirectory
    if ($assetPaths.Count -gt 0) {
        Add-ReleaseAssetPaths -Context $sharedSettings -Path @($assetPaths)
    }
}

Export-ModuleMember -Function Invoke-Plugin
