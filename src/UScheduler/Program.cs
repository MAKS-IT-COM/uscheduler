using Microsoft.Extensions.Logging.Configuration;
using Microsoft.Extensions.Logging.EventLog;
using System.Runtime.InteropServices;
using UScheduler;
using UScheduler.BackgroundServices;
using UScheduler.Services;

// read configuration from appsettings.json
var configurationRoot = new ConfigurationBuilder()
  .SetBasePath(AppDomain.CurrentDomain.BaseDirectory)
  .AddJsonFile("appsettings.json", optional: true)
  .AddJsonFile($"appsettings.{Environment.GetEnvironmentVariable("ASPNETCORE_ENVIRONMENT") ?? "Production"}.json", optional: true)
  .Build();

// bind Configuration section inside configuration to a new instance of Settings
var configuration = new Configuration();
configurationRoot.GetSection("Configurations").Bind(configuration);
 
HostApplicationBuilder builder = Host.CreateApplicationBuilder(args);
builder.Services.AddWindowsService(options => {
  options.ServiceName = configuration.ServiceNameOrDefault;
});

if (RuntimeInformation.IsOSPlatform(OSPlatform.Windows)) {
  LoggerProviderOptions.RegisterProviderOptions<
      EventLogSettings, EventLogLoggerProvider>(builder.Services);
}

builder.Services.Configure<Configuration>(configurationRoot.GetSection("Configurations"));

builder.Services.AddSingleton<ProcessService>();
builder.Services.AddHostedService<ProcessBackgroundService>();

builder.Services.AddSingleton<PSScriptService>();
builder.Services.AddHostedService<PSScriptBackgroundService>();

IHost host = builder.Build();
host.Run();