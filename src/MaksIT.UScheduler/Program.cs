using System.Diagnostics;
using Microsoft.Extensions.Logging.EventLog;
using Microsoft.Extensions.Logging.Configuration;
using MaksIT.Core.Logging;
using MaksIT.UScheduler.Shared;
using MaksIT.UScheduler.Services;
using MaksIT.UScheduler.BackgroundServices;


var basePath = AppContext.BaseDirectory;
var seedPath = Path.Combine(basePath, ConfigurationFileService.SeedFileName);
var settingsPath = HostPaths.SharedSettingsFile;

if (args.Length > 0) {
  var early = args[0].ToLowerInvariant();
  if (early is "--install" or "-i" or "--prepare-data") {
    var prepared = HostDataDirectories.Prepare(basePath);
    Console.WriteLine(prepared.Message);
    if (!prepared.Success)
      return 1;
  }
}

_ = new ConfigurationFileService(settingsPath, seedPath);

var configurationRoot = new ConfigurationBuilder()
  .SetBasePath(basePath)
  .AddJsonFile("appsettings.json", optional: true, reloadOnChange: true)
  .AddJsonFile(settingsPath, optional: true, reloadOnChange: true)
  .Build();

var configurationSection = configurationRoot.GetSection("Configuration");
var appSettings = configurationSection.Get<Configuration>() ?? new Configuration();
appSettings.EnsureDefaults();

var serviceName = string.IsNullOrWhiteSpace(appSettings.ServiceName)
  ? "MaksIT.UScheduler"
  : appSettings.ServiceName.Trim();
var serviceDescription = "Schedules and invokes PowerShell scripts and processes";

if (args.Length > 0) {
  var command = args[0].ToLowerInvariant();
  var exePath = Path.GetFullPath(
    Environment.ProcessPath
    ?? Path.Combine(basePath, HostServiceManager.GetExecutableFileName()));

  switch (command) {
    case "--install":
    case "-i":
      return InstallService(serviceName, exePath, serviceDescription);

    case "--uninstall":
    case "-u":
      return UninstallService(serviceName);

    case "--start":
      return StartService(serviceName);

    case "--stop":
      return StopService(serviceName);

    case "--status":
      return GetServiceStatus(serviceName);

    case "--prepare-data":
      return PrepareDataDirectories(basePath);

    case "--help":
    case "-h":
    case "/?":
      PrintHelp(serviceName);
      return 0;
  }
}

var builder = Host.CreateApplicationBuilder(new HostApplicationBuilderSettings {
  Args = args,
  ContentRootPath = basePath
});

if (OperatingSystem.IsWindows()) {
  builder.Services.AddWindowsService(options => {
    options.ServiceName = serviceName;
  });
}

if (OperatingSystem.IsLinux())
  builder.Services.AddSystemd();

builder.Services.Configure<Configuration>(configurationSection);
builder.Services.AddHostedService<ConfigurationReloadBackgroundService>();

var logPath = appSettings.GetEffectiveLogDirectory(basePath);

Directory.CreateDirectory(logPath);
builder.Logging.AddConsoleLogger(logPath);

if (OperatingSystem.IsWindows()) {
  LoggerProviderOptions.RegisterProviderOptions<
    EventLogSettings, EventLogLoggerProvider>(builder.Services);
}

builder.Services.AddSingleton<IProcessService, ProcessService>();
builder.Services.AddHostedService<ProcessBackgroundService>();

builder.Services.AddSingleton<IPSScriptService, PSScriptService>();
builder.Services.AddHostedService<PSScriptBackgroundService>();

builder.Build().Run();
return 0;


static void PrintHelp(string name) =>
  Console.WriteLine(
    $"""
    MaksIT.UScheduler - PowerShell and process scheduler

    Usage: MaksIT.UScheduler [command]

    Commands:
      --install, -i    Install the service (Windows SCM or systemd)
      --uninstall, -u  Uninstall the service
      --start          Start the service
      --stop           Stop the service
      --status         Query service status
      --prepare-data   Create C:\MaksIT\Scripts, C:\MaksIT\Logs, and shared settings (elevated)
      --help, -h       Show this help message

    Service Name: {name}
    Config File:  {HostPaths.SharedSettingsFile}
    Seed File:    appsettings.json (next to the executable, logging + first-run seed)

    Note: Install/uninstall/prepare-data typically require administrator / root privileges.
    """);

static int GetServiceStatus(string name) {
  if (OperatingSystem.IsWindows())
    return RunScCommand($"query \"{name}\"");

  if (OperatingSystem.IsLinux())
    return RunSystemctl($"status {name} --no-pager");

  Console.WriteLine("Service status is only supported on Windows and Linux.");
  return 1;
}

static int StartService(string name) {
  if (OperatingSystem.IsWindows())
    return RunScCommand($"start \"{name}\"");

  if (OperatingSystem.IsLinux())
    return RunSystemctl($"start {name}");

  Console.WriteLine("Service start is only supported on Windows and Linux.");
  return 1;
}

