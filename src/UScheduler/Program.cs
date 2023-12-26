using Microsoft.Extensions.Logging.Configuration;
using Microsoft.Extensions.Logging.EventLog;
using UScheduler;
using UScheduler.BackgroundServices;
using UScheduler.Services;

// read configuration from appsettings.json
var configurationRoot = new ConfigurationBuilder()
  .SetBasePath(Directory.GetCurrentDirectory())
  .AddJsonFile("appsettings.json", optional: true)
  .Build();

// bind Configuration section inside configuration to a new instance of Settings
var configuration = new Configuration();
configurationRoot.GetSection("Configurations").Bind(configuration);
 
HostApplicationBuilder builder = Host.CreateApplicationBuilder(args);
builder.Services.AddWindowsService(options => {
  options.ServiceName = configuration.ServiceNameOrDefault;
});

LoggerProviderOptions.RegisterProviderOptions<
    EventLogSettings, EventLogLoggerProvider>(builder.Services);




// register configuration as IOptions<Configuration>
builder.Services.Configure<Configuration>(configurationRoot.GetSection("Configurations"));

builder.Services.AddSingleton<ProcessService>();
builder.Services.AddHostedService<ProcessBackgroundService>();

builder.Services.AddSingleton<PSScriptService>();
builder.Services.AddHostedService<PSScriptBackgroundService>();

IHost host = builder.Build();
host.Run();