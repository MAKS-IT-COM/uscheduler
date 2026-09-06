#requires -Version 7.0
#requires -PSEdition Core

<#
.SYNOPSIS
    Windows installer plugin for published .NET desktop apps (Community).

.DESCRIPTION
    Harvests a win-* (or sole) DotNetPublish folder into a WiX MSI, then wraps
    it in a Burn bootstrapper .exe. The .exe is the GitHub asset; the MSI/WXS
    stay in a staging folder and are not added to the portable zip.
    Requires the WiX CLI (`dotnet tool install -g wix`). WiX v7: accept the
    OSMF EULA (`wix eula accept wix7` or `-acceptEula wix7`) and
    `wix extension add -g WixToolset.BootstrapperApplications.wixext`.
    Reopen the shell so `%USERPROFILE%\.dotnet\tools` is on PATH.
#>

if (-not (Get-Command Import-PluginDependency -ErrorAction SilentlyContinue)) {
    $srcDir = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
        $pluginSupportModulePath = Join-Path $srcDir "modules/Engine/PluginSupport.psm1"
    if (Test-Path $pluginSupportModulePath -PathType Leaf) {
        Import-Module $pluginSupportModulePath -Force -Global -ErrorAction Stop
    }
}

function Test-WixMissingException {
    param(
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.ErrorRecord]$ErrorRecord
    )

    $message = [string]$ErrorRecord.Exception.Message
    if ($ErrorRecord.Exception -is [System.Management.Automation.CommandNotFoundException]) {
        return $true
    }

    return ($message -match '(?i)(not recognized|command not found|The term .+ is not recognized|marked unavailable)')
}

function Get-WixMissingInstallMessage {
    return "WiX CLI ('wix') is not on PATH. Install with: dotnet tool install -g wix. For WiX v7 also run: wix eula accept wix7; wix extension add -g WixToolset.BootstrapperApplications.wixext. Reopen the terminal so %USERPROFILE%\.dotnet\tools is on PATH."
}

function Get-WixCliVersionText {
    $raw = Invoke-ExternalCommand -Name wix -ArgumentList @('--version')
    return ((@($raw) | ForEach-Object { [string]$_ }) -join '').Trim()
}

function Get-WixAcceptEulaArguments {
    param(
        [Parameter(Mandatory = $false)]
        [string]$VersionText
    )

    if ($VersionText -match '^7\.') {
        return @('-acceptEula', 'wix7')
    }

    return @()
}

function Get-WixBundleExtensionName {
    param(
        [Parameter(Mandatory = $false)]
        [string]$VersionText
    )

    if ($VersionText -match '^[5-9]\.') {
        return 'WixToolset.BootstrapperApplications.wixext'
    }

    return 'WixToolset.Bal.wixext'
}

