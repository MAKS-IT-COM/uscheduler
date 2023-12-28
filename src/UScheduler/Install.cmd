sc.exe create "Unified Scheduler Service" binpath="%~dp0UScheduler.exe"
sc description "Unified Scheduler Service" "Windows service, which allows you to invoke PowerShell Scripts and Processes"
pause