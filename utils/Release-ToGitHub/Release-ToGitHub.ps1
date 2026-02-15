<#
.SYNOPSIS
    Automated GitHub release script for MaksIT.UScheduler.

.DESCRIPTION
    Creates a GitHub release by performing the following steps:
    
    Pre-flight checks:
    - Detects current branch (main or dev)
    - On main: requires clean working directory; on dev: uncommitted changes allowed
    - Reads version from .csproj (source of truth)
    - On main: requires matching tag (vX.Y.Z format)
    - Ensures version consistency with CHANGELOG.md
    - Confirms GitHub CLI authentication via GH_TOKEN (main branch only)
    
    Test execution:
    - Runs all unit tests via Run-Tests.ps1
    - Aborts release if any tests fail
    - Displays coverage summary (line, branch, method)
    
    Build and release:
    - Publishes the .NET project in Release configuration
    - Copies Scripts folder into the release
    - Creates a versioned ZIP archive
    - Extracts release notes from CHANGELOG.md
    - Pushes tag to remote if not already present (main branch only)
    - Creates (or recreates) the GitHub release with assets (main branch only)
    
    Branch-based behavior (configurable in scriptsettings.json):
    - On dev branch: Local build only, no tag required, uncommitted changes allowed
    - On release branch: Full GitHub release, tag required, clean working directory required
    - On other branches: Blocked

.NOTES
    File:        Release-ToGitHub.ps1
    Author:      Maksym Sadovnychyy (MAKS-IT)
    Requires:    dotnet, git, gh (GitHub CLI - required on main branch only)
    
    Configuration is loaded from scriptsettings.json in the same directory.
    Set the GitHub token in an environment variable specified by github.tokenEnvVar.

.EXAMPLE
    .\Release-ToGitHub.ps1
    
    Runs the release process using settings from scriptsettings.json.
    On dev branch: creates local build (no tag needed).
    On main branch: publishes to GitHub (tag required).

.EXAMPLE
    # Recommended workflow:
    # 1. On dev branch: Update version in .csproj and CHANGELOG.md
    # 2. Commit changes
    # 3. Run: .\Release-ToGitHub.ps1
    #    (creates local build for testing - no tag needed)
    # 4. Test the build
    # 5. Merge to main: git checkout main && git merge dev
    # 6. Create tag: git tag v1.0.1
    # 7. Run: .\Release-ToGitHub.ps1
    #    (publishes to GitHub)
#>

# No parameters - behavior is controlled by current branch (configured in scriptsettings.json):
# - dev branch    -> Local build only (no tag required, uncommitted changes allowed)
# - release branch -> Full release to GitHub (tag required, clean working directory)

# Load settings from scriptsettings.json
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$settingsPath = Join-Path $scriptDir "scriptsettings.json"

if (-not (Test-Path $settingsPath)) {
    Write-Error "Settings file not found: $settingsPath"
    exit 1
}

$settings = Get-Content $settingsPath -Raw | ConvertFrom-Json

# Import TestRunner module
$modulePath = Join-Path (Split-Path $scriptDir -Parent) "TestRunner.psm1"
if (-not (Test-Path $modulePath)) {
    Write-Error "TestRunner module not found at: $modulePath"
    exit 1
}
Import-Module $modulePath -Force

# Set GH_TOKEN from custom environment variable for GitHub CLI authentication
$tokenEnvVar = $settings.github.tokenEnvVar
$env:GH_TOKEN = [System.Environment]::GetEnvironmentVariable($tokenEnvVar)

# Paths from settings (resolve relative to script directory)
$csprojPaths = @()
if ($settings.paths.csprojPath -is [System.Collections.IEnumerable] -and -not ($settings.paths.csprojPath -is [string])) {
    foreach ($path in $settings.paths.csprojPath) {
        $csprojPaths += [System.IO.Path]::GetFullPath((Join-Path $scriptDir $path))
    }
}
else {
    $csprojPaths += [System.IO.Path]::GetFullPath((Join-Path $scriptDir $settings.paths.csprojPath))
}

