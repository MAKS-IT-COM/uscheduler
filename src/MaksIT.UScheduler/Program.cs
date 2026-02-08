using System.Diagnostics;
using System.Runtime.InteropServices;
using Microsoft.Extensions.Logging.EventLog;
using Microsoft.Extensions.Logging.Configuration;
using MaksIT.Core.Logging;
using MaksIT.UScheduler.BackgroundServices;
using MaksIT.UScheduler.Services;
using MaksIT.UScheduler.Shared;


// OS Guard - This application only supports Windows
if (!RuntimeInformation.IsOSPlatform(OSPlatform.Windows)) {
  Console.WriteLine("Error: MaksIT.UScheduler only supports Windows.");
  return 1;
}

// Read configuration from appsettings.json
var configurationRoot = new ConfigurationBuilder()
  .SetBasePath(AppDomain.CurrentDomain.BaseDirectory)
  .AddJsonFile("appsettings.json", optional: true, reloadOnChange: true)
  .Build();

// Configure strongly typed settings objects
var configurationSection = configurationRoot.GetSection("Configuration");
var appSettings = configurationSection.Get<Configuration>() ?? throw new InvalidOperationException("Configuration section is missing.");
if (string.IsNullOrWhiteSpace(appSettings.LogDir))
  throw new InvalidOperationException("Configuration.LogDir is required. Set it in appsettings.json (e.g. \".\\Logs\").");

// Handle command-line arguments for service management
if (args.Length > 0) {
  var command = args[0].ToLowerInvariant();
  var exePath = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "MaksIT.UScheduler.exe");
  var serviceName = appSettings.ServiceName;
  var serviceDescription = "Windows service that allows you to schedule and invoke PowerShell Scripts and Processes";

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

    case "--help":
    case "-h":
    case "/?":
      PrintHelp(serviceName);
      return 0;

    default:
      // If not a recognized command, continue with normal startup
      break;
  }
}

HostApplicationBuilder builder = Host.CreateApplicationBuilder(args);
builder.Services.AddWindowsService(options => {
  options.ServiceName = appSettings.ServiceName;
});

// Allow configurations to be available through IOptions<Configuration>
builder.Services.Configure<Configuration>(configurationSection);
builder.Services.AddHostedService<ConfigurationReloadBackgroundService>();

// Logging: resolve LogDir (required); relative paths are resolved against application base directory
var baseDir = AppDomain.CurrentDomain.BaseDirectory;
var logPath = Path.IsPathRooted(appSettings.LogDir)
    ? appSettings.LogDir
    : Path.GetFullPath(Path.Combine(baseDir, appSettings.LogDir));

if (!Directory.Exists(logPath)) {
  Directory.CreateDirectory(logPath);
}

builder.Logging.AddConsoleLogger(logPath);

LoggerProviderOptions.RegisterProviderOptions<
    EventLogSettings, EventLogLoggerProvider>(builder.Services);

builder.Services.AddSingleton<IProcessService, ProcessService>();
builder.Services.AddHostedService<ProcessBackgroundService>();

builder.Services.AddSingleton<IPSScriptService, PSScriptService>();
builder.Services.AddHostedService<PSScriptBackgroundService>();

IHost host = builder.Build();

// Test logger
var loggerFactory = builder.Logging.Services.BuildServiceProvider().GetRequiredService<ILoggerFactory>();
var testLogger = loggerFactory.CreateLogger("LoggerTest");
testLogger.LogInformation("Logger test: This should appear in your log file.");

host.Run();
return 0;


// Service management functions
static int InstallService(string serviceName, string exePath, string description) {
  Console.WriteLine($"Installing service '{serviceName}'...");

  // Create the service
  var createResult = RunScCommand($"create \"{serviceName}\" binpath=\"{exePath}\" start=auto");
  if (createResult != 0) {
    Console.WriteLine("Failed to create service.");
    return createResult;
  }

  // Set description
  var descResult = RunScCommand($"description \"{serviceName}\" \"{description}\"");
  if (descResult != 0) {
    Console.WriteLine("Warning: Failed to set service description.");
  }

  Console.WriteLine($"Service '{serviceName}' installed successfully.");
  Console.WriteLine($"Use '--start' to start the service or start it from services.msc");
  return 0;
}

static int UninstallService(string serviceName) {
  Console.WriteLine($"Stopping service '{serviceName}'...");
  RunScCommand($"stop \"{serviceName}\"");

  Console.WriteLine($"Uninstalling service '{serviceName}'...");
  var result = RunScCommand($"delete \"{serviceName}\"");

  if (result == 0) {
    Console.WriteLine($"Service '{serviceName}' uninstalled successfully.");
  }
  else {
    Console.WriteLine("Failed to uninstall service.");
  }

  return result;
}

static int StartService(string serviceName) {
  Console.WriteLine($"Starting service '{serviceName}'...");
  var result = RunScCommand($"start \"{serviceName}\"");

  if (result == 0) {
    Console.WriteLine($"Service '{serviceName}' started successfully.");
  }
  else {
    Console.WriteLine("Failed to start service.");
  }

  return result;
}

static int StopService(string serviceName) {
  Console.WriteLine($"Stopping service '{serviceName}'...");
  var result = RunScCommand($"stop \"{serviceName}\"");

  if (result == 0) {
    Console.WriteLine($"Service '{serviceName}' stopped successfully.");
  }
  else {
    Console.WriteLine("Failed to stop service.");
  }

  return result;
}

static int GetServiceStatus(string serviceName) {
  return RunScCommand($"query \"{serviceName}\"");
}

static int RunScCommand(string arguments) {
  try {
    var process = new Process {
      StartInfo = new ProcessStartInfo {
        FileName = "sc.exe",
        Arguments = arguments,
        UseShellExecute = false,
        RedirectStandardOutput = true,
        RedirectStandardError = true,
        CreateNoWindow = true
      }
    };

    process.Start();

    var output = process.StandardOutput.ReadToEnd();
    var error = process.StandardError.ReadToEnd();

    process.WaitForExit();

    if (!string.IsNullOrWhiteSpace(output))
      Console.WriteLine(output);

    if (!string.IsNullOrWhiteSpace(error))
      Console.WriteLine(error);

    return process.ExitCode;
  }
  catch (Exception ex) {
    Console.WriteLine($"Error executing sc.exe: {ex.Message}");
    return 1;
  }
}

static void PrintHelp(string serviceName) {
  Console.WriteLine($"""
    MaksIT.UScheduler - Windows Service Scheduler

    Usage: MaksIT.UScheduler.exe [command]

    Commands:
      --install, -i    Install the Windows service
      --uninstall, -u  Uninstall the Windows service
      --start          Start the service
      --stop           Stop the service
      --status         Query service status
      --help, -h       Show this help message

    Configuration:
      Service Name: {serviceName}
      Config File:  appsettings.json

    Examples:
      MaksIT.UScheduler.exe --install    # Install and register the service
      MaksIT.UScheduler.exe --start      # Start the service
      MaksIT.UScheduler.exe --stop       # Stop the service
      MaksIT.UScheduler.exe --uninstall  # Remove the service

    Note: Service management commands require administrator privileges.
    """);
}