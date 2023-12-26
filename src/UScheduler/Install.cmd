"%~dp0PSScriptsService.exe" install

sc.exe create ".NET Joke Service" binpath="C:\Path\To\App.WindowsService.exe"
sc.exe create "Svc Name" binpath="C:\Path\To\App.exe --contentRoot C:\Other\Path"
pause