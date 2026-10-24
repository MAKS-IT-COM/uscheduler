# Microsoft Store description

Paste into Partner Center → Store listings. Plain text only. URLs in these fields are not clickable; put the privacy policy, support site, and license in their own submission fields.

Leave **What's new in this version** empty on the first submission. Use it only for a later update (1,500 characters).

Hardware checkboxes (keyboard, memory, processor) stay in [CONTRIBUTING.md](../../CONTRIBUTING.md) under **System requirements (Properties)**.

## Short description

Shown at the top of the listing. The field allows 1,000 characters. Keep this under 270 so every Store view shows the full sentence.

```text
Schedule PowerShell scripts on this PC, and keep console programs running. Register the service, edit when each script runs, launch one now, and follow its log. The window stays unelevated.
```

## Description

Required. Up to 10,000 characters. This text is different from the short description so the page does not repeat the same paragraph.

```text
Run PowerShell scripts on a schedule, and keep console programs running, without leaving a terminal open.

The same program is the window and the Windows service. Register, start, stop, and unregister ask for administrator approval in place. The window stays open and does not restart as administrator.

Launch starts the selected script now through the running service. That run ignores the schedule and the minimum interval. The script log is written the same way as a scheduled run, and a window follows the new lines until the run finishes. A second launch of the same script uses the window that is already open.

Each script shows a description and whether it is for Windows, Linux, or both. A script for the other operating system stays in the list, grayed out, and does not run. Example scripts ship disabled: Hyper-V backup, Windows Update, file sync, and a pure PowerShell folder sync. Enable one in the window when you want it. Existing script files are not overwritten when you install again.

The Processes tab lists programs the service keeps running. A program starts with the service, restarts when it exits, and stops when the service stops. Start, Stop, and Restart ask the running service, so the program runs as the service account.

Schedules and the script list are stored in the shared settings file. On a standard install that is %ProgramData%\MaksIT\UScheduler\settings.json. Scripts default to C:\MaksIT\Scripts and logs to C:\MaksIT\Logs. Windows setup Options sets those folders. Preparing them asks for approval once. Service logs and script logs open in the window. Help → Logs shows the program log and crash reports. Help → About shows the product, license, and contact. After an upgrade, What's New lists additions since the version you last opened.

You need 64-bit Windows 10 or Windows 11. Service registration needs administrator approval. The window itself does not.
```

Product features (up to 20 bullets) are in [product-features.md](product-features.md). Keywords are in [keywords.md](keywords.md). Copyright, additional license terms, and Developed by are in [additional-info.md](additional-info.md).

## Additional system requirements

Optional text lines, separate from the Properties hardware table. Up to 11 minimum and 11 recommended. Each line is at most 200 characters.

Minimum:

```text
64-bit Windows 10 or Windows 11
```

Recommended:

```text
Administrator approval when you register, start, or stop the service
```

Category: Utilities & tools.
