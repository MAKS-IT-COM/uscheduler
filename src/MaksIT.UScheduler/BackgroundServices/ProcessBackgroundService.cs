using Microsoft.Extensions.Options;
using MaksIT.UScheduler.Shared;
using MaksIT.UScheduler.Services;


namespace MaksIT.UScheduler.BackgroundServices;

/// <summary>
/// Background service that manages the execution of configured external processes.
/// Continuously monitors and launches processes based on the application configuration.
/// </summary>
public sealed class ProcessBackgroundService : BackgroundService {

  private readonly ILogger<ProcessBackgroundService> _logger;
  private readonly IOptionsMonitor<Configuration> _optionsMonitor;
  private readonly IProcessService _processService;

  /// <summary>
  /// Initializes a new instance of the <see cref="ProcessBackgroundService"/> class.
  /// </summary>
  /// <param name="logger">The logger instance for this service.</param>
  /// <param name="options">The configuration options containing process definitions.</param>
  /// <param name="processService">The process service for executing processes.</param>
  public ProcessBackgroundService(
    ILogger<ProcessBackgroundService> logger,
    IOptionsMonitor<Configuration> optionsMonitor,
    IProcessService processService
  ) {
    _logger = logger;
    _optionsMonitor = optionsMonitor;
    _processService = processService;
  }

  /// <summary>
  /// Executes the background service, continuously launching configured processes in parallel.
  /// Processes are checked and launched every 10 seconds.
  /// </summary>
  /// <param name="stoppingToken">Cancellation token that signals when the service should stop.</param>
  /// <returns>A task representing the background operation.</returns>
  protected override async Task ExecuteAsync(CancellationToken stoppingToken) {
    _logger.LogInformation("Starting ProcessBackgroundService");

    try {
      while (!stoppingToken.IsCancellationRequested) {
        // Always get the latest configuration
        var processes = _optionsMonitor.CurrentValue.Processes;

        _logger.LogInformation("Checking for processes to run");

        // Launch all enabled processes in parallel
        var processTasks = processes
          .Where(process => !process.Disabled && !string.IsNullOrEmpty(process.Path) && HostPlatforms.IsCompatible(process.Platforms))
          .Select(process => {
            var argsString = process.Args != null ? string.Join(", ", process.Args) : "";
            _logger.LogInformation($"Launching process {process.Path} with arguments {argsString}");
            return _processService.RunProcessAsync(process.Path, process.Args, stoppingToken);
          })
          .ToList();

        if (processTasks.Count > 0) {
          _logger.LogInformation($"Waiting for {processTasks.Count} process(es) to complete");
          await Task.WhenAll(processTasks);
          _logger.LogInformation("All processes completed");
        }

        await Task.Delay(TimeSpan.FromSeconds(10), stoppingToken);
      }
    }
    catch (OperationCanceledException) {
      // When the stopping token is canceled, for example, a call made from services.msc,
      // we shouldn't exit with a non-zero exit code. In other words, this is expected...
      _logger.LogInformation("Stopping ProcessBackgroundService due to cancellation request");
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
  /// Stops the background service and terminates all running processes.
  /// </summary>
  /// <param name="stoppingToken">Cancellation token for the stop operation.</param>
  /// <returns>A task representing the stop operation.</returns>
  public override Task StopAsync(CancellationToken stoppingToken) {
    // Perform cleanup tasks here
    _logger.LogInformation("Stopping ProcessBackgroundService");

    _processService.TerminateAllProcesses();

    _logger.LogInformation("All processes terminated");

    return base.StopAsync(stoppingToken);
  }
}
