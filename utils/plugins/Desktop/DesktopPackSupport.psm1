#requires -Version 7.0
#requires -PSEdition Core

<#
.SYNOPSIS
    Helpers for Community desktop pack plugins (Windows MSI, Linux Flatpak).
#>

function ConvertTo-WixIdentifier {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Value,

        [Parameter(Mandatory = $false)]
        [string]$Prefix = 'id'
    )

    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Value)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $hash = [System.BitConverter]::ToString($sha.ComputeHash($bytes)).Replace('-', '')
    }
    finally {
        $sha.Dispose()
    }

    return ($Prefix + $hash.Substring(0, 16))
}

function Get-DesktopInstallFolderName {
    param(
        [Parameter(Mandatory = $true)]
        [string]$AppName,

        [Parameter(Mandatory = $false)]
        [string]$Manufacturer,

        [Parameter(Mandatory = $false)]
        [string]$InstallFolderName
    )

    if (-not [string]::IsNullOrWhiteSpace($InstallFolderName)) {
        return $InstallFolderName.Trim()
    }

    $name = $AppName.Trim()
    $mfr = if ([string]::IsNullOrWhiteSpace($Manufacturer)) { '' } else { $Manufacturer.Trim() }
    if ($mfr.Length -gt 0 -and $name.StartsWith($mfr, [System.StringComparison]::OrdinalIgnoreCase)) {
        $rest = $name.Substring($mfr.Length).TrimStart([char[]]@(' ', '-', '.'))
        if (-not [string]::IsNullOrWhiteSpace($rest)) {
            return $rest
        }
    }

    return $name
}

function Get-MsiProductVersion {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Version
    )

    $numeric = $Version
    $plusIndex = $numeric.IndexOf('+')
    if ($plusIndex -ge 0) {
        $numeric = $numeric.Substring(0, $plusIndex)
    }

    $hyphenIndex = $numeric.IndexOf('-')
    if ($hyphenIndex -ge 0) {
        $numeric = $numeric.Substring(0, $hyphenIndex)
    }

    $parts = @($numeric.Split('.') | Where-Object { $_ -match '^\d+$' })
    if ($parts.Count -lt 2) {
        throw "Cannot derive an MSI ProductVersion from '$Version'. Expected semver with at least major.minor."
    }

    while ($parts.Count -lt 3) {
        $parts += '0'
    }

    if ($parts.Count -gt 4) {
        $parts = $parts[0..3]
    }

    return ($parts -join '.')
}

function Get-PluginPropertyValue {
    param(
        [Parameter(Mandatory = $true)]
        $PluginSettings,

        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $false)]
        $Default = $null
    )

    if ($PluginSettings.PSObject.Properties[$Name] -and $null -ne $PluginSettings.$Name) {
        $value = $PluginSettings.$Name
        if ($value -is [string] -and [string]::IsNullOrWhiteSpace($value)) {
            return $Default
        }

        return $value
    }

    return $Default
}

function Resolve-DesktopPublishDirectory {
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$Context,

        [Parameter(Mandatory = $true)]
        [string]$RuntimeIdentifier,

        [Parameter(Mandatory = $false)]
        [string]$PublishDir,

        [Parameter(Mandatory = $false)]
        [string]$ScriptDir
    )

    if (-not [string]::IsNullOrWhiteSpace($PublishDir)) {
        $resolved = $PublishDir
        if (-not [System.IO.Path]::IsPathRooted($resolved) -and -not [string]::IsNullOrWhiteSpace($ScriptDir)) {
            $resolved = [System.IO.Path]::GetFullPath((Join-Path $ScriptDir $PublishDir))
        }

        if (-not (Test-Path -LiteralPath $resolved -PathType Container)) {
            throw "Desktop publish directory not found: $resolved"
        }

        return $resolved
    }

    $outputs = @(Get-EngineFact -Context $Context -Namespace 'dotnet' -Name 'publishOutputs' -Default @())
    if ($outputs.Count -gt 0) {
        $exact = @(
            $outputs |
                Where-Object { [string]$_.runtimeIdentifier -eq $RuntimeIdentifier }
        )
        if ($exact.Count -gt 0) {
            return [string]$exact[0].directory
        }

        $family = $RuntimeIdentifier.Split('-')[0]
        if (-not [string]::IsNullOrWhiteSpace($family)) {
            $matchedFamily = @(
                $outputs |
                    Where-Object { ([string]$_.runtimeIdentifier).StartsWith("$family-", [System.StringComparison]::OrdinalIgnoreCase) }
            )
            if ($matchedFamily.Count -gt 0) {
                return [string]$matchedFamily[0].directory
            }
        }
    }

    $archiveInputs = @(Get-EngineFact -Context $Context -Namespace 'release' -Name 'archiveInputs' -Default @() -LegacyProperty @('releaseArchiveInputs'))
    $dirs = @(
        $archiveInputs |
            Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) -and (Test-Path -LiteralPath ([string]$_) -PathType Container) }
    )
    if ($dirs.Count -eq 1) {
        return [string]$dirs[0]
    }

    throw "Could not resolve a '$RuntimeIdentifier' publish directory. Run DotNetPublish with runtimeIdentifiers (or set publishDir)."
}