$stagingDir = [System.IO.Path]::GetFullPath((Join-Path $scriptDir $settings.paths.stagingDir))
$releaseDir = [System.IO.Path]::GetFullPath((Join-Path $scriptDir $settings.paths.releaseDir))
$changelogPath = [System.IO.Path]::GetFullPath((Join-Path $scriptDir $settings.paths.changelogPath))
$scriptsPath = [System.IO.Path]::GetFullPath((Join-Path $scriptDir $settings.paths.scriptsPath))
$testProjectPath = [System.IO.Path]::GetFullPath((Join-Path $scriptDir $settings.paths.testProject))

# Release naming patterns
$zipNamePattern = $settings.release.zipNamePattern
$releaseTitlePattern = $settings.release.releaseTitlePattern

# Branch configuration
$releaseBranch = $settings.branches.release
$devBranch = $settings.branches.dev

# Project configuration (avoid hardcoding project names)
$projectsSettings = $settings.projects
$scheduleManagerCsprojEndsWith = $projectsSettings.scheduleManagerCsprojEndsWith
$uschedulerCsprojEndsWith = $projectsSettings.uschedulerCsprojEndsWith
$scheduleManagerAppSettingsFile = $projectsSettings.scheduleManagerAppSettingsFile
$uschedulerAppSettingsFile = $projectsSettings.uschedulerAppSettingsFile
$scheduleManagerServiceBinPath = $projectsSettings.scheduleManagerServiceBinPath
$uschedulerLogDir = $projectsSettings.uschedulerLogDir
$scriptsRelativeToExe = $projectsSettings.scriptsRelativeToExe

# Helper: ensure required commands exist
function Assert-Command {
    param([string]$cmd)

    if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) {
        Write-Error "Required command '$cmd' is missing. Aborting."
        exit 1
    }
}

# Helper: extract a csproj property (first match)
function Get-CsprojPropertyValue {
    param(
        [Parameter(Mandatory=$true)][xml]$csproj,
        [Parameter(Mandatory=$true)][string]$propertyName
    )

    $propNode = $csproj.Project.PropertyGroup |
        Where-Object { $_.$propertyName } |
        Select-Object -First 1

    if ($propNode) {
        return $propNode.$propertyName
    }

    return $null
}

# Helper: resolve output assembly name for published exe
function Resolve-ProjectExeName {
    param(
        [Parameter(Mandatory=$true)][string]$projPath
    )

    [xml]$csproj = Get-Content $projPath
    $assemblyName = Get-CsprojPropertyValue -csproj $csproj -propertyName "AssemblyName"
    if ($assemblyName) {
        return $assemblyName
    }

    return [System.IO.Path]::GetFileNameWithoutExtension($projPath)
}

# Helper: find csproj by configured suffix
function Find-CsprojByEndsWith {
    param(
        [Parameter(Mandatory=$true)][string[]]$paths,
        [Parameter(Mandatory=$true)][string]$endsWith
    )

    if (-not $endsWith) {
        return $null
    }

    return $paths | Where-Object { $_ -like "*$endsWith" } | Select-Object -First 1
}

Assert-Command dotnet
Assert-Command git
# gh command check deferred until after branch detection (only needed on main branch)

Write-Host ""
Write-Host "==================================================" -ForegroundColor Cyan
Write-Host "RELEASE BUILD" -ForegroundColor Cyan
Write-Host "==================================================" -ForegroundColor Cyan
Write-Host ""

# ==============================================================================
# PRE-FLIGHT CHECKS
# ==============================================================================

# 1. Detect current branch and determine release mode
Write-Host "Detecting current branch..." -ForegroundColor Gray
$currentBranch = git rev-parse --abbrev-ref HEAD 2>$null
if ($LASTEXITCODE -ne 0 -or -not $currentBranch) {
    Write-Error "Could not determine current branch."
    exit 1
}

