using System.Diagnostics;
using System.Collections.Concurrent;

namespace UScheduler.Services {
  public sealed class ProcessService {
    private readonly ILogger<ProcessService> _logger;
    private readonly ConcurrentDictionary<int, Process> _runningProcesses = new();

    public ProcessService(ILogger<ProcessService> logger) {
      _logger = logger;
    }

    public async Task RunProcess(string processPath, string[] args, CancellationToken stoppingToken) {
      _logger.LogInformation($"Starting process {processPath} with arguments {string.Join(", ", args)}");

      Process? process = null;

      try {
        if (GetRunningProcesses().Any(x => x.Value.StartInfo.FileName == processPath)) {
          _logger.LogInformation($"Process {processPath} is already running");
          return;
        }

        process = new Process();

        process.StartInfo = new ProcessStartInfo {
          FileName = processPath,
          WorkingDirectory = Path.GetDirectoryName(processPath),
          UseShellExecute = false,
          RedirectStandardOutput = true,
          RedirectStandardError = true
        };

        foreach (var arg in args)
          process.StartInfo.ArgumentList.Add(arg);

        process.Start();
        _runningProcesses.TryAdd(process.Id, process);

        _logger.LogInformation($"Process {processPath} started with ID {process.Id}");

        await process.WaitForExitAsync();

        if (process.ExitCode != 0 && !stoppingToken.IsCancellationRequested) {
          _logger.LogWarning($"Process {processPath} exited with code {process.ExitCode}");
          await RunProcess(processPath, args, stoppingToken);
        }
        else {
          _logger.LogInformation($"Process {processPath} completed successfully");
        }
      }
      catch (OperationCanceledException) {
        // When the stopping token is canceled, for example, a call made from services.msc,
        // we shouldn't exit with a non-zero exit code. In other words, this is expected...
        _logger.LogWarning($"Process {processPath} was canceled");
      }
      catch (Exception ex) {
        _logger.LogError($"Error running process {processPath}: {ex.Message}");
      }
      finally {
        if (process != null && _runningProcesses.ContainsKey(process.Id)) {
          TerminateProcessById(process.Id);

          _logger.LogInformation($"Process {processPath} with ID {process.Id} removed from running processes");
        }
      }
    }

    public ConcurrentDictionary<int, Process> GetRunningProcesses() {
      _logger.LogInformation($"Retrieving running processes. Current count: {_runningProcesses.Count}");
      return _runningProcesses;
    }

    public void TerminateProcessById(int processId) {
      // Check if the process is in the running processes list
      if (!_runningProcesses.TryGetValue(processId, out var processToTerminate)) {
        _logger.LogWarning($"Failed to terminate process {processId}. Process not found.");
        return;
      }

      // Kill the process
      try {
        processToTerminate.Kill(true);
        _logger.LogInformation($"Process {processId} terminated");
      }
      catch (Exception ex) {
        _logger.LogError($"Error terminating process {processId}: {ex.Message}");
      }

      // Check if the process has exited
      if (!processToTerminate.HasExited) {
        _logger.LogWarning($"Failed to terminate process {processId}. Process still running.");
        TerminateProcessById(processId);
      }
    }


    public void TerminateAllProcesses() {
      foreach (var process in _runningProcesses) {
        TerminateProcessById(process.Key);
      }
    }
  }
}
