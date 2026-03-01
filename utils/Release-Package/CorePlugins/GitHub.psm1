#requires -Version 7.0
#requires -PSEdition Core

<#
.SYNOPSIS
    GitHub release plugin.

.DESCRIPTION
    This plugin validates GitHub CLI access, resolves the target
    repository, and creates the configured GitHub release using the
    shared release artifacts and extracted release notes.
#>

if (-not (Get-Command Import-PluginDependency -ErrorAction SilentlyContinue)) {
    $pluginSupportModulePath = Join-Path (Split-Path $PSScriptRoot -Parent) "PluginSupport.psm1"
    if (Test-Path $pluginSupportModulePath -PathType Leaf) {
        Import-Module $pluginSupportModulePath -Force -Global -ErrorAction Stop
    }
}

function Get-GitHubRepositoryInternal {
    param(
        [Parameter(Mandatory = $false)]
        [string]$ConfiguredRepository
    )

    $repoSource = $ConfiguredRepository

    if ([string]::IsNullOrWhiteSpace($repoSource)) {
        $repoSource = git config --get remote.origin.url
        if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($repoSource)) {
            throw "Could not determine git remote origin URL."
        }
    }

    $repoSource = $repoSource.Trim()

    if ($repoSource -match "(?i)github\.com[:/](?<owner>[^/]+)/(?<repo>[^/.]+)(\.git)?$") {
        return "$($matches['owner'])/$($matches['repo'])"
    }

    if ($repoSource -match "^(?<owner>[^/]+)/(?<repo>[^/]+)$") {
        return "$($matches['owner'])/$($matches['repo'])"
    }

    throw "Could not parse GitHub repo from source: $repoSource. Configure Plugins[].repository with 'owner/repo' or a GitHub URL."
}

function Get-ReleaseNotesInternal {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ReleaseNotesFile,

        [Parameter(Mandatory = $true)]
        [string]$Version
    )

    Write-Log -Level "INFO" -Message "Verifying release notes source..."
    if (-not (Test-Path $ReleaseNotesFile -PathType Leaf)) {
        throw "Release notes source file not found at: $ReleaseNotesFile"
    }

    $releaseNotesContent = Get-Content $ReleaseNotesFile -Raw
    if ($releaseNotesContent -notmatch '##\s+v(\d+\.\d+\.\d+)') {
        throw "No version entry found in the configured release notes source."
    }

    $releaseNotesVersion = $Matches[1]
    if ($releaseNotesVersion -ne $Version) {
        throw "Project version ($Version) does not match the latest release notes version ($releaseNotesVersion)."
    }

    Write-Log -Level "OK" -Message "  Release notes version matches: v$releaseNotesVersion"

    Write-Log -Level "STEP" -Message "Extracting release notes..."
    $pattern = "(?ms)^##\s+v$([regex]::Escape($Version))\b.*?(?=^##\s+v\d+\.\d+\.\d+|\Z)"
    $match = [regex]::Match($releaseNotesContent, $pattern)

    if (-not $match.Success) {
        throw "Release notes entry for version $Version not found."
    }

    Write-Log -Level "OK" -Message "  Release notes extracted."
    return $match.Value.Trim()
}