$currentBranch = $currentBranch.Trim()
Write-Host "  Branch: $currentBranch" -ForegroundColor Green

$isDevBranch = $currentBranch -eq $devBranch
$isReleaseBranch = $currentBranch -eq $releaseBranch

if (-not $isDevBranch -and -not $isReleaseBranch) {
    Write-Error "Releases can only be created from '$releaseBranch' or '$devBranch' branches. Current branch: $currentBranch"
    exit 1
}

if ($isDevBranch) {
    Write-Host "  Dev branch ($devBranch) - local build only (no GitHub release)." -ForegroundColor Yellow
}
else {
    Write-Host "  Release branch ($releaseBranch) - will publish to GitHub." -ForegroundColor Cyan
    Assert-Command gh
}

# 2. Check for uncommitted changes (required on main, allowed on dev)
$gitStatus = git status --porcelain 2>$null
if ($gitStatus) {
    if ($isReleaseBranch) {
        Write-Error "Working directory has uncommitted changes. Commit or stash them before releasing."
        Write-Host ""
        Write-Host "Uncommitted files:" -ForegroundColor Yellow
        $gitStatus | ForEach-Object { Write-Host "  $_" -ForegroundColor Yellow }
        exit 1
    }
    else {
        Write-Host "  Uncommitted changes detected (allowed on dev branch)." -ForegroundColor Yellow
    }
} else {
    Write-Host "  Working directory is clean." -ForegroundColor Green
}

# 3. Get version from csproj (source of truth)

Write-Host "Reading version(s) from csproj(s)..." -ForegroundColor Gray
$projectVersions = @{}
foreach ($projPath in $csprojPaths) {
    if (-not (Test-Path $projPath)) {
        Write-Error "Csproj not found at: $projPath"
        exit 1
    }

    [xml]$csproj = Get-Content $projPath
    $version = Get-CsprojPropertyValue -csproj $csproj -propertyName "Version"

    if (-not $version) {
        Write-Error "Version not found in $projPath"
        exit 1
    }
    
    $projectVersions[$projPath] = $version
    Write-Host "  $([System.IO.Path]::GetFileName($projPath)): $version" -ForegroundColor Green
}

# Use the first project's version as the main version for tag/release
$version = $projectVersions[$csprojPaths[0]]

# 4. Handle tag based on branch
if ($isReleaseBranch) {
    # Main branch: tag is required and must match version
    Write-Host "Checking for tag on current commit..." -ForegroundColor Gray
    $tag = git describe --tags --exact-match HEAD 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $tag) {
        Write-Error "No tag found on current commit. Create a tag: git tag v$version"
        exit 1
    }

    $tag = $tag.Trim()
    
    if ($tag -notmatch '^v(\d+\.\d+\.\d+)$') {
        Write-Error "Tag '$tag' does not match expected format 'vX.Y.Z' (e.g., v$version)."
        exit 1
    }

    $tagVersion = $Matches[1]
    
    if ($tagVersion -ne $version) {
        Write-Error "Tag version ($tagVersion) does not match csproj version ($version)."
        Write-Host "  Either update the tag or the csproj version." -ForegroundColor Yellow
        exit 1
    }

    Write-Host "  Tag found: $tag (matches csproj)" -ForegroundColor Green
}
else {
    # Dev branch: no tag required, use version from csproj
    $tag = "v$version"
    Write-Host "  Using version from csproj (no tag required on dev)." -ForegroundColor Gray
}

# 5. Verify CHANGELOG.md has matching version entry
Write-Host "Verifying CHANGELOG.md..." -ForegroundColor Gray
if (-not (Test-Path $changelogPath)) {
    Write-Error "CHANGELOG.md not found at: $changelogPath"
    exit 1
}

$changelog = Get-Content $changelogPath -Raw

if ($changelog -notmatch '##\s+v(\d+\.\d+\.\d+)') {
    Write-Error "No version entry found in CHANGELOG.md"
    exit 1
}

