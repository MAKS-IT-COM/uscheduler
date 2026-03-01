# Contributing to MaksIT.UScheduler

Thank you for your interest in contributing to MaksIT.UScheduler!

## Table of Contents

- [Contributing to MaksIT.UScheduler](#contributing-to-maksituscheduler)
  - [Table of Contents](#table-of-contents)
  - [Development Setup](#development-setup)
  - [Branch Strategy](#branch-strategy)
  - [Making Changes](#making-changes)
  - [Versioning](#versioning)
  - [Release Process](#release-process)
    - [Prerequisites](#prerequisites)
    - [Version Files](#version-files)
    - [Branch-Based Release Behavior](#branch-based-release-behavior)
    - [Development Build Workflow](#development-build-workflow)
    - [Production Release Workflow](#production-release-workflow)
    - [Release Script Details](#release-script-details)
  - [Changelog Guidelines](#changelog-guidelines)
    - [AI-Powered Changelog Generation (Optional)](#ai-powered-changelog-generation-optional)

---

## Development Setup

1. Clone the repository:
   ```bash
   git clone https://github.com/MaksIT/uscheduler.git
   cd uscheduler
   ```

2. Open the solution in Visual Studio or your preferred IDE:
   ```
   src/MaksIT.UScheduler.slnx
   ```

3. Build the project:
   ```bash
   dotnet build src/MaksIT.UScheduler/MaksIT.UScheduler.csproj
   ```

---

## Branch Strategy

- `main` - Production-ready code
- `dev` - Active development branch
- Feature branches - Created from `dev` for specific features

---

## Making Changes

1. Create a feature branch from `dev`
2. Make your changes
3. Update `CHANGELOG.md` with your changes
4. Update version in `.csproj` if needed
5. Test your changes locally using dev tags
6. Submit a pull request to `dev`

---

## Versioning

This project follows [Semantic Versioning](https://semver.org/):

- **MAJOR** - Incompatible API changes
- **MINOR** - New functionality (backwards compatible)
- **PATCH** - Bug fixes (backwards compatible)

Version format: `X.Y.Z` (e.g., `1.0.1`)

---

## Release Process

### Prerequisites

- .NET SDK installed
- Git CLI
- GitHub CLI (`gh`) - required only for production releases
- GitHub token set in environment variable (configured in `scriptsettings.json`)

### Version Files

Before creating a release, ensure version consistency across:

1. **`.csproj`** - Update `<Version>` element:
   ```xml
   <Version>1.0.1</Version>
   ```

2. **`CHANGELOG.md`** - Add version entry at the top:
   ```markdown
   ## v1.0.1

   ### Added
   - New feature description

   ### Fixed
   - Bug fix description
   ```

### Branch-Based Release Behavior

The release script behavior is controlled by the current branch (configurable in `scriptsettings.json`):

| Branch | Tag Required | Uncommitted Changes | Behavior |
|--------|--------------|---------------------|----------|
| Dev (`dev`) | No | Allowed | Local build only (version from .csproj) |
| Release (`main`) | Yes | Not allowed | Full release to GitHub |
| Other | - | - | Blocked |

Branch names can be customized in `scriptsettings.json`:
```json
"branches": {
  "release": "main",
  "dev": "dev"
}
```

### Development Build Workflow

Test builds on the `dev` branch - no tag needed:

```bash
# 1. On dev branch: Update version in .csproj and CHANGELOG.md
git checkout dev

# 2. Commit your changes
git add .
git commit -m "Prepare v1.0.1 release"

# 3. Run the release script (no tag needed!)
cd src/scripts/Release-ToGitHub
.\Release-ToGitHub.ps1

# Output: DEV BUILD COMPLETE
# Creates: release/maksit.uscheduler-1.0.1.zip (local only)
```

### Production Release Workflow

When ready to publish, merge to `main`, create tag, and run:

```bash
# 1. Merge to main
git checkout main
git merge dev

# 2. Create tag (required on main)
git tag v1.0.1

# 3. Run the release script
cd src/scripts/Release-ToGitHub
.\Release-ToGitHub.ps1

# Output: RELEASE COMPLETE
# Creates: release/maksit.uscheduler-1.0.1.zip
# Pushes tag to GitHub
# Creates GitHub release with assets
```

### Release Script Details

The `Release-ToGitHub.ps1` script performs these steps:

**Pre-flight checks:**
- Detects current branch (`main` or `dev`)
- On `main`: requires clean working directory; on `dev`: uncommitted changes allowed
- Reads version from `.csproj` (source of truth)
- On `main`: requires tag matching the version
- Ensures `CHANGELOG.md` has matching version entry
- Checks GitHub CLI authentication (main branch only)

**Build process:**
- Publishes .NET project in Release configuration
- Copies `Scripts` folder into the release
- Creates versioned ZIP archive
- Extracts release notes from `CHANGELOG.md`

**GitHub release (main branch only):**
- Pushes tag to remote if not present
- Creates (or recreates) GitHub release with assets

**Configuration:**

The script reads settings from `scriptsettings.json`:

```json
{
  "github": {
    "tokenEnvVar": "GITHUB_MAKS_IT_COM"
  },
  "paths": {
    "csprojPath": "..\\..\\MaksIT.UScheduler\\MaksIT.UScheduler.csproj",
    "changelogPath": "..\\..\\..\\CHANGELOG.md",
    "releaseDir": "..\\..\\release"
  },
  "release": {
    "zipNamePattern": "maksit.uscheduler-{version}.zip",
    "releaseTitlePattern": "Release {version}"
  }
}
```

---

## Changelog Guidelines

Follow [Keep a Changelog](https://keepachangelog.com/) format:

```markdown
## v1.0.1

### Added
- New features

### Changed
- Changes to existing functionality

### Deprecated
- Features to be removed in future

### Removed
- Removed features

### Fixed
- Bug fixes

### Security
- Security-related changes
```

---
