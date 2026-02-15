# MaksIT.UScheduler Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## v1.0.1 - 2026-02-15

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

## v1.0.0 - 2025-12-06

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

## v1.x.x - YYYY-MM-DD

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