function Invoke-Plugin {
    param(
        [Parameter(Mandatory = $true)]
        $Settings
    )

    Import-PluginDependency -ModuleName "Logging" -RequiredCommand "Write-Log"
    Import-PluginDependency -ModuleName "ScriptConfig" -RequiredCommand "Assert-Command"

    $pluginSettings = $Settings
    $sharedSettings = $Settings.Context
    $githubTokenEnvVar = $pluginSettings.githubToken
    $configuredRepository = $pluginSettings.repository
    $releaseNotesFileSetting = $pluginSettings.releaseNotesFile
    $releaseTitlePatternSetting = $pluginSettings.releaseTitlePattern
    $scriptDir = $sharedSettings.ScriptDir
    $version = $sharedSettings.Version
    $tag = $sharedSettings.Tag
    $releaseDir = $sharedSettings.ReleaseDir
    $releaseAssetPaths = @()

    Assert-Command gh

    if ([string]::IsNullOrWhiteSpace($githubTokenEnvVar)) {
        throw "GitHub plugin requires 'githubToken' in scriptsettings.json."
    }

    $githubToken = [System.Environment]::GetEnvironmentVariable($githubTokenEnvVar)
    if ([string]::IsNullOrWhiteSpace($githubToken)) {
        throw "GitHub token is not set. Set '$githubTokenEnvVar' and rerun."
    }

    if ([string]::IsNullOrWhiteSpace($releaseNotesFileSetting)) {
        throw "GitHub plugin requires 'releaseNotesFile' in scriptsettings.json."
    }

    $releaseNotesFile = [System.IO.Path]::GetFullPath((Join-Path $scriptDir $releaseNotesFileSetting))
    $releaseNotes = Get-ReleaseNotesInternal -ReleaseNotesFile $releaseNotesFile -Version $version

    if ($sharedSettings.PSObject.Properties['ReleaseAssetPaths'] -and $sharedSettings.ReleaseAssetPaths) {
        $releaseAssetPaths = @($sharedSettings.ReleaseAssetPaths)
    }
    elseif ($sharedSettings.PSObject.Properties['PackageFile'] -and $sharedSettings.PackageFile) {
        $releaseAssetPaths = @($sharedSettings.PackageFile.FullName)
        if ($sharedSettings.PSObject.Properties['SymbolsPackageFile'] -and $sharedSettings.SymbolsPackageFile) {
            $releaseAssetPaths += $sharedSettings.SymbolsPackageFile.FullName
        }
    }

    if ($releaseAssetPaths.Count -eq 0) {
        throw "GitHub release requires at least one prepared release asset."
    }

    $repo = Get-GitHubRepositoryInternal -ConfiguredRepository $configuredRepository
    $releaseTitlePattern = if ([string]::IsNullOrWhiteSpace($releaseTitlePatternSetting)) {
        "Release {version}"
    }
    else {
        $releaseTitlePatternSetting
    }
    $releaseName = $releaseTitlePattern -replace '\{version\}', $version

    Write-Log -Level "INFO" -Message "  GitHub repository: $repo"
    Write-Log -Level "INFO" -Message "  GitHub tag: $tag"
    Write-Log -Level "INFO" -Message "  GitHub title: $releaseName"

    $previousGhToken = $env:GH_TOKEN
    $env:GH_TOKEN = $githubToken

    try {
        $ghVersion = & gh --version 2>&1
        if ($ghVersion) {
            Write-Log -Level "INFO" -Message "  gh version: $($ghVersion[0])"
        }

        Write-Log -Level "INFO" -Message "  Auth env var: $githubTokenEnvVar (set)"

        $authArgs = @("api", "repos/$repo", "--jq", ".full_name")
        $authOutput = & gh @authArgs 2>&1
        $authExitCode = $LASTEXITCODE

        if ($authExitCode -ne 0 -or [string]::IsNullOrWhiteSpace(($authOutput | Out-String))) {
            Write-Log -Level "WARN" -Message "  gh auth check failed (exit code: $authExitCode)."
            if ($authOutput) {
                $authOutput | ForEach-Object { Write-Log -Level "WARN" -Message "    $_" }
            }

            $authStatus = & gh auth status --hostname github.com 2>&1
            if ($authStatus) {
                $authStatus | ForEach-Object { Write-Log -Level "WARN" -Message "    $_" }
            }

            throw "GitHub CLI authentication failed for repository '$repo'. Ensure '$githubTokenEnvVar' is valid and has access to this repository."
        }

        Write-Log -Level "OK" -Message "  GitHub token validated for repository: $($authOutput | Select-Object -First 1)"
        Write-Log -Level "STEP" -Message "Creating GitHub release..."

        $releaseViewArgs = @("release", "view", $tag, "--repo", $repo)
        & gh @releaseViewArgs 2>$null

        if ($LASTEXITCODE -eq 0) {
            Write-Log -Level "WARN" -Message "  Release $tag already exists. Deleting..."
            $releaseDeleteArgs = @("release", "delete", $tag, "--repo", $repo, "--yes")
            & gh @releaseDeleteArgs
            if ($LASTEXITCODE -ne 0) {
                throw "Failed to delete existing release $tag."
            }
        }

        $notesFilePath = Join-Path $releaseDir ("release-notes-{0}.md" -f $version)

        try {
            [System.IO.File]::WriteAllText($notesFilePath, $releaseNotes, [System.Text.UTF8Encoding]::new($false))

            $createReleaseArgs = @("release", "create", $tag) + $releaseAssetPaths + @(
                "--repo", $repo,
                "--title", $releaseName,
                "--notes-file", $notesFilePath
            )
            & gh @createReleaseArgs

            if ($LASTEXITCODE -ne 0) {
                throw "Failed to create GitHub release for tag $tag."
            }
        }
        finally {
            if (Test-Path $notesFilePath) {
                Remove-Item $notesFilePath -Force
            }
        }

        Write-Log -Level "OK" -Message "  GitHub release created successfully."
        $sharedSettings | Add-Member -NotePropertyName PublishCompleted -NotePropertyValue $true -Force
    }
    finally {
        if ($null -ne $previousGhToken) {
            $env:GH_TOKEN = $previousGhToken
        }
        else {
            Remove-Item Env:GH_TOKEN -ErrorAction SilentlyContinue
        }
    }
}

Export-ModuleMember -Function Invoke-Plugin