function Invoke-Plugin {
    param(
        [Parameter(Mandatory = $true)]
        $Settings
    )

    Import-PluginDependency -ModuleName "Logging" -RequiredCommand "Write-Log"
    Import-PluginDependency -ModuleName "EngineContext" -RequiredCommand "Add-ReleaseAssetPaths"
    Import-PluginDependency -ModuleName "ExternalCommandSupport" -RequiredCommand "Invoke-ExternalCommand"
    Import-PluginDependency -ModuleName "DesktopPackSupport" -RequiredCommand "New-WixPackageXml"

    $pluginSettings = $Settings
    $sharedSettings = $Settings.context
    $scriptDir = $sharedSettings.scriptDir
    $version = [string]$sharedSettings.version
    $artifactsDirectory = $sharedSettings.artifactsDirectory

    $appName = [string](Get-PluginPropertyValue -PluginSettings $pluginSettings -Name 'appName')
    $upgradeCodeRaw = [string](Get-PluginPropertyValue -PluginSettings $pluginSettings -Name 'upgradeCode')
    if ([string]::IsNullOrWhiteSpace($appName)) {
        throw "WindowsInstaller plugin requires appName."
    }

    if ([string]::IsNullOrWhiteSpace($upgradeCodeRaw)) {
        throw "WindowsInstaller plugin requires a stable upgradeCode GUID (per product, never change it)."
    }

    $upgradeCode = [guid]$upgradeCodeRaw
    $manufacturer = [string](Get-PluginPropertyValue -PluginSettings $pluginSettings -Name 'manufacturer' -Default 'MaksIT')
    $runtimeIdentifier = [string](Get-PluginPropertyValue -PluginSettings $pluginSettings -Name 'runtimeIdentifier' -Default 'win-x64')
    $installScope = [string](Get-PluginPropertyValue -PluginSettings $pluginSettings -Name 'installScope' -Default 'perMachine')
    $installFolderName = [string](Get-PluginPropertyValue -PluginSettings $pluginSettings -Name 'installFolderName')
    $executableName = [string](Get-PluginPropertyValue -PluginSettings $pluginSettings -Name 'executableName')
    $publishDirSetting = [string](Get-PluginPropertyValue -PluginSettings $pluginSettings -Name 'publishDir')
    $iconSetting = [string](Get-PluginPropertyValue -PluginSettings $pluginSettings -Name 'iconPath')
    $logoSetting = [string](Get-PluginPropertyValue -PluginSettings $pluginSettings -Name 'logoPath')
    $logoSideSetting = [string](Get-PluginPropertyValue -PluginSettings $pluginSettings -Name 'logoSidePath')
    $themeSetting = [string](Get-PluginPropertyValue -PluginSettings $pluginSettings -Name 'themePath')

    if ([string]::IsNullOrWhiteSpace([string]$artifactsDirectory)) {
        throw "WindowsInstaller plugin requires an artifacts directory in the shared context."
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
        -ExecutableName $executableName `
        -Windows

    $brandDir = Join-Path $PSScriptRoot 'brand'

    $resolvePackPath = {
        param([string]$Setting)
        if ([string]::IsNullOrWhiteSpace($Setting)) {
            return $null
        }

        if ([System.IO.Path]::IsPathRooted($Setting)) {
            return $Setting
        }

        return [System.IO.Path]::GetFullPath((Join-Path $scriptDir $Setting))
    }

    $iconPath = & $resolvePackPath $iconSetting
    if (-not [string]::IsNullOrWhiteSpace($iconSetting) -and -not (Test-Path -LiteralPath $iconPath -PathType Leaf)) {
        throw "WindowsInstaller iconPath not found: $iconPath"
    }

    if ([string]::IsNullOrWhiteSpace($iconPath)) {
        $fallbackIcon = Join-Path $brandDir 'mark.ico'
        if (Test-Path -LiteralPath $fallbackIcon -PathType Leaf) {
            $iconPath = $fallbackIcon
        }
    }

    $logoPath = & $resolvePackPath $logoSetting
    if (-not [string]::IsNullOrWhiteSpace($logoSetting) -and -not (Test-Path -LiteralPath $logoPath -PathType Leaf)) {
        throw "WindowsInstaller logoPath not found: $logoPath"
    }

    if ([string]::IsNullOrWhiteSpace($logoPath)) {
        $fallbackLogo = Join-Path $brandDir 'logo-64.png'
        if (Test-Path -LiteralPath $fallbackLogo -PathType Leaf) {
            $logoPath = $fallbackLogo
        }
    }

    $logoSidePath = & $resolvePackPath $logoSideSetting
    if (-not [string]::IsNullOrWhiteSpace($logoSideSetting) -and -not (Test-Path -LiteralPath $logoSidePath -PathType Leaf)) {
        throw "WindowsInstaller logoSidePath not found: $logoSidePath"
    }

    if ([string]::IsNullOrWhiteSpace($logoSidePath)) {
        $fallbackSide = Join-Path $brandDir 'sidebar.png'
        if (Test-Path -LiteralPath $fallbackSide -PathType Leaf) {
            $logoSidePath = $fallbackSide
        }
    }

    $themePath = & $resolvePackPath $themeSetting
    if (-not [string]::IsNullOrWhiteSpace($themeSetting) -and -not (Test-Path -LiteralPath $themePath -PathType Leaf)) {
        throw "WindowsInstaller themePath not found: $themePath"
    }

    if ([string]::IsNullOrWhiteSpace($themePath)) {
        $fallbackTheme = Join-Path $brandDir 'HyperlinkSidebarTheme.xml'
        if (Test-Path -LiteralPath $fallbackTheme -PathType Leaf) {
            $themePath = $fallbackTheme
        }
    }

    $productVersion = Get-MsiProductVersion -Version $version
    $safeName = ($appName -replace '[^A-Za-z0-9._-]', '-').Trim('-')
    $exeNamePattern = [string](Get-PluginPropertyValue -PluginSettings $pluginSettings -Name 'exeNamePattern' -Default '{name}-{version}.exe')
    $exeFileName = $exeNamePattern.Replace('{version}', $version).Replace('{name}', $safeName)
    $exePath = Join-Path $artifactsDirectory $exeFileName

    $stageDir = Join-Path $artifactsDirectory '.wix-stage'
    if (Test-Path -LiteralPath $stageDir) {
        Remove-Item -LiteralPath $stageDir -Recurse -Force
    }
    New-Item -ItemType Directory -Path $stageDir | Out-Null

    $wxsPath = Join-Path $stageDir ($safeName + '-' + $version + '.wxs')
    $msiPath = Join-Path $stageDir ($safeName + '-' + $version + '.msi')
    $bundleWxsPath = Join-Path $stageDir ($safeName + '-' + $version + '-bundle.wxs')

    Write-Log -Level "STEP" -Message "Generating WiX source for '$appName' from $publishDirectory"
    $xml = New-WixPackageXml `
        -AppName $appName `
        -Manufacturer $manufacturer `
        -ProductVersion $productVersion `
        -UpgradeCode $upgradeCode `
        -PublishDirectory $publishDirectory `
        -ExecutablePath $executablePath `
        -InstallScope $installScope `
        -InstallFolderName $installFolderName `
        -IconPath $iconPath

    $xml.Save($wxsPath)
    Write-Log -Level "OK" -Message "  WiX source: $wxsPath"

    try {
        $wixVersion = Get-WixCliVersionText
    }
    catch {
        if (Test-WixMissingException -ErrorRecord $_) {
            throw (Get-WixMissingInstallMessage)
        }

        throw
    }

    $eulaArgs = @(Get-WixAcceptEulaArguments -VersionText $wixVersion)
    $bundleExt = Get-WixBundleExtensionName -VersionText $wixVersion

    Write-Log -Level "STEP" -Message "Building MSI with WiX..."
    try {
        Invoke-ExternalCommand -Name wix -ArgumentList (@('build') + $eulaArgs + @($wxsPath, '-o', $msiPath)) | Out-Null
    }
    catch {
        if (Test-WixMissingException -ErrorRecord $_) {
            throw (Get-WixMissingInstallMessage)
        }

        throw
    }

    if (-not (Test-Path -LiteralPath $msiPath -PathType Leaf)) {
        throw "WiX completed but MSI was not produced: $msiPath"
    }

    $bundleXml = New-WixBundleXml `
        -AppName $appName `
        -Manufacturer $manufacturer `
        -ProductVersion $productVersion `
        -UpgradeCode $upgradeCode `
        -MsiPath $msiPath `
        -IconPath $iconPath `
        -LogoPath $logoPath `
        -LogoSidePath $logoSidePath `
        -ThemePath $themePath `
        -InstallScope $installScope `
        -InstallFolderName $installFolderName
    [System.IO.File]::WriteAllText($bundleWxsPath, $bundleXml, [System.Text.UTF8Encoding]::new($false))

    if (Test-Path -LiteralPath $exePath -PathType Leaf) {
        Remove-Item -LiteralPath $exePath -Force
    }

    Write-Log -Level "STEP" -Message "Building Windows installer exe..."
    try {
        Invoke-ExternalCommand -Name wix -ArgumentList (@('build') + $eulaArgs + @($bundleWxsPath, '-ext', $bundleExt, '-o', $exePath)) | Out-Null
    }
    catch {
        if (Test-WixMissingException -ErrorRecord $_) {
            throw (Get-WixMissingInstallMessage)
        }

        throw
    }

    if (-not (Test-Path -LiteralPath $exePath -PathType Leaf)) {
        throw "WiX completed but installer exe was not produced: $exePath"
    }

    Write-Log -Level "OK" -Message "  Windows installer ready: $exePath"
    Set-EngineState -Context $sharedSettings -Name 'releaseDir' -Value $artifactsDirectory
    Set-EngineFact -Context $sharedSettings -Namespace 'desktop' -Name 'windowsInstallerPath' -Value $exePath -Overwrite Replace
    Add-ReleaseAssetPaths -Context $sharedSettings -Path @($exePath)
}

Export-ModuleMember -Function Invoke-Plugin