function Resolve-DesktopExecutablePath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$PublishDirectory,

        [Parameter(Mandatory = $false)]
        [string]$ExecutableName,

        [Parameter(Mandatory = $false)]
        [switch]$Windows
    )

    if (-not [string]::IsNullOrWhiteSpace($ExecutableName)) {
        $direct = Join-Path $PublishDirectory $ExecutableName
        if (Test-Path -LiteralPath $direct -PathType Leaf) {
            return $direct
        }

        $withExe = Join-Path $PublishDirectory ($ExecutableName + '.exe')
        if ($Windows -and (Test-Path -LiteralPath $withExe -PathType Leaf)) {
            return $withExe
        }

        throw "Executable '$ExecutableName' was not found in: $PublishDirectory"
    }

    $candidates = @()
    if ($Windows) {
        $candidates = @(Get-ChildItem -LiteralPath $PublishDirectory -File -Filter '*.exe' | Where-Object { $_.Name -notin @('createdump.exe') })
    }
    else {
        $candidates = @(
            Get-ChildItem -LiteralPath $PublishDirectory -File |
                Where-Object { [string]::IsNullOrWhiteSpace($_.Extension) }
        )
    }

    if ($candidates.Count -eq 1) {
        return $candidates[0].FullName
    }

    if ($candidates.Count -gt 1) {
        throw "Multiple executables found in '$PublishDirectory'. Set executableName."
    }

    throw "No executable found in '$PublishDirectory'. Set executableName."
}

