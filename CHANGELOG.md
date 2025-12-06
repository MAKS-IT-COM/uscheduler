# MaksIT.UScheduler Changelog

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
- Updated install/uninstall scripts (`Install.cmd`, `Uninstall.cmd`) for service management.
- Added comprehensive README with usage, configuration, and scheduling examples.
- MIT License included.

### Breaking Changes
- Old solution, project, and service files removed.
- Configuration format and service naming conventions updated.
- Scheduling logic for console applications is not yet implemented (runs every 10 seconds).
