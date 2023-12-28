using Microsoft.Extensions.Options;
using System.Text.Json;
using UScheduler.Services;

namespace UScheduler.BackgroundServices;

public sealed class ProcessBackgroundService : BackgroundService {

  private readonly ILogger<ProcessBackgroundService> _logger;
  private readonly Configuration _configuration;
  private readonly ProcessService _processService;

  public ProcessBackgroundService(
    ILogger<ProcessBackgroundService> logger,
    IOptions<Configuration> options,
    ProcessService processService
  ) {
    _logger = logger;
    _configuration = options.Value;
    _processService = processService;
  }

  protected override async Task ExecuteAsync(CancellationToken stoppingToken) {
    _logger.LogInformation("Starting ProcessBackgroundService");

    try {
      var processes = _configuration.ProcessesOrDefault;

      while (!stoppingToken.IsCancellationRequested) {
        _logger.LogInformation("Checking for processes to run");

        //stop background service if there are no processes to run
        if (processes.Count == 0) {
          _logger.LogWarning("No processes to run, stopping ProcessBackgroundService");
          break;
        }

        foreach (var process in processes) {
          var processPath = process.GetPathOrDefault;
          var processArgs = process.GetArgsOrDefault;

          if (processPath == string.Empty)
            continue;

          _logger.LogInformation($"Running process {processPath} with arguments {string.Join(", ", processArgs)}");
          _processService.RunProcess(processPath, processArgs, stoppingToken);

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

  public override Task StopAsync(CancellationToken stoppingToken) {
    // Perform cleanup tasks here
    _logger.LogInformation("Stopping ProcessBackgroundService");

    _processService.TerminateAllProcesses();

    _logger.LogInformation("All processes terminated");

    return Task.CompletedTask;
  }
}