function New-WixPackageXml {
    param(
        [Parameter(Mandatory = $true)]
        [string]$AppName,

        [Parameter(Mandatory = $true)]
        [string]$Manufacturer,

        [Parameter(Mandatory = $true)]
        [string]$ProductVersion,

        [Parameter(Mandatory = $true)]
        [guid]$UpgradeCode,

        [Parameter(Mandatory = $true)]
        [string]$PublishDirectory,

        [Parameter(Mandatory = $true)]
        [string]$ExecutablePath,

        [Parameter(Mandatory = $false)]
        [string]$InstallScope = 'perMachine',

        [Parameter(Mandatory = $false)]
        [string]$InstallFolderName,

        [Parameter(Mandatory = $false)]
        [string]$IconPath
    )

    $ns = 'http://wixtoolset.org/schemas/v4/wxs'
    $xml = New-Object System.Xml.XmlDocument
    $null = $xml.AppendChild($xml.CreateXmlDeclaration('1.0', 'utf-8', $null))
    $wix = $xml.CreateElement('Wix', $ns)
    $null = $xml.AppendChild($wix)

    $scope = if ($InstallScope -eq 'perMachine') { 'perMachine' } else { 'perUser' }
    $package = $xml.CreateElement('Package', $ns)
    $null = $package.SetAttribute('Name', $AppName)
    $null = $package.SetAttribute('Manufacturer', $Manufacturer)
    $null = $package.SetAttribute('Version', $ProductVersion)
    $null = $package.SetAttribute('UpgradeCode', $UpgradeCode.ToString('D'))
    $null = $package.SetAttribute('Scope', $scope)
    $null = $wix.AppendChild($package)

    $major = $xml.CreateElement('MajorUpgrade', $ns)
    $null = $major.SetAttribute('DowngradeErrorMessage', 'A newer version is already installed.')
    $null = $package.AppendChild($major)

    $media = $xml.CreateElement('MediaTemplate', $ns)
    $null = $media.SetAttribute('EmbedCab', 'yes')
    $null = $package.AppendChild($media)

    if (-not [string]::IsNullOrWhiteSpace($IconPath) -and (Test-Path -LiteralPath $IconPath -PathType Leaf)) {
        $icon = $xml.CreateElement('Icon', $ns)
        $null = $icon.SetAttribute('Id', 'AppIcon')
        $null = $icon.SetAttribute('SourceFile', $IconPath)
        $null = $package.AppendChild($icon)
        $prop = $xml.CreateElement('Property', $ns)
        $null = $prop.SetAttribute('Id', 'ARPPRODUCTICON')
        $null = $prop.SetAttribute('Value', 'AppIcon')
        $null = $package.AppendChild($prop)
    }

    $desktopProp = $xml.CreateElement('Property', $ns)
    $null = $desktopProp.SetAttribute('Id', 'INSTALLDESKTOPSHORTCUT')
    $null = $desktopProp.SetAttribute('Value', '0')
    $null = $package.AppendChild($desktopProp)

    $productFolder = Get-DesktopInstallFolderName `
        -AppName $AppName `
        -Manufacturer $Manufacturer `
        -InstallFolderName $InstallFolderName

    $stdLocal = $xml.CreateElement('StandardDirectory', $ns)
    $rootFolderId = if ($scope -eq 'perMachine') { 'ProgramFiles6432Folder' } else { 'LocalAppDataFolder' }
    $null = $stdLocal.SetAttribute('Id', $rootFolderId)
    $null = $package.AppendChild($stdLocal)

    $installParent = $stdLocal
    if (-not [string]::IsNullOrWhiteSpace($Manufacturer)) {
        $mfrDir = $xml.CreateElement('Directory', $ns)
        $null = $mfrDir.SetAttribute('Id', 'ManufacturerFolder')
        $null = $mfrDir.SetAttribute('Name', $Manufacturer)
        $null = $stdLocal.AppendChild($mfrDir)
        $installParent = $mfrDir
    }

    $installFolder = $xml.CreateElement('Directory', $ns)
    $null = $installFolder.SetAttribute('Id', 'INSTALLFOLDER')
    $null = $installFolder.SetAttribute('Name', $productFolder)
    $null = $installParent.AppendChild($installFolder)

    $stdMenu = $xml.CreateElement('StandardDirectory', $ns)
    $null = $stdMenu.SetAttribute('Id', 'ProgramMenuFolder')
    $null = $package.AppendChild($stdMenu)
    $menuDir = $xml.CreateElement('Directory', $ns)
    $null = $menuDir.SetAttribute('Id', 'AppShortcutFolder')
    $menuName = if ([string]::IsNullOrWhiteSpace($Manufacturer)) { $productFolder } else { $Manufacturer }
    $null = $menuDir.SetAttribute('Name', $menuName)
    $null = $stdMenu.AppendChild($menuDir)

    $stdDesktop = $xml.CreateElement('StandardDirectory', $ns)
    $null = $stdDesktop.SetAttribute('Id', 'DesktopFolder')
    $null = $package.AppendChild($stdDesktop)

    $dirNodes = @{
        '' = $installFolder
    }
    $componentIds = [System.Collections.Generic.List[string]]::new()

    $publishRoot = [System.IO.Path]::GetFullPath($PublishDirectory)
    $files = @(Get-ChildItem -LiteralPath $publishRoot -Recurse -File)
    if ($files.Count -eq 0) {
        throw "WindowsInstaller found no files to harvest in: $publishRoot"
    }

    foreach ($file in $files) {
        $relative = $file.FullName.Substring($publishRoot.Length).TrimStart('\', '/')
        $relativeDir = [System.IO.Path]::GetDirectoryName($relative)
        if ($null -eq $relativeDir) {
            $relativeDir = ''
        }

        $parent = $installFolder
        if (-not [string]::IsNullOrWhiteSpace($relativeDir)) {
            $parts = $relativeDir.Split([char[]]@('\', '/'), [System.StringSplitOptions]::RemoveEmptyEntries)
            $walk = ''
            foreach ($part in $parts) {
                $walk = if ($walk) { Join-Path $walk $part } else { $part }
                if (-not $dirNodes.ContainsKey($walk)) {
                    $child = $xml.CreateElement('Directory', $ns)
                    $null = $child.SetAttribute('Id', (ConvertTo-WixIdentifier -Value $walk -Prefix 'd'))
                    $null = $child.SetAttribute('Name', $part)
                    $null = $parent.AppendChild($child)
                    $dirNodes[$walk] = $child
                }

                $parent = $dirNodes[$walk]
            }
        }

        $component = $xml.CreateElement('Component', $ns)
        $componentId = ConvertTo-WixIdentifier -Value $relative -Prefix 'c'
        $null = $component.SetAttribute('Id', $componentId)
        $null = $component.SetAttribute('Guid', '*')
        $componentIds.Add($componentId)
        $fileNode = $xml.CreateElement('File', $ns)
        $null = $fileNode.SetAttribute('Id', (ConvertTo-WixIdentifier -Value $relative -Prefix 'f'))
        $null = $fileNode.SetAttribute('Source', $file.FullName)
        $null = $fileNode.SetAttribute('Name', $file.Name)
        $null = $fileNode.SetAttribute('KeyPath', 'yes')
        $null = $component.AppendChild($fileNode)
        $null = $parent.AppendChild($component)
    }

    $exeName = [System.IO.Path]::GetFileName($ExecutablePath)
    $shortcut = $xml.CreateElement('Component', $ns)
    $null = $shortcut.SetAttribute('Id', 'StartMenuShortcut')
    $null = $shortcut.SetAttribute('Directory', 'AppShortcutFolder')
    $null = $shortcut.SetAttribute('Guid', '*')
    $shortcutNode = $xml.CreateElement('Shortcut', $ns)
    $null = $shortcutNode.SetAttribute('Id', 'AppStartMenuShortcut')
    $null = $shortcutNode.SetAttribute('Name', $productFolder)
    $null = $shortcutNode.SetAttribute('Target', "[INSTALLFOLDER]$exeName")
    $null = $shortcutNode.SetAttribute('WorkingDirectory', 'INSTALLFOLDER')
    if (-not [string]::IsNullOrWhiteSpace($IconPath) -and (Test-Path -LiteralPath $IconPath -PathType Leaf)) {
        $null = $shortcutNode.SetAttribute('Icon', 'AppIcon')
    }

    $null = $shortcut.AppendChild($shortcutNode)
    $remove = $xml.CreateElement('RemoveFolder', $ns)
    $null = $remove.SetAttribute('Id', 'AppShortcutFolder')
    $null = $remove.SetAttribute('On', 'uninstall')
    $null = $shortcut.AppendChild($remove)
    $reg = $xml.CreateElement('RegistryValue', $ns)
    $null = $reg.SetAttribute('Root', 'HKCU')
    $null = $reg.SetAttribute('Key', "Software\$Manufacturer\$AppName")
    $null = $reg.SetAttribute('Name', 'installed')
    $null = $reg.SetAttribute('Type', 'integer')
    $null = $reg.SetAttribute('Value', '1')
    $null = $reg.SetAttribute('KeyPath', 'yes')
    $null = $shortcut.AppendChild($reg)
    $null = $package.AppendChild($shortcut)

    $desktop = $xml.CreateElement('Component', $ns)
    $null = $desktop.SetAttribute('Id', 'DesktopShortcut')
    $null = $desktop.SetAttribute('Directory', 'DesktopFolder')
    $null = $desktop.SetAttribute('Guid', '*')
    $null = $desktop.SetAttribute('Condition', 'INSTALLDESKTOPSHORTCUT = 1')
    $desktopShortcut = $xml.CreateElement('Shortcut', $ns)
    $null = $desktopShortcut.SetAttribute('Id', 'AppDesktopShortcut')
    $null = $desktopShortcut.SetAttribute('Name', $productFolder)
    $null = $desktopShortcut.SetAttribute('Target', "[INSTALLFOLDER]$exeName")
    $null = $desktopShortcut.SetAttribute('WorkingDirectory', 'INSTALLFOLDER')
    if (-not [string]::IsNullOrWhiteSpace($IconPath) -and (Test-Path -LiteralPath $IconPath -PathType Leaf)) {
        $null = $desktopShortcut.SetAttribute('Icon', 'AppIcon')
    }

    $null = $desktop.AppendChild($desktopShortcut)
    $desktopReg = $xml.CreateElement('RegistryValue', $ns)
    $null = $desktopReg.SetAttribute('Root', 'HKCU')
    $null = $desktopReg.SetAttribute('Key', "Software\$Manufacturer\$AppName")
    $null = $desktopReg.SetAttribute('Name', 'desktop')
    $null = $desktopReg.SetAttribute('Type', 'integer')
    $null = $desktopReg.SetAttribute('Value', '1')
    $null = $desktopReg.SetAttribute('KeyPath', 'yes')
    $null = $desktop.AppendChild($desktopReg)
    $null = $package.AppendChild($desktop)

    $feature = $xml.CreateElement('Feature', $ns)
    $null = $feature.SetAttribute('Id', 'Main')
    $null = $feature.SetAttribute('Title', $AppName)
    $null = $feature.SetAttribute('Level', '1')
    $refShortcut = $xml.CreateElement('ComponentRef', $ns)
    $null = $refShortcut.SetAttribute('Id', 'StartMenuShortcut')
    $null = $feature.AppendChild($refShortcut)
    $refDesktop = $xml.CreateElement('ComponentRef', $ns)
    $null = $refDesktop.SetAttribute('Id', 'DesktopShortcut')
    $null = $feature.AppendChild($refDesktop)
    foreach ($id in $componentIds) {
        $cref = $xml.CreateElement('ComponentRef', $ns)
        $null = $cref.SetAttribute('Id', $id)
        $null = $feature.AppendChild($cref)
    }

    $null = $package.AppendChild($feature)

    return $xml
}

function Get-DefaultFlatpakFinishArgs {
    return @(
        '--share=ipc',
        '--share=network',
        '--socket=fallback-x11',
        '--socket=wayland',
        '--device=dri',
        '--filesystem=home'
    )
}

function New-FlatpakDesktopEntry {
    param(
        [Parameter(Mandatory = $true)]
        [string]$AppId,

        [Parameter(Mandatory = $true)]
        [string]$AppName,

        [Parameter(Mandatory = $true)]
        [string]$Command,

        [Parameter(Mandatory = $false)]
        [string]$Categories = 'Utility;'
    )

    $lines = @(
        '[Desktop Entry]',
        'Type=Application',
        "Name=$AppName",
        "Exec=$Command",
        "Icon=$AppId",
        'Terminal=false',
        "Categories=$Categories"
    )
    return (($lines -join "`n") + "`n")
}

function New-FlatpakMetainfoXml {
    param(
        [Parameter(Mandatory = $true)]
        [string]$AppId,

        [Parameter(Mandatory = $true)]
        [string]$AppName,

        [Parameter(Mandatory = $true)]
        [string]$Summary,

        [Parameter(Mandatory = $false)]
        [string]$ProjectLicense = 'MIT',

        [Parameter(Mandatory = $false)]
        [string]$MetadataLicense = 'CC0-1.0'
    )

    $escapedName = [System.Security.SecurityElement]::Escape($AppName)
    $escapedSummary = [System.Security.SecurityElement]::Escape($Summary)
    return @"
<?xml version="1.0" encoding="UTF-8"?>
<component type="desktop-application">
  <id>$AppId</id>
  <name>$escapedName</name>
  <summary>$escapedSummary</summary>
  <launchable type="desktop-id">$AppId.desktop</launchable>
  <metadata_license>$MetadataLicense</metadata_license>
  <project_license>$ProjectLicense</project_license>
</component>
"@
}

function New-FlatpakManifestObject {
    param(
        [Parameter(Mandatory = $true)]
        [string]$AppId,

        [Parameter(Mandatory = $true)]
        [string]$Command,

        [Parameter(Mandatory = $true)]
        [string]$ModuleName,

        [Parameter(Mandatory = $false)]
        [string]$Runtime = 'org.freedesktop.Platform',

        [Parameter(Mandatory = $false)]
        [string]$RuntimeVersion = '24.08',

        [Parameter(Mandatory = $false)]
        [string]$Sdk = 'org.freedesktop.Sdk',

        [Parameter(Mandatory = $false)]
        [string[]]$FinishArgs,

        [Parameter(Mandatory = $false)]
        [string[]]$BuildCommands
    )

    if ($null -eq $FinishArgs -or $FinishArgs.Count -eq 0) {
        $FinishArgs = @(Get-DefaultFlatpakFinishArgs)
    }

    if ($null -eq $BuildCommands -or $BuildCommands.Count -eq 0) {
        $BuildCommands = @(
            'mkdir -p /app/lib /app/share',
            'cp -a lib /app/lib',
            'cp -a share /app/share',
            "install -Dm755 bin/$Command /app/bin/$Command",
            "chmod +x /app/lib/$ModuleName/$Command"
        )
    }

    return [ordered]@{
        'app-id'          = $AppId
        runtime           = $Runtime
        'runtime-version' = $RuntimeVersion
        sdk               = $Sdk
        command           = $Command
        'finish-args'     = @($FinishArgs)
        modules           = @(
            [ordered]@{
                name            = $ModuleName
                buildsystem     = 'simple'
                'build-commands' = @($BuildCommands)
                sources         = @(
                    [ordered]@{
                        type = 'dir'
                        path = 'files'
                    }
                )
            }
        )
    }
}

function New-FlatpakLaunchScript {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ModuleName,

        [Parameter(Mandatory = $true)]
        [string]$ExecutableFileName
    )

    return "#!/bin/sh`nexec /app/lib/$ModuleName/$ExecutableFileName `"`$@`"`n"
}

