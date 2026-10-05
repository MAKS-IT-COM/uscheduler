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
   dotnet build src/MaksIT.UScheduler.UI/MaksIT.UScheduler.UI.csproj
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
3. Update [CHANGELOG.md](CHANGELOG.md) and [WHATSNEW.md](WHATSNEW.md). What's New is the short list shown in the app. The changelog keeps Added, Changed, and Fixed, including maintainer notes.
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

1. **`src/MaksIT.UScheduler.UI/MaksIT.UScheduler.UI.csproj`** — canonical `<Version>`
2. **`CHANGELOG.md`** — matching version header
3. **`WHATSNEW.md`** — short notes for that version, shown in the app

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
# 1. Update version in .csproj files, CHANGELOG.md, and WHATSNEW.md
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

## Microsoft Store (MSIX)

`MsixPack` writes `releases/maksit-uscheduler-{version}.msix` from the Windows installer payload (the UI program plus bundled Scripts). It is a full-trust desktop package (`runFullTrust`), x64, language English (`en-us` only). Upload that file on an **MSIX** product in Partner Center. The Store re-signs it. An EXE/MSI product listing cannot take this file.

The UI project sets `SatelliteResourceLanguages` to `en`, and `MsixPack` drops any leftover culture folder that contains `*.resources.dll`. If that folder is packed, makeappx treats it as a second package language. Partner Center then reports the English resources as incomplete, even though the app UI is English only. A Store listing language marked incomplete is separate: that means a required listing field for that language is still empty.

Partner Center package identity for this product:

| Field | Value |
|-------|--------|
| Package/Identity/Name | `MAKS-IT.UScheduler` |
| Package/Identity/Publisher | `CN=FCC8C0E7-6D5F-4028-B8EE-903B88C0C8F9` |
| PublisherDisplayName | `MaksIT` |
| Package Family Name | `MAKS-IT.UScheduler_pt3s39h1tn26a` |
| Package SID | `S-1-15-2-839323616-4275740711-2118678478-1772334301-1145667798-1068409364-565805883` |
| Store ID | `9PLRWJ6G7RSF` |

Those name, publisher, and publisher display strings are `packageName`, `publisher`, and `publisherDisplayName` in `utils/engines/release/scriptSettings.json`. A placeholder publisher `CN=PartnerCenter` stops `MsixPack` until it is replaced.

The Store deep link and the Web Store URL are available after the product is live. The `.msix` is not a GitHub release asset.

Store listing copy:

| Field | Document |
|-------|----------|
| Short description, description, extra requirements | [packaging/microsoft-store/description.md](packaging/microsoft-store/description.md) |
| Product features (up to 20 bullets, 200 characters each) | [packaging/microsoft-store/product-features.md](packaging/microsoft-store/product-features.md) |
| Keywords (up to 7, 40 characters each, 21 words total) | [packaging/microsoft-store/keywords.md](packaging/microsoft-store/keywords.md) |
| Copyright, additional license terms, Developed by | [packaging/microsoft-store/additional-info.md](packaging/microsoft-store/additional-info.md) |
| Restricted capability `runFullTrust` | [packaging/microsoft-store/restricted-capabilities.md](packaging/microsoft-store/restricted-capabilities.md) |
| Store logos (9:16 poster, 1:1 box art, app tiles) | [packaging/microsoft-store/logos.md](packaging/microsoft-store/logos.md) |

### System requirements (Properties)

Partner Center → **Properties** → **System requirements**. A blank cell stays unset. Minimum is what the Store may warn on; Recommended does not warn.

The app is a win-x64 desktop scheduler. It does not use a camera, microphone, radio, gamepad, or a specific GPU.

| Feature | Minimum | Recommended |
|---------|---------|-------------|
| Touch screen | | |
| Keyboard | Minimum | |
| Mouse | Minimum | |
| Camera | | |
| NFC HCE | | |
| NFC Proximity | | |
| Bluetooth LE | | |
| Telephony | | |
| Microphone | | |
| Xbox controller or gamepad | | |
| Windows Mixed Reality motion controllers | | |
| Windows Mixed Reality immersive headset | | |
| Memory | 2 GB | 4 GB |
| DirectX | Not specified | Not specified |
| Video memory | Not specified | Not specified |
| Processor | x64 | Not specified |
| Graphics | Not specified | Not specified |

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

## License

By contributing, you agree that your contributions are licensed under the terms in [LICENSE.md](LICENSE.md) (Apache 2.0).

---