$changelogVersion = $Matches[1]

if ($changelogVersion -ne $version) {
    Write-Error "Csproj version ($version) does not match latest CHANGELOG.md version ($changelogVersion)."
    Write-Host "  Update CHANGELOG.md or the csproj version." -ForegroundColor Yellow
    exit 1
}

Write-Host "  CHANGELOG.md version matches: v$changelogVersion" -ForegroundColor Green

# 6. Check GitHub authentication (skip for local-only builds)
if (-not $isDevBranch) {
    Write-Host "Checking GitHub authentication..." -ForegroundColor Gray
    if (-not $env:GH_TOKEN) {
        Write-Error "GH_TOKEN environment variable is not set. Set $tokenEnvVar and rerun."
        exit 1
    }

    $authTest = gh api user 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $authTest) {
        Write-Error "GitHub CLI authentication failed. GH_TOKEN may be invalid or missing repo scope."
        exit 1
    }
    Write-Host "  GitHub CLI authenticated." -ForegroundColor Green
}
else {
    Write-Host "Skipping GitHub authentication (local-only mode)." -ForegroundColor Gray
}

Write-Host ""
Write-Host "All pre-flight checks passed!" -ForegroundColor Green
Write-Host ""

# ==============================================================================
# RUN TESTS
# ==============================================================================

Write-Host "Running tests..." -ForegroundColor Cyan

# Run tests using TestRunner module
$testResult = Invoke-TestsWithCoverage -TestProjectPath $testProjectPath -Silent

if (-not $testResult.Success) {
    Write-Error "Tests failed. Release aborted."
    Write-Host "  Error: $($testResult.Error)" -ForegroundColor Red
    exit 1
}

Write-Host "  All tests passed!" -ForegroundColor Green
Write-Host "  Line Coverage:   $($testResult.LineRate)%" -ForegroundColor Gray
Write-Host "  Branch Coverage: $($testResult.BranchRate)%" -ForegroundColor Gray
Write-Host "  Method Coverage: $($testResult.MethodRate)%" -ForegroundColor Gray
Write-Host ""

# ==============================================================================
# BUILD AND RELEASE
# ==============================================================================

# 7. Prepare staging directory
Write-Host "Preparing staging directory..." -ForegroundColor Cyan
if (Test-Path $stagingDir) {
    Remove-Item $stagingDir -Recurse -Force
}

New-Item -ItemType Directory -Path $stagingDir | Out-Null

$binDir = Join-Path $stagingDir "bin"

# 8. Publish the project to staging/bin

Write-Host "Publishing projects to bin folder..." -ForegroundColor Cyan
$publishSuccess = $true
$publishedProjects = @()

foreach ($projPath in $csprojPaths) {
    $projName = [System.IO.Path]::GetFileNameWithoutExtension($projPath)
    $projBinDir = Join-Path $binDir $projName

    dotnet publish $projPath -c Release -o $projBinDir
    if ($LASTEXITCODE -ne 0) {
        Write-Error "dotnet publish failed for $projName."
        $publishSuccess = $false
    }
    else {
        $exeBaseName = Resolve-ProjectExeName -projPath $projPath
        $publishedProjects += [PSCustomObject]@{
            ProjPath = $projPath
            ProjName = $projName
            BinDir = $projBinDir
            ExeBaseName = $exeBaseName
        }

        Write-Host "  Published $projName successfully to: $projBinDir" -ForegroundColor Green
    }
}

if (-not $publishSuccess) {
    exit 1
}

# 9. Copy Scripts folder to staging
Write-Host "Copying Scripts folder..." -ForegroundColor Cyan
if (-not (Test-Path $scriptsPath)) {
    Write-Error "Scripts folder not found at: $scriptsPath"
    exit 1
}

$scriptsDestination = Join-Path $stagingDir "Scripts"
Copy-Item -Path $scriptsPath -Destination $scriptsDestination -Recurse
Write-Host "  Scripts copied to: $scriptsDestination" -ForegroundColor Green

