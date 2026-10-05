using Microsoft.Extensions.Options;
using MaksIT.Core.Extensions;
using MaksIT.UScheduler.Shared;


namespace MaksIT.UScheduler.BackgroundServices;

public class ConfigurationReloadBackgroundService : BackgroundService {
  private readonly IOptionsMonitor<Configuration> _configMonitor;
  private readonly ILogger<ConfigurationReloadBackgroundService> _logger;

  public ConfigurationReloadBackgroundService(
    IOptionsMonitor<Configuration> configMonitor,
    ILogger<ConfigurationReloadBackgroundService> logger
  ) {
    _configMonitor = configMonitor;
    _logger = logger;

    _configMonitor.OnChange(OnConfigChanged);
  }

  private void OnConfigChanged(Configuration newConfig) {
    _logger.LogInformation("Detected configuration change");
    var configJson = newConfig.ToJson();
    _logger.LogInformation("New configuration: {ConfigJson}", configJson);
  }

  protected override Task ExecuteAsync(CancellationToken stoppingToken) {
    // No background loop needed for this example
    return Task.CompletedTask;
  }
}