function Assert-FlatpakAppId {
    param(
        [Parameter(Mandatory = $true)]
        [string]$AppId
    )

    $hint = "Domain hyphens become underscores (maks-it.com → com.maks_it.App). Only the last segment may contain '-'."
    $segments = @($AppId.Split('.'))
    if ($segments.Count -lt 3) {
        throw "Flatpak appId '$AppId' is invalid: need at least three reverse-DNS segments (e.g. com.maks_it.Wvc210). $hint"
    }

    for ($i = 0; $i -lt $segments.Count; $i++) {
        $segment = $segments[$i]
        $isLast = ($i -eq ($segments.Count - 1))
        $pattern = if ($isLast) { '^[A-Za-z_][A-Za-z0-9_-]*$' } else { '^[A-Za-z_][A-Za-z0-9_]*$' }
        if ($segment -notmatch $pattern) {
            throw "Flatpak appId '$AppId' is invalid: Only last name segment can contain '-'. $hint"
        }
    }
}

function Get-DerivedBundleUpgradeCode {
    param(
        [Parameter(Mandatory = $true)]
        [guid]$UpgradeCode
    )

    $bytes = $UpgradeCode.ToByteArray()
    $bytes[0] = $bytes[0] -bxor 0x5A
    return [guid]::new($bytes)
}

