# What's new

Short notes shown in the app after an upgrade. The full history, including maintainer notes, is [CHANGELOG.md](CHANGELOG.md).

## [1.4.0] - 2026-10-05

- After an upgrade, What's New lists additions since the version you last opened.
- Help → Logs shows the program log and crash reports. Help → About shows the product, license, and contact.
- The window and the service are the same program. Re-register an existing service so it points at that program.
- Launch starts the script now through the running service. The window stays unelevated, and that run ignores the schedule and the minimum interval.
- Service messages show the command output. Copy puts that text on the clipboard.

## [1.3.0] - 2026-09-30

- An unhandled error opens a window you can copy. The same text is saved under the UScheduler logs folder.
- Windows setup keeps one desktop shortcut across upgrades.

## [1.2.0] - 2026-09-21

- Windows setup offers Standard or Portable. Portable keeps binaries, scripts, logs, and settings in the folder you choose.

## [1.1.0] - 2026-09-06

- The desktop window manages schedules, the service, and logs on Windows and Linux.
- Register, start, stop, and unregister ask for approval in place. The window stays unelevated.
- Scripts show a description and platform. A script for the other OS stays in the list, grayed out, and does not run.