Write-Host "Updating ScheduleManager appsettings with UScheduler path..." -ForegroundColor Cyan

# 10. Update appsettings.json with scripts in disabled state
# Dynamically locate ScheduleManager appsettings based on settings.projects.scheduleManagerCsprojEndsWith
$scheduleManagerCsprojPath = Find-CsprojByEndsWith -paths $csprojPaths -endsWith $scheduleManagerCsprojEndsWith
if ($scheduleManagerCsprojPath) {
    $scheduleManagerProjName = [System.IO.Path]::GetFileNameWithoutExtension($scheduleManagerCsprojPath)
    $scheduleManagerBinDir = Join-Path $binDir $scheduleManagerProjName
    $scheduleManagerAppSettingsPath = Join-Path $scheduleManagerBinDir $scheduleManagerAppSettingsFile

    if (Test-Path $scheduleManagerAppSettingsPath) {
        $smAppSettings = Get-Content $scheduleManagerAppSettingsPath -Raw | ConvertFrom-Json
        if ($smAppSettings.USchedulerSettings) {
            $smAppSettings.USchedulerSettings.ServiceBinPath = $scheduleManagerServiceBinPath
            $jsonOutput = $smAppSettings | ConvertTo-Json -Depth 10
            Set-Content -Path $scheduleManagerAppSettingsPath -Value $jsonOutput -Encoding UTF8
            Write-Host "  Updated ServiceBinPath in ScheduleManager appsettings" -ForegroundColor Green
        }
        else {
            Write-Host "  Warning: USchedulerSettings section not found in ScheduleManager appsettings" -ForegroundColor Yellow
        }
    }
    else {
        Write-Host "  Warning: $scheduleManagerAppSettingsFile not found in $scheduleManagerProjName bin folder" -ForegroundColor Yellow
    }
}
else {
    Write-Host "  Warning: ScheduleManager csproj not found in csprojPaths array" -ForegroundColor Yellow
}

Write-Host "Updating UScheduler appsettings with new LogDir bundled scripts paths..." -ForegroundColor Cyan

