# MaksIT.UScheduler Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.1.1] - 2026-09-06

### Fixed

- Windows setup exe now ships bundled Scripts next to the worker and runs `--prepare-data` after files are installed, so example scripts are copied to `C:\MaksIT\Scripts` when those folders do not already exist.

## [1.1.0] - 2026-09-06

### Added

- **Avalonia UScheduler UI** on Windows and Linux (replaces WPF Schedule Manager).
- **Linux systemd** install/start/stop for the worker (`Type=notify`), matching Windows SCM.
- `--prepare-data` creates scripts, logs, and shared-settings folders (and ACLs) without registering the service.
- Community desktop GitHub assets: portable `maksit-uscheduler-{version}.zip` (win-x64 worker, UI, Scripts), Windows setup exe, and Flatpak of the UI.
- Script list shows a description and platform (`Windows` / `Linux`). Incompatible scripts stay in the list but are grayed out; the worker does not run them. Bundled Hyper-V Backup, Windows Update, and File Sync are Windows-only.

### Changed

- **Schedule Manager** is now **MaksIT.UScheduler.UI**. The UI launches without elevation; register/start/stop/unregister prompt for UAC (or pkexec) in place.
- Worker and UI install to `C:\Program Files\MaksIT\UScheduler` (Linux: `/opt/maksit/uscheduler`). The Windows setup exe is **x64** (not Program Files (x86)) and ships worker + UI in that folder. Scripts live in `C:\MaksIT\Scripts` (`/var/lib/maksit/scripts`) and logs in `C:\MaksIT\Logs` (`/var/log/maksit`), with Users/group write after `--install` / `--prepare-data`. Bundled examples are copied only when the destination file or script folder does not already exist; existing customizations are left unchanged.
- Schedule configuration is stored in `%ProgramData%\MaksIT\UScheduler\settings.json` (Linux: `/var/lib/maksit/uscheduler/settings.json`). Shipped `appsettings.json` next to the worker keeps host logging and a first-run Configuration seed. Per-user UI prefs stay in `%AppData%\MaksIT\UScheduler\settings.json`.
- UI dark theme uses the MAKS.IT origami blues (`#33A5CF` / `#006199`). App icon is a faceted scheduler clock (not the brand M).
- Worker is no longer Windows-only: no `win-x64` RID lock; Event Log logging stays Windows-only.
- `sc.exe create` uses `binPath= ` / `start= auto` (space after `=`).
- **Tests:** migrate to **xunit.v3** **4.0** + **Microsoft Testing Platform** (`src/global.json` `test.runner`; **coverlet.MTP**). README coverage badges are shields.io URLs.
- Synced RepoUtils to the Community desktop profile (local-copy only; no `Update-RepoUtils`). Release engine QualityGate / publish / installer / Flatpak target **MaksIT.UScheduler.UI**.

### Removed

- WPF **MaksIT.UScheduler.ScheduleManager** project.
- SVG coverage badges under `assets/badges/`.

## [1.0.3] - 2026-06-28

### Added
- **RepoUtils release engine**: `utils/engines/release/` with `BundleCustomization` plugin for bundled ZIP releases
- **`.editorconfig`**: repo-wide C# formatting (2-space indent, MaksIT brace style)

### Changed
- **PSScriptGateway**: MaksIT.Core logging/middleware, layered config, camelCase JSON, and `Result<T>` → `ToActionResult()` flow
- **README** and **CONTRIBUTING**: RepoUtils test/release entry points, commit format, and coverage badge workflow

### Fixed
- **Release packaging**: `utils/Invoke-ReleasePackage.bat` now targets a wired release engine (previously missing `utils/engines/release/`)
- **ScheduleManager version**: aligned with `MaksIT.UScheduler` at `1.0.3`

## [1.0.2] - 2026-03-01

