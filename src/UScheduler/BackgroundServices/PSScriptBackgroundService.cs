using Microsoft.Extensions.Options;
using UScheduler.Services;

namespace UScheduler.BackgroundServices {

  public sealed class PSScriptBackgroundService : BackgroundService {

    private readonly ILogger<PSScriptBackgroundService> _logger;
    private readonly Configuration _configuration;
    private readonly PSScriptService _psScriptService;

    public PSScriptBackgroundService(
      ILogger<PSScriptBackgroundService> logger,
      IOptions<Configuration> options,
      PSScriptService psScriptService
    ) {
      _logger = logger;
      _configuration = options.Value;
      _psScriptService = psScriptService;
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken) {
      _logger.LogInformation("Starting PSScriptBackgroundService");

      try {
        var psScripts = _configuration.PowershellOrDefault;

        while (!stoppingToken.IsCancellationRequested) {
          _logger.LogInformation("Checking for PowerShell scripts to run");

          //stop background service if there are no PowerShell scripts to run
          if (psScripts.Count == 0) {
            _logger.LogWarning("No PowerShell scripts to run, stopping PSScriptBackgroundService");
            break;
          }

          foreach (var psScript in psScripts) {
            var scriptPath = psScript.GetPathOrDefault;

            if (scriptPath == string.Empty)
              continue;

            _logger.LogInformation($"Running PowerShell script {scriptPath}");
            _psScriptService.RunScript(scriptPath, psScript.GetIsSignedOrDefault, stoppingToken);
          }

          await Task.Delay(TimeSpan.FromSeconds(10), stoppingToken);
        }
      }
      catch (OperationCanceledException) {
        // When the stopping token is canceled, for example, a call made from services.msc,
        // we shouldn't exit with a non-zero exit code. In other words, this is expected...
        _logger.LogInformation("Stopping PSScriptBackgroundService due to cancellation request");
        _psScriptService.TerminateAllScripts();
      }
      catch (Exception ex) {
        _logger.LogError(ex, "{Message}", ex.Message);

        _psScriptService.TerminateAllScripts();

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
      _logger.LogInformation("Stopping PSScriptBackgroundService");

      _psScriptService.TerminateAllScripts();

      _logger.LogInformation("PSScriptBackgroundService stopped");

      return Task.CompletedTask;
    }
  }
}
