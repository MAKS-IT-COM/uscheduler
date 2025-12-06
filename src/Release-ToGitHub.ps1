# Set GH_TOKEN from custom environment variable for GitHub CLI authentication
$env:GH_TOKEN = $env:GITHUB_MAKS_IT_COM

# Paths
$csprojPath = "MaksIT.UScheduler\MaksIT.UScheduler.csproj"
$publishDir = "publish"
$releaseDir = "release"
$changelogPath = "..\CHANGELOG.md"

# Helper: ensure required commands exist
function Assert-Command {
    param([string]$cmd)
    if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) {
        Write-Error "Required command '$cmd' is missing. Aborting."
        exit 1
    }
}

Assert-Command dotnet
Assert-Command git
Assert-Command gh

# 1. Get version from .csproj
[xml]$csproj = Get-Content $csprojPath

# Support multiple PropertyGroups
$version = ($csproj.Project.PropertyGroup |
            Where-Object { $_.Version } |
            Select-Object -First 1).Version

if (-not $version) {
    Write-Error "Version not found in $csprojPath"
    exit 1
}

Write-Host "Version detected: $version"

# 2. Publish the project
Write-Host "Publishing project..."
dotnet publish $csprojPath -c Release -o $publishDir

if ($LASTEXITCODE -ne 0) {
    Write-Error "dotnet publish failed."
    exit 1
}

# 3. Prepare release directory
if (!(Test-Path $releaseDir)) {
    New-Item -ItemType Directory -Path $releaseDir | Out-Null
}

# 4. Create zip file
$zipName = "maksit.uscheduler-$version.zip"
$zipPath = Join-Path $releaseDir $zipName

if (Test-Path $zipPath) {
    Remove-Item $zipPath -Force
}

Write-Host "Creating archive $zipName ..."
Compress-Archive -Path "$publishDir\*" -DestinationPath $zipPath -Force

if ($LASTEXITCODE -ne 0 -or -not (Test-Path $zipPath)) {
    Write-Error "Failed to create archive $zipPath"
    exit 1
}

Write-Host "Release zip created: $zipPath"

# 5.a Extract related changelog section from CHANGELOG.md
if (-not (Test-Path $changelogPath)) {
    Write-Error "CHANGELOG.md not found."
    exit 1
}

$changelog = Get-Content $changelogPath -Raw

# Regex pattern to get the changelog section for the current version
$pattern = "(?ms)^##\s+v$([regex]::Escape($version))\b.*?(?=^##\s+v\d+\.\d+\.\d+|\Z)"

$match = [regex]::Match($changelog, $pattern)

if (-not $match.Success) {
    Write-Error "Changelog entry for version $version not found."
    exit 1
}

$releaseNotes = $match.Value.Trim()

Write-Host "Extracted release notes for ${version}:"
Write-Host "----------------------------------------"
Write-Host $releaseNotes
Write-Host "----------------------------------------"

# 5. Create GitHub Release (requires GitHub CLI)
# Get remote URL
$remoteUrl = git config --get remote.origin.url
if ($LASTEXITCODE -ne 0 -or -not $remoteUrl) {
    Write-Error "Could not determine git remote origin URL."
    exit 1
}

# Extract owner/repo from URL (supports HTTPS and SSH)
if ($remoteUrl -match "[:/](?<owner>[^/]+)/(?<repo>[^/.]+)(\.git)?$") {
    $owner = $matches['owner']
    $repoName = $matches['repo']
    $repo = "$owner/$repoName"
} else {
    Write-Error "Could not parse GitHub repo from remote URL: $remoteUrl"
    exit 1
}

$tag = "v$version"
$releaseName = "Release $version"

Write-Host "Repository detected: $repo"
Write-Host "Tag to be created: $tag"

# Ensure GH_TOKEN is set
if (-not $env:GH_TOKEN) {
    Write-Error "GH_TOKEN environment variable is not set. Set GITHUB_MAKS_IT_COM and rerun."
    exit 1
}

Write-Host "Authenticating GitHub CLI using GH_TOKEN..."

# Reliable authentication test
$authTest = gh api user 2>$null

if ($LASTEXITCODE -ne 0 -or -not $authTest) {
    Write-Error "GitHub CLI authentication failed. GH_TOKEN may be invalid or missing repo scope."
    exit 1
}

Write-Host "GitHub CLI authenticated successfully via GH_TOKEN."

# Create or replace release
Write-Host "Creating GitHub release for $repo ..."

# Check if release already exists
$existing = gh release list --repo $repo | Select-String "^$tag\s"

if ($existing) {
    Write-Host "Tag $tag already exists. Deleting old release..."
    gh release delete $tag --repo $repo --yes
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to delete existing release $tag."
        exit 1
    }
}

# Create new release with extracted changelog section
gh release create $tag $zipPath `
    --repo $repo `
    --title "${releaseName}" `
    --notes "${releaseNotes}"

if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to create GitHub release for tag $tag."
    exit 1
}

Write-Host "GitHub release created successfully."

# Cleanup temporary directories
if (Test-Path $publishDir) {
    Remove-Item $publishDir -Recurse -Force
    Write-Host "Cleaned up $publishDir directory."
}

# Keep release artifacts
Write-Host "Release artifacts kept in: $releaseDir"
Write-Host "Done."
