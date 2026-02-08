using System.Diagnostics;
using System.Collections.Concurrent;
using MaksIT.UScheduler.Shared.Helpers;
using MaksIT.UScheduler.Shared.Extensions;


namespace MaksIT.UScheduler.Services;

/// <summary>
/// Service responsible for managing and executing external processes.
/// Tracks running processes and provides methods for starting, monitoring, and terminating them.
/// </summary>
public sealed class ProcessService : IProcessService {

  private readonly ILogger _logger;
  private readonly ILoggerFactory _loggerFactory;
  private readonly ConcurrentDictionary<int, Process> _runningProcesses = new();

  /// <summary>
  /// Initializes a new instance of the <see cref="ProcessService"/> class.
  /// </summary>
  /// <param name="logger">The logger instance for this service.</param>
  /// <param name="loggerFactory">The logger factory for creating process-specific loggers.</param>
  public ProcessService(
    ILogger<ProcessService> logger,
    ILoggerFactory loggerFactory
  ) {
    _logger = logger;
    _loggerFactory = loggerFactory;
  }

  /// <summary>
  /// Starts and monitors an external process asynchronously.
  /// If the process exits with a non-zero code, it will be automatically restarted.
  /// </summary>
  /// <param name="processPath">The path to the executable to run.</param>
  /// <param name="args">Optional command-line arguments to pass to the process.</param>
  /// <param name="stoppingToken">Cancellation token to signal when the process should stop.</param>
  /// <returns>A task representing the asynchronous operation.</returns>
  public async Task RunProcessAsync(string processPath, string[]? args, CancellationToken stoppingToken) {
    // Resolve relative paths against application base directory
    var resolvedPath = PathHelper.ResolvePath(processPath);
    var processLogger = _loggerFactory.CreateFolderLogger(resolvedPath);
    var argsString = args != null ? string.Join(", ", args) : "";

    processLogger.LogInformation($"Starting process {resolvedPath} with arguments {argsString}");

    Process? process = null;

    try {
      if (GetRunningProcesses().Any(x => x.Value.StartInfo.FileName == resolvedPath)) {
        processLogger.LogInformation($"Process {resolvedPath} is already running");
        return;
      }

      process = new Process();

      process.StartInfo = new ProcessStartInfo {
        FileName = resolvedPath,
        WorkingDirectory = Path.GetDirectoryName(resolvedPath),
        UseShellExecute = false,
        RedirectStandardOutput = true,
        RedirectStandardError = true
      };

      if (args != null) {
        foreach (var arg in args)
          process.StartInfo.ArgumentList.Add(arg);
      }

      process.Start();
      _runningProcesses.TryAdd(process.Id, process);

      processLogger.LogInformation($"Process {resolvedPath} started with ID {process.Id}");

      await process.WaitForExitAsync();

      if (process.ExitCode != 0 && !stoppingToken.IsCancellationRequested) {
        processLogger.LogWarning($"Process {resolvedPath} exited with code {process.ExitCode}, restarting...");
        await RunProcessAsync(resolvedPath, args, stoppingToken);
      }
      else {
        processLogger.LogInformation($"Process {resolvedPath} completed successfully with exit code {process.ExitCode}");
      }
    }
    catch (OperationCanceledException) {
      // When the stopping token is canceled, for example, a call made from services.msc,
      // we shouldn't exit with a non-zero exit code. In other words, this is expected...
      processLogger.LogInformation($"Process {resolvedPath} was canceled");
    }
    catch (Exception ex) {
      processLogger.LogError($"Error running process {resolvedPath}: {ex.Message}");
    }
    finally {
      if (process != null && _runningProcesses.ContainsKey(process.Id)) {
        TerminateProcessById(process.Id);
        processLogger.LogInformation($"Process {resolvedPath} with ID {process.Id} removed from running processes");
      }
    }
  }

  /// <summary>
  /// Gets the dictionary of currently running processes.
  /// </summary>
  /// <returns>A concurrent dictionary mapping process IDs to their Process objects.</returns>
  public ConcurrentDictionary<int, Process> GetRunningProcesses() {
    return _runningProcesses;
  }

  /// <summary>
  /// Terminates a running process by its ID.
  /// Recursively attempts to kill the process until it has exited.
  /// </summary>
  /// <param name="processId">The ID of the process to terminate.</param>
  public void TerminateProcessById(int processId) {
    // Check if the process is in the running processes list
    if (!_runningProcesses.TryGetValue(processId, out var processToTerminate)) {
      return;
    }

    // Kill the process
    try {
      processToTerminate.Kill(true);
    }
    catch (Exception ex) {
      _logger.LogError($"Error terminating process {processId}: {ex.Message}");
    }

    // Check if the process has exited
    if (!processToTerminate.HasExited) {
      TerminateProcessById(processId);
    }
  }

  /// <summary>
  /// Terminates all currently running processes managed by this service.
  /// </summary>
  public void TerminateAllProcesses() {
    _logger.LogInformation("Terminating all running processes");

    foreach (var processId in _runningProcesses.Keys.ToList()) {
      TerminateProcessById(processId);
    }
  }
}
