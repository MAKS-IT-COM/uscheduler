#requires -Version 7.0
#requires -PSEdition Core

<#
.SYNOPSIS
    GitHub release plugin.

.DESCRIPTION
    This plugin validates GitHub CLI access, resolves the target
    repository, and creates the configured GitHub release using the
    shared release artifacts and release notes from CHANGELOG.md.
    Release notes must use Keep a Changelog headers: ## [semver] - YYYY-MM-DD
    (see ChangelogSupport.psm1).
#>

if (-not (Get-Command Import-PluginDependency -ErrorAction SilentlyContinue)) {
    $srcDir = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
        $pluginSupportModulePath = Join-Path $srcDir "modules/Engine/PluginSupport.psm1"
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

    throw "Could not parse GitHub repo from source: $repoSource. Configure plugins[].repository with 'owner/repo' or a GitHub URL."
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
    $releaseNotesVersion = Get-LatestChangelogVersion -ReleaseNotesContent $releaseNotesContent
    if ([string]::IsNullOrWhiteSpace($releaseNotesVersion)) {
        throw "No version entry found in the configured release notes source. Expected Keep a Changelog header: ## [semver] - YYYY-MM-DD."
    }

    if ($releaseNotesVersion -ne $Version) {
        throw "Project version ($Version) does not match the latest release notes version ($releaseNotesVersion)."
    }

    Write-Log -Level "OK" -Message "  Release notes version matches: v$releaseNotesVersion"

    Write-Log -Level "STEP" -Message "Extracting release notes..."
    $section = Get-ChangelogReleaseNotesSection -ReleaseNotesContent $releaseNotesContent -Version $Version

    if ([string]::IsNullOrWhiteSpace($section)) {
        throw "Release notes entry for version $Version not found. Expected header: ## [$Version] - YYYY-MM-DD."
    }

    Write-Log -Level "OK" -Message "  Release notes extracted."
    return $section
}

function Invoke-Plugin {
    param(
        [Parameter(Mandatory = $true)]
        $Settings
    )

    Import-PluginDependency -ModuleName "Logging" -RequiredCommand "Write-Log"
    Import-PluginDependency -ModuleName "ScriptConfig" -RequiredCommand "Assert-Command"
    Import-PluginDependency -ModuleName "ChangelogSupport" -RequiredCommand "Get-LatestChangelogVersion"

    $pluginSettings = $Settings
    $sharedSettings = $Settings.context
    $githubTokenEnvVar = $pluginSettings.githubToken
    $configuredRepository = $pluginSettings.repository
    $releaseNotesFileSetting = $pluginSettings.releaseNotesFile
    $releaseTitlePatternSetting = $pluginSettings.releaseTitlePattern
    $scriptDir = $sharedSettings.scriptDir
    $version = $sharedSettings.version
    $tag = $sharedSettings.tag
    $releaseDir = $sharedSettings.releaseDir
    $releaseAssetPaths = @()

    Assert-Command gh

    if ([string]::IsNullOrWhiteSpace($githubTokenEnvVar)) {
        throw "GitHub plugin requires 'githubToken' in scriptSettings.json."
    }

    $githubToken = [System.Environment]::GetEnvironmentVariable($githubTokenEnvVar)
    if ([string]::IsNullOrWhiteSpace($githubToken)) {
        throw "GitHub token is not set. Set '$githubTokenEnvVar' and rerun."
    }

    if ([string]::IsNullOrWhiteSpace($releaseNotesFileSetting)) {
        throw "GitHub plugin requires 'releaseNotesFile' in scriptSettings.json."
    }

    $releaseNotesFile = [System.IO.Path]::GetFullPath((Join-Path $scriptDir $releaseNotesFileSetting))
    $releaseNotes = Get-ReleaseNotesInternal -ReleaseNotesFile $releaseNotesFile -Version $version

    if ($sharedSettings.PSObject.Properties['releaseAssetPaths'] -and $sharedSettings.releaseAssetPaths) {
        $releaseAssetPaths = @($sharedSettings.releaseAssetPaths)
    }
    elseif ($sharedSettings.PSObject.Properties['packageFile'] -and $sharedSettings.packageFile) {
        $releaseAssetPaths = @($sharedSettings.packageFile.FullName)
        if ($sharedSettings.PSObject.Properties['symbolsPackageFile'] -and $sharedSettings.symbolsPackageFile) {
            $releaseAssetPaths += $sharedSettings.symbolsPackageFile.FullName
        }
    }

    $requireReleaseAssets = $true
    if ($null -ne $pluginSettings.requireReleaseAssets) {
        $requireReleaseAssets = [bool]$pluginSettings.requireReleaseAssets
    }

    if ($releaseAssetPaths.Count -eq 0 -and $requireReleaseAssets) {
        throw "GitHub release requires at least one prepared release asset (set requireReleaseAssets: false for notes-only npm releases)."
    }

    if ($releaseAssetPaths.Count -eq 0) {
        Write-Log -Level "INFO" -Message "  Notes-only GitHub release (requireReleaseAssets: false)."
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
        $sharedSettings | Add-Member -NotePropertyName publishCompleted -NotePropertyValue $true -Force
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