# Resolve UScheduler csproj by configured suffix (avoid hardcoded ScheduleManager exclusion)
$uschedulerCsprojPath = Find-CsprojByEndsWith -paths $csprojPaths -endsWith $uschedulerCsprojEndsWith
if ($uschedulerCsprojPath) {
    $uschedulerProjName = [System.IO.Path]::GetFileNameWithoutExtension($uschedulerCsprojPath)
    $uschedulerBinDir = Join-Path $binDir $uschedulerProjName
    $appSettingsPath = Join-Path $uschedulerBinDir $uschedulerAppSettingsFile

    if (Test-Path $appSettingsPath) {
        $appSettings = Get-Content $appSettingsPath -Raw | ConvertFrom-Json

        # Update LogDir for release
        if ($appSettings.Configuration) {
            $appSettings.Configuration.LogDir = $uschedulerLogDir
            Write-Host "  Updated LogDir in UScheduler appsettings" -ForegroundColor Green
        }
        else {
            Write-Host "  Warning: Configuration section not found in UScheduler appsettings" -ForegroundColor Yellow
        }

        # Find all .ps1 files in Scripts folder (exclude utility scripts in subfolders named "Utilities")
        $psScripts = Get-ChildItem -Path $scriptsDestination -Filter "*.ps1" -Recurse |
            Where-Object { $_.Directory.Name -ne "Utilities" } |
            ForEach-Object {
                $relativePath = $_.FullName.Substring($scriptsDestination.Length + 1).Replace('/', '\')
                $scriptPath = "$scriptsRelativeToExe\$relativePath"
                [PSCustomObject]@{
                    Path = $scriptPath
                    IsSigned = $false
                    Disabled = $true
                }
            }

        # Add scripts to Powershell configuration
        if ($psScripts) {
            if (-not $appSettings.Configuration) {
                $appSettings | Add-Member -MemberType NoteProperty -Name "Configuration" -Value ([PSCustomObject]@{})
            }

            $appSettings.Configuration.Powershell = @($psScripts)
            $jsonOutput = $appSettings | ConvertTo-Json -Depth 10
            Set-Content -Path $appSettingsPath -Value $jsonOutput -Encoding UTF8
            Write-Host "  Added $($psScripts.Count) PowerShell script(s) to appsettings (disabled)" -ForegroundColor Green
            $psScripts | ForEach-Object { Write-Host "    - $($_.Path)" -ForegroundColor Gray }
        }
    }
    else {
        Write-Host "  Warning: $uschedulerAppSettingsFile not found in $uschedulerProjName bin folder" -ForegroundColor Yellow
    }
}
else {
    Write-Host "  Warning: UScheduler csproj not found in csprojPaths array" -ForegroundColor Yellow
}

# 11. Create launcher batch file (if enabled)
if ($settings.launcher -and $settings.launcher.enabled) {
    Write-Host "Creating launcher batch file..." -ForegroundColor Cyan
    
    $launcherFileName = $settings.launcher.fileName
    $targetProject = $settings.launcher.targetProject
    
    # Determine which project to launch
    $targetCsprojPath = $null
    $targetExeName = $null
    $targetProjName = $null
    
    if ($targetProject -eq "scheduleManager") {
        $targetCsprojPath = Find-CsprojByEndsWith -paths $csprojPaths -endsWith $scheduleManagerCsprojEndsWith
    }
    elseif ($targetProject -eq "uscheduler") {
        $targetCsprojPath = Find-CsprojByEndsWith -paths $csprojPaths -endsWith $uschedulerCsprojEndsWith
    }
    else {
        Write-Host "  Warning: Unknown targetProject '$targetProject' in launcher settings" -ForegroundColor Yellow
    }
    
    if ($targetCsprojPath) {
        $targetProjName = [System.IO.Path]::GetFileNameWithoutExtension($targetCsprojPath)
        $targetExeName = Resolve-ProjectExeName -projPath $targetCsprojPath
        
        $batPath = Join-Path $stagingDir $launcherFileName
        $exePath = "%~dp0bin\$targetProjName\$targetExeName.exe"
        
        $batContent = @"
@echo off
start "" "$exePath"
"@
        
        Set-Content -Path $batPath -Value $batContent -Encoding ASCII
        Write-Host "  Created launcher: $launcherFileName -> $exePath" -ForegroundColor Green
    }
    else {
        Write-Host "  Warning: Could not find target project for launcher" -ForegroundColor Yellow
    }
}
else {
    Write-Host "Skipping launcher batch file creation (disabled in settings)." -ForegroundColor Gray
}

Write-Host ""

# 12. Prepare release directory
if (!(Test-Path $releaseDir)) {
    New-Item -ItemType Directory -Path $releaseDir | Out-Null
}

# 13. Create zip file
$zipName = $zipNamePattern -replace '\{version\}', $version
$zipPath = Join-Path $releaseDir $zipName

if (Test-Path $zipPath) {
    Remove-Item $zipPath -Force
}

Write-Host "Creating archive $zipName..." -ForegroundColor Cyan
Compress-Archive -Path "$stagingDir\*" -DestinationPath $zipPath -Force

if (-not (Test-Path $zipPath)) {
    Write-Error "Failed to create archive $zipPath"
    exit 1
}

Write-Host "  Archive created: $zipPath" -ForegroundColor Green


# 14. Extract release notes from CHANGELOG.md
Write-Host "Extracting release notes..." -ForegroundColor Cyan
$pattern = "(?ms)^##\s+v$([regex]::Escape($version))\b.*?(?=^##\s+v\d+\.\d+\.\d+|\Z)"
$match = [regex]::Match($changelog, $pattern)

if (-not $match.Success) {
    Write-Error "Changelog entry for version $version not found."
    exit 1
}

$releaseNotes = $match.Value.Trim()
Write-Host "  Release notes extracted." -ForegroundColor Green

# 15. Get repository info
$remoteUrl = git config --get remote.origin.url
if ($LASTEXITCODE -ne 0 -or -not $remoteUrl) {
    Write-Error "Could not determine git remote origin URL."
    exit 1
}

if ($remoteUrl -match "[:/](?<owner>[^/]+)/(?<repo>[^/.]+)(\.git)?$") {
    $owner = $matches['owner']
    $repoName = $matches['repo']
    $repo = "$owner/$repoName"
} else {
    Write-Error "Could not parse GitHub repo from remote URL: $remoteUrl"
    exit 1
}

$releaseName = $releaseTitlePattern -replace '\{version\}', $version

Write-Host ""
Write-Host "Release Summary:" -ForegroundColor Cyan
Write-Host "  Repository: $repo" -ForegroundColor White
Write-Host "  Tag: $tag" -ForegroundColor White
Write-Host "  Title: $releaseName" -ForegroundColor White
Write-Host ""

# 16. Check if tag is pushed to remote (skip on dev branch)
if (-not $isDevBranch) {
    Write-Host "Verifying tag is pushed to remote..." -ForegroundColor Cyan
    $remoteTag = git ls-remote --tags origin $tag 2>$null
    if (-not $remoteTag) {
        Write-Host "  Tag $tag not found on remote. Pushing..." -ForegroundColor Yellow
        git push origin $tag
        if ($LASTEXITCODE -ne 0) {
            Write-Error "Failed to push tag $tag to remote."
            exit 1
        }
        Write-Host "  Tag pushed successfully." -ForegroundColor Green
    }
    else {
        Write-Host "  Tag exists on remote." -ForegroundColor Green
    }

    # 17. Create or update GitHub release
    Write-Host "Creating GitHub release..." -ForegroundColor Cyan

    # Check if release already exists
    gh release view $tag --repo $repo 2>$null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  Release $tag already exists. Deleting..." -ForegroundColor Yellow
        gh release delete $tag --repo $repo --yes
        if ($LASTEXITCODE -ne 0) {
            Write-Error "Failed to delete existing release $tag."
            exit 1
        }
    }

    # Create new release using existing tag
    $ghArgs = @(
        "release", "create", $tag, $zipPath
        "--repo", $repo
        "--title", $releaseName
        "--notes", $releaseNotes
    )
    & gh @ghArgs

    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to create GitHub release for tag $tag."
        exit 1
    }

    Write-Host "  GitHub release created successfully." -ForegroundColor Green
}
else {
    Write-Host "Skipping GitHub release (dev branch)." -ForegroundColor Yellow
}

# 18. Cleanup
if (Test-Path $stagingDir) {
    Remove-Item $stagingDir -Recurse -Force
    Write-Host "  Cleaned up staging directory." -ForegroundColor Gray
}

Write-Host ""
Write-Host "==================================================" -ForegroundColor Green
if ($isDevBranch) {
    Write-Host "DEV BUILD COMPLETE" -ForegroundColor Green
}
else {
    Write-Host "RELEASE COMPLETE" -ForegroundColor Green
}
Write-Host "==================================================" -ForegroundColor Green
Write-Host ""
if (-not $isDevBranch) {
    Write-Host "Release URL: https://github.com/$repo/releases/tag/$tag" -ForegroundColor Cyan
}
Write-Host "Artifacts location: $releaseDir" -ForegroundColor Gray
if ($isDevBranch) {
    Write-Host ""
    Write-Host "To publish to GitHub, merge to main, tag, and run the script again:" -ForegroundColor Yellow
    Write-Host "  git checkout main" -ForegroundColor Yellow
    Write-Host "  git merge dev" -ForegroundColor Yellow
    Write-Host "  git tag v$version" -ForegroundColor Yellow
    Write-Host "  .\Release-ToGitHub.ps1" -ForegroundColor Yellow
}
Write-Host ""
