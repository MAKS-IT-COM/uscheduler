#requires -Version 7.0
#requires -PSEdition Core

<#
.SYNOPSIS
    Store MSIX plugin for a published win-* .NET desktop app (Community).

.DESCRIPTION
    Packs the win-* DotNetPublish folder into a full-trust .msix and signs it
    with a short-lived self-signed certificate whose subject is `publisher`.
    The Microsoft Store re-signs the package; this signature is only the upload
    envelope. The .msix is not a GitHub release asset and is not added to the
    portable zip. Requires makeappx.exe and signtool.exe from the Windows SDK.
#>

if (-not (Get-Command Import-PluginDependency -ErrorAction SilentlyContinue)) {
    $srcDir = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    $pluginSupportModulePath = Join-Path $srcDir "modules/Engine/PluginSupport.psm1"
    if (Test-Path $pluginSupportModulePath -PathType Leaf) {
        Import-Module $pluginSupportModulePath -Force -Global -ErrorAction Stop
    }
}

function Get-WindowsSdkToolPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FileName
    )

    $roots = @(
        ${env:ProgramFiles(x86)},
        $env:ProgramFiles
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

    foreach ($root in $roots) {
        $bin = Join-Path $root 'Windows Kits\10\bin'
        if (-not (Test-Path -LiteralPath $bin -PathType Container)) {
            continue
        }

        $versions = @(
            Get-ChildItem -LiteralPath $bin -Directory |
                Where-Object { $_.Name -match '^10\.' } |
                Sort-Object { try { [version]$_.Name } catch { [version]'0.0' } } -Descending
        )
        foreach ($version in $versions) {
            $candidate = Join-Path $version.FullName "x64\$FileName"
            if (Test-Path -LiteralPath $candidate -PathType Leaf) {
                return $candidate
            }
        }
    }

    return $null
}

function Get-MsixToolCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FileName,

        [Parameter(Mandatory = $true)]
        [string]$StubName
    )

    if (Test-ExternalCommandTestHandler) {
        return $StubName
    }

    $path = Get-WindowsSdkToolPath -FileName $FileName
    if ([string]::IsNullOrWhiteSpace($path)) {
        throw "Windows SDK tool '$FileName' was not found. Install the Windows 10 SDK so $FileName is under 'Windows Kits\10\bin\<version>\x64'."
    }

    return $path
}

