using MaksIT.Core.Logging;
using MaksIT.UScheduler;
using MaksIT.UScheduler.BackgroundServices;
using MaksIT.UScheduler.Services;
using Microsoft.Extensions.Logging.Configuration;
using Microsoft.Extensions.Logging.EventLog;
using System.Runtime.InteropServices;


// read configuration from appsettings.json
var configurationRoot = new ConfigurationBuilder()
  .SetBasePath(AppDomain.CurrentDomain.BaseDirectory)
  .AddJsonFile("appsettings.json", optional: true)
  .Build();

// Configure strongly typed settings objects
var configurationSection = configurationRoot.GetSection("Configuration");
var appSettings = configurationSection.Get<Configuration>() ?? throw new ArgumentNullException();

HostApplicationBuilder builder = Host.CreateApplicationBuilder(args);
builder.Services.AddWindowsService(options => {
  options.ServiceName = appSettings.ServiceName;
});

// Allow configurations to be available through IOptions<Configuration>
builder.Services.Configure<Configuration>(configurationSection);

// Logging
var logPath = !string.IsNullOrEmpty(appSettings.LogDir)
    ? Path.Combine(appSettings.LogDir)
    : Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "Logs");

if (!Directory.Exists(logPath)) {
  Directory.CreateDirectory(logPath);
}

builder.Logging.AddConsoleLogger(logPath);

if (RuntimeInformation.IsOSPlatform(OSPlatform.Windows)) {
  LoggerProviderOptions.RegisterProviderOptions<
      EventLogSettings, EventLogLoggerProvider>(builder.Services);
}

builder.Services.AddSingleton<ProcessService>();
builder.Services.AddHostedService<ProcessBackgroundService>();

builder.Services.AddSingleton<PSScriptService>();
builder.Services.AddHostedService<PSScriptBackgroundService>();

IHost host = builder.Build();

// Test logger
var loggerFactory = builder.Logging.Services.BuildServiceProvider().GetRequiredService<ILoggerFactory>();
var testLogger = loggerFactory.CreateLogger("LoggerTest");
testLogger.LogInformation("Logger test: This should appear in your log file.");

host.Run();