function ConvertTo-ShSingleQuoted {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Value
    )

    return "'" + ($Value -replace "'", "'\''") + "'"
}

function ConvertTo-UnixLineEndings {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Value
    )

    return (($Value -replace "`r`n", "`n") -replace "`r", "`n")
}

function ConvertTo-WslMountPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$WindowsPath
    )

    $full = [System.IO.Path]::GetFullPath($WindowsPath)
    if ($full.StartsWith('\\')) {
        throw "UNC paths cannot be mapped to /mnt for WSL Flatpak builds: $WindowsPath"
    }

    $root = [System.IO.Path]::GetPathRoot($full)
    $drive = $root.Substring(0, 1).ToLowerInvariant()
    $rest = $full.Substring($root.Length).Replace('\', '/')
    return "/mnt/$drive/$rest"
}

function ConvertFrom-WslMountPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$UnixPath
    )

    if ($UnixPath -notmatch '^/mnt/([A-Za-z])/(.*)$') {
        return $null
    }

    $drive = $Matches[1].ToUpperInvariant()
    $rest = $Matches[2].Replace('/', '\')
    return "${drive}:\$rest"
}

function ConvertFrom-WslText {
    param($InputObject)

    $parts = foreach ($item in @($InputObject)) {
        if ($null -eq $item) {
            continue
        }

        [string]$item
    }

    $text = ($parts -join "`n").Replace("`0", '')
    $lines = [System.Collections.Generic.List[string]]::new()
    foreach ($line in ($text -split "`r?`n")) {
        $trimmed = $line.Trim()
        if ([string]::IsNullOrWhiteSpace($trimmed)) {
            continue
        }

        $utf16Spaced = $trimmed.Length -ge 3 -and ($trimmed.Length % 2) -eq 1
        if ($utf16Spaced) {
            for ($i = 1; $i -lt $trimmed.Length; $i += 2) {
                if ($trimmed[$i] -ne [char]' ') {
                    $utf16Spaced = $false
                    break
                }
            }
        }

        if ($utf16Spaced) {
            $chars = for ($i = 0; $i -lt $trimmed.Length; $i += 2) { $trimmed[$i] }
            $trimmed = (-join $chars).Trim()
        }

        if (-not [string]::IsNullOrWhiteSpace($trimmed)) {
            $lines.Add($trimmed)
        }
    }

    return @($lines)
}