function Invoke-MsixSign {
    param(
        [Parameter(Mandatory = $true)]
        [string]$MsixPath,

        [Parameter(Mandatory = $true)]
        [string]$Publisher,

        [Parameter(Mandatory = $true)]
        [string]$SignTool
    )

    $thumb = 'TEST'
    $created = $false
    try {
        if (-not (Test-ExternalCommandTestHandler)) {
            $cert = New-SelfSignedCertificate `
                -Type Custom `
                -Subject $Publisher `
                -KeyUsage DigitalSignature `
                -KeyAlgorithm RSA `
                -KeyLength 2048 `
                -FriendlyName 'MaksIT MsixPack ephemeral' `
                -CertStoreLocation 'Cert:\CurrentUser\My' `
                -TextExtension @('2.5.29.37={text}1.3.6.1.5.5.7.3.3') `
                -NotAfter (Get-Date).AddDays(1)
            $thumb = $cert.Thumbprint
            $created = $true
        }

        Invoke-ExternalCommand -Name $SignTool -ArgumentList @(
            'sign', '/fd', 'SHA256', '/sha1', $thumb,
            '/tr', 'http://timestamp.digicert.com', '/td', 'SHA256',
            $MsixPath
        ) | Out-Null
    }
    finally {
        if ($created -and -not [string]::IsNullOrWhiteSpace($thumb)) {
            $certPath = Join-Path 'Cert:\CurrentUser\My' $thumb
            if (Test-Path -LiteralPath $certPath) {
                Remove-Item -LiteralPath $certPath -Force
            }
        }
    }
}

function Invoke-Plugin {
    param(
        [Parameter(Mandatory = $true)]
        $Settings
    )

    Import-PluginDependency -ModuleName "Logging" -RequiredCommand "Write-Log"
    Import-PluginDependency -ModuleName "EngineContext" -RequiredCommand "Set-EngineFact"
    Import-PluginDependency -ModuleName "ExternalCommandSupport" -RequiredCommand "Invoke-ExternalCommand"
    Import-PluginDependency -ModuleName "DesktopPackSupport" -RequiredCommand "New-MsixManifestXml"

    if (-not $IsWindows -and -not (Test-ExternalCommandTestHandler)) {
        throw "MsixPack requires Windows (Windows SDK makeappx.exe and signtool.exe)."
    }

    $pluginSettings = $Settings
    $sharedSettings = $Settings.context
    $scriptDir = [string]$sharedSettings.scriptDir
    $version = [string]$sharedSettings.version
    $artifactsDirectory = [string]$sharedSettings.artifactsDirectory

    if ([string]::IsNullOrWhiteSpace($version)) {
        throw "MsixPack requires a release version in the shared context (DotNetReleaseVersion)."
    }

    if ([string]::IsNullOrWhiteSpace($artifactsDirectory)) {
        throw "MsixPack requires an artifacts directory in the shared context."
    }

    $packageName = [string](Get-PluginPropertyValue -PluginSettings $pluginSettings -Name 'packageName')
    $publisher = [string](Get-PluginPropertyValue -PluginSettings $pluginSettings -Name 'publisher')
    $executableName = [string](Get-PluginPropertyValue -PluginSettings $pluginSettings -Name 'executableName')
    if ([string]::IsNullOrWhiteSpace($packageName)) {
        throw "MsixPack requires packageName."
    }

    if ([string]::IsNullOrWhiteSpace($publisher) -or $publisher -eq 'CN=PartnerCenter') {
        throw "MsixPack requires publisher set to the Partner Center package identity (CN=...)."
    }

    if ($publisher -notmatch '(?i)(^|,)\s*CN=') {
        throw "MsixPack publisher must be a distinguished name starting with CN=: $publisher"
    }

    if ([string]::IsNullOrWhiteSpace($executableName)) {
        throw "MsixPack requires executableName."
    }

    Assert-MsixPackageName -PackageName $packageName
    $packageVersion = ConvertTo-MsixPackageVersion -Version $version

    $displayName = [string](Get-PluginPropertyValue -PluginSettings $pluginSettings -Name 'displayName' -Default $packageName)
    $publisherDisplayName = [string](Get-PluginPropertyValue -PluginSettings $pluginSettings -Name 'publisherDisplayName' -Default 'MaksIT')
    $description = [string](Get-PluginPropertyValue -PluginSettings $pluginSettings -Name 'description' -Default '')
    $language = [string](Get-PluginPropertyValue -PluginSettings $pluginSettings -Name 'language' -Default 'en-us')
    $runtimeIdentifier = [string](Get-PluginPropertyValue -PluginSettings $pluginSettings -Name 'runtimeIdentifier' -Default 'win-x64')
    $architecture = Get-WixArchitectureFromRuntimeIdentifier -RuntimeIdentifier $runtimeIdentifier
    $publishDirSetting = [string](Get-PluginPropertyValue -PluginSettings $pluginSettings -Name 'publishDir')
    $iconSetting = [string](Get-PluginPropertyValue -PluginSettings $pluginSettings -Name 'iconPath')

    if (-not (Test-Path -LiteralPath $artifactsDirectory -PathType Container)) {
        New-Item -ItemType Directory -Path $artifactsDirectory | Out-Null
    }

    $publishDirectory = Resolve-DesktopPublishDirectory `
        -Context $sharedSettings `
        -RuntimeIdentifier $runtimeIdentifier `
        -PublishDir $publishDirSetting `
        -ScriptDir $scriptDir

    $null = Resolve-DesktopExecutablePath `
        -PublishDirectory $publishDirectory `
        -ExecutableName $executableName `
        -Windows

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
    if ([string]::IsNullOrWhiteSpace($iconPath)) {
        $fallback = Join-Path $PSScriptRoot 'brand\mark.png'
        if (Test-Path -LiteralPath $fallback -PathType Leaf) {
            $iconPath = $fallback
        }
    }

    if ([string]::IsNullOrWhiteSpace($iconPath) -or -not (Test-Path -LiteralPath $iconPath -PathType Leaf)) {
        throw "MsixPack iconPath not found: $iconSetting"
    }

    $safeName = ($packageName -replace '[^A-Za-z0-9._-]', '-').Trim('-')
    $namePattern = [string](Get-PluginPropertyValue -PluginSettings $pluginSettings -Name 'msixNamePattern' -Default '{name}-{version}.msix')
    $msixFileName = $namePattern.Replace('{version}', $version).Replace('{name}', $safeName)
    $msixPath = Join-Path $artifactsDirectory $msixFileName

    $stageDir = Join-Path $artifactsDirectory '.msix-stage'
    if (Test-Path -LiteralPath $stageDir) {
        Remove-Item -LiteralPath $stageDir -Recurse -Force
    }

    $layout = Join-Path $stageDir 'layout'
    New-Item -ItemType Directory -Path $layout | Out-Null
    Copy-Item -Path (Join-Path $publishDirectory '*') -Destination $layout -Recurse -Force

    $manifest = New-MsixManifestXml `
        -PackageName $packageName `
        -Publisher $publisher `
        -PackageVersion $packageVersion `
        -ProcessorArchitecture $architecture `
        -DisplayName $displayName `
        -PublisherDisplayName $publisherDisplayName `
        -ExecutableName $executableName `
        -Description $description `
        -Language $language
    [System.IO.File]::WriteAllText((Join-Path $layout 'AppxManifest.xml'), $manifest, [System.Text.UTF8Encoding]::new($false))
    Copy-MsixPackageLogos -IconPath $iconPath -AssetsDirectory (Join-Path $layout 'Assets')

    $makeAppx = Get-MsixToolCommand -FileName 'makeappx.exe' -StubName 'makeappx'
    $signTool = Get-MsixToolCommand -FileName 'signtool.exe' -StubName 'signtool'

    if (Test-Path -LiteralPath $msixPath -PathType Leaf) {
        Remove-Item -LiteralPath $msixPath -Force
    }

    Write-Log -Level "STEP" -Message "Packing MSIX for '$displayName' ($architecture, $packageVersion)..."
    Invoke-ExternalCommand -Name $makeAppx -ArgumentList @('pack', '/d', $layout, '/p', $msixPath, '/o') | Out-Null
    if (-not (Test-Path -LiteralPath $msixPath -PathType Leaf)) {
        throw "makeappx completed but MSIX was not produced: $msixPath"
    }

    Write-Log -Level "STEP" -Message "Signing MSIX with an ephemeral certificate ($publisher)..."
    Invoke-MsixSign -MsixPath $msixPath -Publisher $publisher -SignTool $signTool

    if (Test-Path -LiteralPath $stageDir) {
        Remove-Item -LiteralPath $stageDir -Recurse -Force
    }

    Set-EngineFact -Context $sharedSettings -Namespace 'desktop' -Name 'msixPath' -Value $msixPath -Overwrite Replace
    Write-Log -Level "OK" -Message "  Store MSIX ready: $msixPath"
}

Export-ModuleMember -Function Invoke-Plugin
