# Contributing to MaksIT.UScheduler

Thank you for your interest in contributing to MaksIT.UScheduler!

## Table of Contents

- [Development Setup](#development-setup)
- [Branch Strategy](#branch-strategy)
- [Making Changes](#making-changes)
- [Commit Message Format](#commit-message-format)
- [Versioning](#versioning)
- [Build and Test](#build-and-test)
- [Release Process](#release-process)
- [Changelog Guidelines](#changelog-guidelines)

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
5. Run tests locally (`utils/Invoke-TestEngine.bat`)
6. Submit a pull request to `dev`

---

## Commit Message Format

```
(type): description
```

| Type | Description |
|------|-------------|
| `(feature):` | New feature or enhancement |
| `(bugfix):` | Bug fix |
| `(refactor):` | Code refactoring without functional changes |
| `(perf):` | Performance improvement |
| `(test):` | Add or update tests |
| `(docs):` | Documentation-only changes |
| `(build):` | Build system, dependencies, or packaging |
| `(ci):` | CI/CD or automation changes |
| `(style):` | Formatting or non-functional style changes |
| `(revert):` | Revert a previous commit |
| `(chore):` | General maintenance |

Guidelines: lowercase description, no trailing period.

---

## Versioning

This project follows [Semantic Versioning](https://semver.org/):

- **MAJOR** - Incompatible API changes
- **MINOR** - New functionality (backwards compatible)
- **PATCH** - Bug fixes (backwards compatible)

Version format: `X.Y.Z` (e.g., `1.0.2`) or SemVer prerelease (`0.1.0-alpha.1`, `0.1.0-beta.1`, `0.1.0-rc.1`). Git tag is `v{version}`.

Before a release, keep versions aligned across:

1. **`src/MaksIT.UScheduler/MaksIT.UScheduler.csproj`** — canonical `<Version>`
2. **`src/MaksIT.UScheduler.UI/MaksIT.UScheduler.UI.csproj`**
3. **`CHANGELOG.md`** — matching version header

---

## Build and Test

### Tests and coverage badges

```powershell
.\utils\Invoke-TestEngine.bat
```

The test engine runs `MaksIT.UScheduler.Tests` under **Microsoft Testing Platform** (`src/global.json` `test.runner`) with **xunit.v3** and **coverlet.MTP**, applies the quality gate, and rewrites README coverage badges as shields.io URLs. Commit README.md when coverage changes. Or run `dotnet test` on the test project.

### Sync RepoUtils

Local-copy from [maksit-repoutils](https://git.maks-it.com/MAKS-IT/maksit-repoutils) (Community profile). Do not use `Update-RepoUtils`.

---

## Release Process

### Prerequisites

- .NET SDK
- PowerShell 7+
- Git CLI
- GitHub CLI (`gh`) — required for production releases on `main`
- `GitHub` environment variable (see `utils/engines/release/scriptSettings.json`)

### Development build (`dev` branch)

No git tag required. Uncommitted changes are allowed.

```powershell
# 1. Update version in .csproj files and CHANGELOG.md
git checkout dev

# 2. Run the release engine
.\utils\Invoke-ReleasePackage-Single.bat
```

Output: `release/maksit.uscheduler-{version}.zip` (local only; GitHub publish is skipped on non-release branches).

### Production release (`main` branch)

```powershell
# 1. Merge to main and ensure a clean working tree
git checkout main
git merge dev

# 2. Create tag matching the .csproj version
git tag v1.0.2

# 3. Run the release engine
.\utils\Invoke-ReleasePackage-Single.bat
```

On `main`, `ReleasePublishGuard` requires an exact tag on `HEAD` matching the .NET project version. The engine publishes tests, builds the bundle, creates the ZIP, and pushes a GitHub release when guard requirements are met.

Configuration: `utils/engines/release/scriptSettings.json`

---

## Changelog Guidelines

Follow [Keep a Changelog](https://keepachangelog.com/) format:

```markdown
## [1.0.2] - YYYY-MM-DD

### Added
- New features

### Changed
- Changes to existing functionality

### Fixed
- Bug fixes
```

---