static int StopService(string name) {
  if (OperatingSystem.IsWindows())
    return RunScCommand($"stop \"{name}\"");

  if (OperatingSystem.IsLinux())
    return RunSystemctl($"stop {name}");

  Console.WriteLine("Service stop is only supported on Windows and Linux.");
  return 1;
}

static int InstallService(string name, string exePath, string description) {
  if (!HostServiceRegistration.IsValidServiceName(name)) {
    Console.WriteLine($"Invalid service name '{name}'. Use letters, digits, '.', '-', '_' or '@'.");
    return 1;
  }

  if (!File.Exists(exePath)) {
    Console.WriteLine($"Executable not found: {exePath}");
    return 1;
  }

  if (OperatingSystem.IsWindows())
    return InstallWindowsService(name, exePath, description);

  if (OperatingSystem.IsLinux())
    return InstallLinuxService(name, exePath, description);

  Console.WriteLine("Service install is only supported on Windows and Linux.");
  return 1;
}

static int PrepareDataDirectories(string installDirectory) {
  Console.WriteLine($"Install:  {installDirectory}");
  Console.WriteLine($"Settings: {HostPaths.SharedSettingsFile}");
  Console.WriteLine($"Scripts:  {HostPaths.DefaultScriptsDirectory}");
  Console.WriteLine($"Logs:     {HostPaths.DefaultLogDirectory}");
  return 0;
}

static int UninstallService(string name) {
  if (OperatingSystem.IsWindows())
    return UninstallWindowsService(name);

  if (OperatingSystem.IsLinux())
    return UninstallLinuxService(name);

  Console.WriteLine("Service uninstall is only supported on Windows and Linux.");
  return 1;
}

static int InstallWindowsService(string name, string exePath, string description) {
  Console.WriteLine($"Installing Windows service '{name}'...");
  var exitCode = RunScCommand(HostServiceRegistration.FormatWindowsCreateArguments(name, exePath));
  if (exitCode != 0) {
    Console.WriteLine("Failed to create service. Run from an elevated prompt.");
    return exitCode;
  }

  RunScCommand(HostServiceRegistration.FormatWindowsDescriptionArguments(name, description));
  Console.WriteLine($"Service '{name}' installed successfully.");
  return 0;
}

static int UninstallWindowsService(string name) {
  Console.WriteLine($"Stopping service '{name}'...");
  RunScCommand($"stop \"{name}\"");
  Console.WriteLine($"Uninstalling service '{name}'...");
  return RunScCommand($"delete \"{name}\"");
}

static int InstallLinuxService(string name, string exePath, string description) {
  var unitPath = HostServiceRegistration.GetSystemdUnitPath(name);
  Console.WriteLine($"Installing systemd unit '{unitPath}'...");
  EnsureUnixExecutable(exePath);

  try {
    File.WriteAllText(unitPath, HostServiceRegistration.FormatSystemdUnit(name, exePath, description));
  }
  catch (Exception ex) {
    Console.WriteLine($"Failed to write unit file (need root?): {ex.Message}");
    return 1;
  }

  var reload = RunSystemctl("daemon-reload");
  if (reload != 0)
    return reload;

  var enable = RunSystemctl($"enable {name}");
  if (enable != 0)
    return enable;

  Console.WriteLine($"Service '{name}' installed. Use --start to start it.");
  return 0;
}

static int UninstallLinuxService(string name) {
  RunSystemctl($"stop {name}");
  RunSystemctl($"disable {name}");
  var unitPath = HostServiceRegistration.GetSystemdUnitPath(name);
  try {
    if (File.Exists(unitPath))
      File.Delete(unitPath);
  }
  catch (Exception ex) {
    Console.WriteLine($"Failed to remove unit file (need root?): {ex.Message}");
    return 1;
  }

  return RunSystemctl("daemon-reload");
}

static void EnsureUnixExecutable(string exePath) {
  if (!OperatingSystem.IsLinux() && !OperatingSystem.IsMacOS())
    return;

  try {
    var mode = File.GetUnixFileMode(exePath);
    File.SetUnixFileMode(
      exePath,
      mode | UnixFileMode.UserExecute | UnixFileMode.GroupExecute | UnixFileMode.OtherExecute);
  }
  catch (Exception ex) {
    Console.WriteLine($"Warning: could not set execute bit on '{exePath}': {ex.Message}");
  }
}

static int RunScCommand(string arguments) =>
  RunProcess(Path.Combine(Environment.SystemDirectory, "sc.exe"), arguments);

static int RunSystemctl(string arguments) =>
  RunProcess("systemctl", arguments);

static int RunProcess(string fileName, string arguments) {
  try {
    using var process = Process.Start(new ProcessStartInfo {
      FileName = fileName,
      Arguments = arguments,
      UseShellExecute = false,
      RedirectStandardOutput = true,
      RedirectStandardError = true,
      CreateNoWindow = true
    });

    if (process is null) {
      Console.WriteLine($"Failed to start {fileName}.");
      return 1;
    }

    Console.Write(process.StandardOutput.ReadToEnd());
    Console.Write(process.StandardError.ReadToEnd());
    process.WaitForExit();
    return process.ExitCode;
  }
  catch (Exception ex) {
    Console.WriteLine($"Error executing {fileName}: {ex.Message}");
    return 1;
  }
}