function ConvertFrom-WslListOutput {
    param($InputObject)

    return @(
        ConvertFrom-WslText -InputObject $InputObject |
            Where-Object { $_ -notmatch '(?i)^(Windows Subsystem|Distributions:|NAME\s+STATE|The operation completed)' } |
            ForEach-Object { ($_ -replace '\s+\(.*Default.*\)$', '').Trim() } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    )
}

function Test-WslDistroBlockedForFlatpak {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Distro
    )

    $blocked = @('docker-desktop', 'docker-desktop-data')
    return $blocked -contains $Distro.Trim().ToLowerInvariant()
}

function Assert-WslDistroAllowedForFlatpak {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Distro
    )

    if ([string]::IsNullOrWhiteSpace($Distro)) {
        throw "FlatpakPack wslDistro is required on Windows (pin Debian; do not use the default WSL distro)."
    }

    if (Test-WslDistroBlockedForFlatpak -Distro $Distro) {
        throw "FlatpakPack wslDistro cannot be '$Distro' (Docker Desktop). Install Debian and set wslDistro to Debian."
    }
}

function Test-WslDistroInstalled {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Distro,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [string[]]$InstalledNames
    )

    foreach ($name in @($InstalledNames)) {
        if ([string]::Equals($name, $Distro, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }
    }

    return $false
}

