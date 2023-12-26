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
        process = new Process();
        process.StartInfo.FileName = processPath;
        process.StartInfo.UseShellExecute = false;
        process.StartInfo.RedirectStandardOutput = true;
        process.StartInfo.RedirectStandardError = true;

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
        _logger.LogInformation($"Process {processPath} was cancelled");
      }
      catch (Exception ex) {
        _logger.LogError($"Error running process {processPath}: {ex.Message}");
      }
      finally {
        if (process != null && _runningProcesses.ContainsKey(process.Id)) {
          _runningProcesses.TryRemove(process.Id, out _);
          _logger.LogInformation($"Process {processPath} with ID {process.Id} removed from running processes");
        }
      }
    }

    public ConcurrentDictionary<int, Process> GetRunningProcesses() {
      _logger.LogInformation($"Retrieving running processes. Current count: {_runningProcesses.Count}");
      return _runningProcesses;
    }

    public void TerminateProcessById(int processId) {
      if (_runningProcesses.TryRemove(processId, out var process)) {
        _logger.LogInformation($"Terminating process with ID {processId}");
        process.Kill();
        _logger.LogInformation($"Process with ID {processId} terminated");
      }
      else {
        _logger.LogWarning($"Failed to terminate process with ID {processId}. Process not found.");
      }
    }

    public void TerminateAllProcesses() {
      foreach (var process in _runningProcesses) {
        TerminateProcessById(process.Key);
      }
    }
  }
}