### Fixed
- **PowerShell module loading**: Scripts with module dependencies now execute correctly when running as Windows service
  - Added recursive dependency scanning using PowerShell AST parser
  - Automatically unblocks `Import-Module`, `using module`, and dot-sourced (`. ./file.ps1`) dependencies
  - Resolves "AuthorizationManager check failed" errors for modules downloaded from the internet
  - Supports `.psm1` and `.psd1` module files in script directory and subfolders

## [1.0.1] - 2026-02-15

### Added
- **CLI service management**: Added command-line arguments for service installation and management
  - `--install`, `-i`: Install the Windows service
  - `--uninstall`, `-u`: Uninstall the Windows service
  - `--start`: Start the service
  - `--stop`: Stop the service
  - `--status`: Query service status
  - `--help`, `-h`: Show help message
- **Relative path support**: Script and process paths can now be relative to the application directory
- **OS guard**: Application now checks for Windows at startup and exits with error on unsupported platforms
- **Release script enhancement**: Example scripts are now automatically added to `appsettings.json` in disabled state during release build
- **Unit tests**: Added comprehensive test project `MaksIT.UScheduler.Tests` with tests for background services and configuration
- **Uscheduler Manager UI**: Introduced a graphical user interface (WPF) for managing script schedules, viewing script status, and editing configuration in real time
- **Live configuration reload**: Added `ConfigurationReloadBackgroundService` to log configuration changes at runtime
- **Hot-reload for scripts/processes**: Background services now use `IOptionsMonitor<Configuration>` to pick up changes in `appsettings.json` without restart

### Changed
- Default value for `IsSigned` in PowerShell script configuration changed from `false` to `true` for improved security
- PSScriptService now implements `IDisposable` for proper RunspacePool cleanup
- Method signatures updated: `RunScript` → `RunScriptAsync`, `RunProcess` → `RunProcessAsync`
- Service is now installed with `start=auto` for automatic startup on boot
- Updated package dependencies:
  - MaksIT.Core: 1.6.0 → 1.6.3
  - Microsoft.Extensions.Hosting: 10.0.0 → 10.0.3
  - Microsoft.Extensions.Hosting.WindowsServices: 10.0.0 → 10.0.3
  - System.Diagnostics.PerformanceCounter: 10.0.0 → 10.0.3
  - Microsoft.Extensions.Logging.Abstractions: 10.0.2 → 10.0.3

### Removed
- `Install.cmd` and `Uninstall.cmd` files (replaced by CLI arguments)

### Fixed
- **Parallel execution**: Restored parallel execution of PowerShell scripts and processes (broken during .NET Framework to .NET migration)
  - PSScriptService now uses RunspacePool (up to CPU core count) for concurrent script execution
  - Background services use `Task.WhenAll` to launch all tasks simultaneously
- **Unit test improvements**: Refactored tests to use `IOptionsMonitor<Configuration>` for better coverage and reliability

## [1.0.0] - 2025-12-06

### Major Changes
- Migrate of the Unified Scheduler Service in .NET 10 (previously .NET 8).
- New solution and project structure under `MaksIT.UScheduler`.
- Added support for scheduling and running both PowerShell scripts and console applications as Windows services.
- Strongly typed configuration via `appsettings.json` and `Configuration.cs`.
- Improved logging with configurable log directory.
- New background services:
	- `PSScriptBackgroundService` for PowerShell script execution.
	- `ProcessBackgroundService` for process management.
- Enhanced PowerShell script execution with signature validation and script unblocking.
- Improved process management with restart-on-failure logic.
- Added install/uninstall scripts (`Install.cmd`, `Uninstall.cmd`) for service management (removed in v1.0.1).
- Added comprehensive README with usage, configuration, and scheduling examples.
- MIT License included.

### Breaking Changes
- Old solution, project, and service files removed.
- Configuration format and service naming conventions updated.
- Scheduling logic for console applications is not yet implemented (runs every 10 seconds).

<!-- 
Template for new releases:

## [1.x.x] - YYYY-MM-DD

### Added
- New features

### Changed
- Changes in existing functionality

### Deprecated
- Soon-to-be removed features

### Removed
- Removed features

### Fixed
- Bug fixes

### Security
- Security improvements
-->