function Get-FlatpakBuilderShellLines {
    param(
        [Parameter(Mandatory = $false)]
        [string]$Repo = 'repo',

        [Parameter(Mandatory = $false)]
        [string]$BuildDir = 'build-dir',

        [Parameter(Mandatory = $false)]
        [string]$Manifest = 'manifest.json'
    )

    # org.flatpak.Builder's sandbox cwd is $HOME, so relative manifest.json
    # resolves to /home/<user>/manifest.json. Always pass absolute paths.
    # --disable-rofiles-fuse: WSL/bwrap has no working rofiles FUSE overlay.
    $runLine = '  flatpak run --filesystem=host --filesystem="$ROOT" --share=network --cwd="$ROOT" org.flatpak.Builder --disable-rofiles-fuse --repo="$ROOT/{0}" --force-clean "$ROOT/{1}" "$ROOT/{2}"' -f $Repo, $BuildDir, $Manifest
    $cliLine = '  flatpak-builder --disable-rofiles-fuse --repo="$ROOT/{0}" --force-clean "$ROOT/{1}" "$ROOT/{2}"' -f $Repo, $BuildDir, $Manifest

    return @(
        'ROOT=$(pwd)',
        'if flatpak info org.flatpak.Builder >/dev/null 2>&1; then',
        $runLine,
        'elif command -v flatpak-builder >/dev/null 2>&1; then',
        $cliLine,
        'else',
        '  echo "flatpak builder missing; install Flathub org.flatpak.Builder" >&2',
        '  exit 127',
        'fi'
    )
}

function New-WslFlatpakBuildScript {
    param(
        [Parameter(Mandatory = $true)]
        [string]$WindowsStageRoot,

        [Parameter(Mandatory = $true)]
        [string]$WindowsBundlePath,

        [Parameter(Mandatory = $true)]
        [string]$AppId
    )

    $stageQuoted = ConvertTo-ShSingleQuoted -Value $WindowsStageRoot
    $bundleQuoted = ConvertTo-ShSingleQuoted -Value $WindowsBundlePath
    $appQuoted = ConvertTo-ShSingleQuoted -Value $AppId
    $lines = @(
        'set -euo pipefail',
        "STAGE_WIN=$stageQuoted",
        "BUNDLE_WIN=$bundleQuoted",
        "APP_ID=$appQuoted",
        'STAGE=$(wslpath -a "$STAGE_WIN")',
        'BUNDLE=$(wslpath -a "$BUNDLE_WIN")',
        'mkdir -p "$(dirname "$BUNDLE")"',
        'CACHE="${XDG_CACHE_HOME:-$HOME/.cache}"',
        'mkdir -p "$CACHE"',
        'WORK=$(mktemp -d "$CACHE/maksit-flatpak.XXXXXX")',
        'cleanup() { rm -rf "$WORK"; }',
        'trap cleanup EXIT',
        'cp -a "$STAGE"/. "$WORK"/',
        'cd "$WORK"',
        'if [ -d files/bin ]; then',
        '  find files/bin -type f -print0 | xargs -0 -r sed -i "s/\r$//"',
        '  chmod +x files/bin/* || true',
        'fi'
    )
    $lines += @(Get-FlatpakBuilderShellLines)
    $lines += @(
        'flatpak build-bundle "$ROOT/repo" "$BUNDLE" "$APP_ID"',
        'test -f "$BUNDLE"'
    )

    return (($lines -join "`n") + "`n")
}

