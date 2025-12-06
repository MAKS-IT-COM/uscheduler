sc.exe create "MaksIT.UScheduler Service" binpath="%~dp0MaksIT.UScheduler.exe"
sc description "MaksIT.UScheduler Service" "Windows service, which allows you to schedule and invoke PowerShell Scripts and Processes"
pause