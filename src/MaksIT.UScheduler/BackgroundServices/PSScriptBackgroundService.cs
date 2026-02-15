using Microsoft.Extensions.Options;
using MaksIT.UScheduler.Services;
using MaksIT.UScheduler.Shared;


namespace MaksIT.UScheduler.BackgroundServices;

/// <summary>
/// Background service that manages the execution of configured PowerShell scripts.
/// Continuously monitors and launches scripts based on the application configuration.
/// </summary>
public sealed class PSScriptBackgroundService : BackgroundService {

  private readonly ILogger<PSScriptBackgroundService> _logger;
  IOptionsMonitor<Configuration> _optionsMonitor;
  private readonly IPSScriptService _psScriptService;

  /// <summary>
  /// Initializes a new instance of the <see cref="PSScriptBackgroundService"/> class.
  /// </summary>
  /// <param name="logger">The logger instance for this service.</param>
  /// <param name="options">The configuration options containing PowerShell script definitions.</param>
  /// <param name="psScriptService">The PowerShell script service for executing scripts.</param>
  public PSScriptBackgroundService(
    ILogger<PSScriptBackgroundService> logger,
    IOptionsMonitor<Configuration> optionsMonitor,
    IPSScriptService psScriptService
  ) {
    _logger = logger;
    _optionsMonitor = optionsMonitor;
    _psScriptService = psScriptService;
  }

  /// <summary>
  /// Executes the background service, continuously launching configured PowerShell scripts in parallel.
  /// Scripts are checked and launched every 10 seconds.
  /// </summary>
  /// <param name="stoppingToken">Cancellation token that signals when the service should stop.</param>
  /// <returns>A task representing the background operation.</returns>
  protected override async Task ExecuteAsync(CancellationToken stoppingToken) {
    _logger.LogInformation("Starting PSScriptBackgroundService");

    try {
      while (!stoppingToken.IsCancellationRequested) {
        // Always get the latest configuration
        var psScripts = _optionsMonitor.CurrentValue.Powershell;

        _logger.LogInformation("Checking for PowerShell scripts to run");

        // Launch all enabled scripts in parallel
        var scriptTasks = psScripts
          .Where(psScript => !psScript.Disabled && !string.IsNullOrEmpty(psScript.Path))
          .Select(psScript => {
            _logger.LogInformation($"Launching PowerShell script {psScript.Path}");
            return _psScriptService.RunScriptAsync(psScript.Path, psScript.IsSigned, stoppingToken);
          })
          .ToList();

        if (scriptTasks.Count > 0) {
          _logger.LogInformation($"Waiting for {scriptTasks.Count} PowerShell script(s) to complete");
          await Task.WhenAll(scriptTasks);
          _logger.LogInformation("All PowerShell scripts completed");
        }

        await Task.Delay(TimeSpan.FromSeconds(10), stoppingToken);
      }
    }
    catch (OperationCanceledException) {
      // When the stopping token is canceled, for example, a call made from services.msc,
      // we shouldn't exit with a non-zero exit code. In other words, this is expected...
      _logger.LogInformation("Stopping PSScriptBackgroundService due to cancellation request");
    }
    catch (Exception ex) {
      _logger.LogError(ex, "{Message}", ex.Message);

      // Terminates this process and returns an exit code to the operating system.
      // This is required to avoid the 'BackgroundServiceExceptionBehavior', which
      // performs one of two scenarios:
      // 1. When set to "Ignore": will do nothing at all, errors cause zombie services.
      // 2. When set to "StopHost": will cleanly stop the host, and log errors.
      //
      // In order for the Windows Service Management system to leverage configured
      // recovery options, we need to terminate the process with a non-zero exit code.
      Environment.Exit(1);
    }
  }


  /// <summary>
  /// Stops the background service and terminates all running PowerShell scripts.
  /// </summary>
  /// <param name="stoppingToken">Cancellation token for the stop operation.</param>
  /// <returns>A task representing the stop operation.</returns>
  public override Task StopAsync(CancellationToken stoppingToken) {
    // Perform cleanup tasks here
    _logger.LogInformation("Stopping PSScriptBackgroundService");

    _psScriptService.TerminateAllScripts();

    _logger.LogInformation("PSScriptBackgroundService stopped");

    return base.StopAsync(stoppingToken);
  }
}