function New-WixBundleXml {
    param(
        [Parameter(Mandatory = $true)]
        [string]$AppName,

        [Parameter(Mandatory = $true)]
        [string]$Manufacturer,

        [Parameter(Mandatory = $true)]
        [string]$ProductVersion,

        [Parameter(Mandatory = $true)]
        [guid]$UpgradeCode,

        [Parameter(Mandatory = $true)]
        [string]$MsiPath,

        [Parameter(Mandatory = $false)]
        [string]$IconPath,

        [Parameter(Mandatory = $false)]
        [string]$LogoPath,

        [Parameter(Mandatory = $false)]
        [string]$LogoSidePath,

        [Parameter(Mandatory = $false)]
        [string]$ThemePath,

        [Parameter(Mandatory = $false)]
        [string]$InstallScope = 'perMachine',

        [Parameter(Mandatory = $false)]
        [string]$InstallFolderName
    )

    $escapedName = [System.Security.SecurityElement]::Escape($AppName)
    $escapedMfr = [System.Security.SecurityElement]::Escape($Manufacturer)
    $escapedMsi = [System.Security.SecurityElement]::Escape($MsiPath)
    $bundleUpgrade = Get-DerivedBundleUpgradeCode -UpgradeCode $UpgradeCode
    $productFolder = Get-DesktopInstallFolderName `
        -AppName $AppName `
        -Manufacturer $Manufacturer `
        -InstallFolderName $InstallFolderName
    $iconAttr = ''
    if (-not [string]::IsNullOrWhiteSpace($IconPath)) {
        $iconAttr = " IconSourceFile=`"$([System.Security.SecurityElement]::Escape($IconPath))`""
    }

    $theme = 'hyperlinkLicense'
    $logoAttrs = ''
    if (-not [string]::IsNullOrWhiteSpace($LogoPath)) {
        $logoAttrs += " LogoFile=`"$([System.Security.SecurityElement]::Escape($LogoPath))`""
    }

    if (-not [string]::IsNullOrWhiteSpace($LogoSidePath)) {
        $theme = 'hyperlinkSidebarLicense'
        $logoAttrs += " LogoSideFile=`"$([System.Security.SecurityElement]::Escape($LogoSidePath))`""
    }

    if (-not [string]::IsNullOrWhiteSpace($ThemePath)) {
        $theme = 'hyperlinkSidebarLicense'
        $logoAttrs += " ThemeFile=`"$([System.Security.SecurityElement]::Escape($ThemePath))`""
    }

    # Type=formatted so WixStdBA expands well-known folders in the InstallFolder edit box.
    # Type=string shows the raw token, e.g. [ProgramFiles6432Folder]MaksIT\Cluster Console.
    # Burn CSIDL folders already end with a backslash, so do not insert another one.
    # Layout is {ProgramFiles|LocalAppData}\{Manufacturer}\{product} — product folder is the
    # internal name (appName with manufacturer prefix stripped, or installFolderName).
    $folderRoot = if ($InstallScope -eq 'perUser') {
        '[LocalAppDataFolder]'
    }
    else {
        '[ProgramFiles6432Folder]'
    }

    $folderPath = if ([string]::IsNullOrWhiteSpace($Manufacturer)) {
        $folderRoot + $productFolder
    }
    else {
        $folderRoot + $Manufacturer + '\' + $productFolder
    }
    $escapedFolder = [System.Security.SecurityElement]::Escape($folderPath)

    # WiX v7 Bundle has no Scope attribute (WIX0004). MSI Package/@Scope plus
    # InstallFolder tokens decide per-machine vs per-user; Burn infers bundle scope.
    return @"
<?xml version="1.0" encoding="utf-8"?>
<Wix xmlns="http://wixtoolset.org/schemas/v4/wxs" xmlns:bal="http://wixtoolset.org/schemas/v4/wxs/bal">
  <Bundle Name="$escapedName" Manufacturer="$escapedMfr" Version="$ProductVersion" UpgradeCode="$($bundleUpgrade.ToString('D'))"$iconAttr>
    <Variable Name="InstallFolder" Type="formatted" Value="$escapedFolder" bal:Overridable="yes" />
    <Variable Name="InstallDesktopShortcut" Type="numeric" Value="0" bal:Overridable="yes" />
    <BootstrapperApplication>
      <bal:WixStandardBootstrapperApplication Theme="$theme" LicenseUrl=""$logoAttrs />
    </BootstrapperApplication>
    <Chain>
      <MsiPackage SourceFile="$escapedMsi" Compressed="yes" Vital="yes">
        <MsiProperty Name="INSTALLFOLDER" Value="[InstallFolder]" />
        <MsiProperty Name="INSTALLDESKTOPSHORTCUT" Value="[InstallDesktopShortcut]" />
      </MsiPackage>
    </Chain>
  </Bundle>
</Wix>
"@
}

Export-ModuleMember -Function `
    ConvertTo-WixIdentifier, `
    Get-MsiProductVersion, `
    Get-DesktopInstallFolderName, `
    Get-PluginPropertyValue, `
    Resolve-DesktopPublishDirectory, `
    Resolve-DesktopExecutablePath, `
    New-WixPackageXml, `
    Get-DerivedBundleUpgradeCode, `
    New-WixBundleXml, `
    Get-DefaultFlatpakFinishArgs, `
    New-FlatpakDesktopEntry, `
    New-FlatpakMetainfoXml, `
    New-FlatpakManifestObject, `
    New-FlatpakLaunchScript, `
    Assert-FlatpakAppId, `
    ConvertTo-ShSingleQuoted, `
    ConvertTo-UnixLineEndings, `
    ConvertTo-WslMountPath, `
    ConvertFrom-WslMountPath, `
    ConvertFrom-WslText, `
    ConvertFrom-WslListOutput, `
    Test-WslDistroBlockedForFlatpak, `
    Assert-WslDistroAllowedForFlatpak, `
    Test-WslDistroInstalled, `
    Get-FlatpakBuilderShellLines, `
    New-WslFlatpakBuildScript
