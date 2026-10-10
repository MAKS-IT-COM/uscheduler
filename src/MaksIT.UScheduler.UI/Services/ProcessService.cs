using System.Diagnostics;
using System.Collections.Concurrent;
using MaksIT.UScheduler.Shared;
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
  private readonly IProcessStatusStore? _status;
  private readonly ConcurrentDictionary<int, Process> _runningProcesses = new();
  private readonly ConcurrentDictionary<string, byte> _activePaths = new(PathComparer);

  private static StringComparer PathComparer =>
    OperatingSystem.IsWindows() ? StringComparer.OrdinalIgnoreCase : StringComparer.Ordinal;

  /// <summary>
  /// Initializes a new instance of the <see cref="ProcessService"/> class.
  /// </summary>
  /// <param name="logger">The logger instance for this service.</param>
  /// <param name="loggerFactory">The logger factory for creating process-specific loggers.</param>
  public ProcessService(
    ILogger<ProcessService> logger,
    ILoggerFactory loggerFactory,
    IProcessStatusStore? status = null
  ) {
    _logger = logger;
    _loggerFactory = loggerFactory;
    _status = status;
  }

  private static readonly TimeSpan MaxThrottle = TimeSpan.FromMinutes(1);

  /// <summary>
  /// Starts and monitors an external process asynchronously.
  /// Holds the path until supervision stops so the same executable is not started twice.
  /// When <paramref name="supervision"/> keeps it running, any exit starts it again.
  /// </summary>
  /// <param name="processPath">The path to the executable to run.</param>
  /// <param name="args">Optional command-line arguments to pass to the process.</param>
  /// <param name="supervision">Restart and throttle settings.</param>
  /// <param name="stoppingToken">Cancellation token to signal when the process should stop.</param>
  /// <returns>A task representing the asynchronous operation.</returns>
  public async Task<ProcessRunResult> RunProcessAsync(
    string processPath,
    string[]? args,
    ProcessSupervision supervision,
    CancellationToken stoppingToken
  ) {
    var resolvedPath = PathHelper.ResolvePath(processPath);
    var processLogger = _loggerFactory.CreateFolderLogger(resolvedPath);

    if (!_activePaths.TryAdd(resolvedPath, 0)) {
      processLogger.LogInformation($"Process {resolvedPath} is already running");
      return new ProcessRunResult(false, null, false);
    }

    var streak = 0;
    var restarts = 0;
    int? lastExit = null;
    DateTimeOffset? startedUtc = null;

    try {
      while (!stoppingToken.IsCancellationRequested) {
        var started = Stopwatch.GetTimestamp();
        int exitCode;
        try {
          (exitCode, startedUtc) = await RunOnceAsync(
            resolvedPath,
            args,
            supervision.WorkingDirectory,
            processLogger,
            restarts,
            lastExit,
            stoppingToken);
        }
        catch (OperationCanceledException) {
          processLogger.LogInformation($"Process {resolvedPath} was canceled");
          Publish(resolvedPath, ProcessStates.Stopped, null, lastExit, startedUtc, restarts);
          return new ProcessRunResult(true, null, false);
        }
        catch (Exception ex) {
          processLogger.LogError($"Error running process {resolvedPath}: {ex.Message}");
          if (!supervision.KeepRunning) {
            Publish(resolvedPath, ProcessStates.Stopped, null, lastExit, startedUtc, restarts);
            return new ProcessRunResult(true, null, true);
          }

          restarts++;
          Publish(resolvedPath, ProcessStates.Restarting, null, lastExit, startedUtc, restarts);
          streak = await DelayBeforeRestart(supervision, TimeSpan.Zero, streak, processLogger, resolvedPath, stoppingToken);
          continue;
        }

        lastExit = exitCode;

        if (!supervision.KeepRunning) {
          processLogger.LogInformation($"Process {resolvedPath} exited with code {exitCode}");
          Publish(resolvedPath, ProcessStates.Stopped, null, exitCode, startedUtc, restarts);
          return new ProcessRunResult(true, exitCode, true);
        }

        var uptime = Stopwatch.GetElapsedTime(started);
        restarts++;
        processLogger.LogWarning($"Process {resolvedPath} exited with code {exitCode}, restarting...");
        Publish(resolvedPath, ProcessStates.Restarting, null, exitCode, startedUtc, restarts);
        streak = await DelayBeforeRestart(supervision, uptime, streak, processLogger, resolvedPath, stoppingToken);
      }

      Publish(resolvedPath, ProcessStates.Stopped, null, lastExit, startedUtc, restarts);
      return new ProcessRunResult(true, null, false);
    }
    catch (OperationCanceledException) {
      processLogger.LogInformation($"Process {resolvedPath} was canceled");
      Publish(resolvedPath, ProcessStates.Stopped, null, lastExit, startedUtc, restarts);
      return new ProcessRunResult(true, null, false);
    }
    finally {
      _activePaths.TryRemove(resolvedPath, out _);
    }
  }

  /// <summary>
  /// Gets the dictionary of currently running processes.
  /// </summary>
  /// <returns>A concurrent dictionary mapping process IDs to their Process objects.</returns>
  public ConcurrentDictionary<int, Process> GetRunningProcesses() => _runningProcesses;

  /// <summary>
  /// Kills a running process by its ID. The run loop disposes the process object.
  /// </summary>
  /// <param name="processId">The ID of the process to terminate.</param>
  public void TerminateProcessById(int processId) {
    if (!_runningProcesses.TryGetValue(processId, out var processToTerminate))
      return;

    try {
      if (!processToTerminate.HasExited)
        processToTerminate.Kill(entireProcessTree: true);
    }
    catch (Exception ex) {
      _logger.LogError($"Error terminating process {processId}: {ex.Message}");
    }
  }

  /// <summary>
  /// Terminates all currently running processes managed by this service.
  /// </summary>
  public void TerminateAllProcesses() {
    _logger.LogInformation("Terminating all running processes");

    foreach (var processId in _runningProcesses.Keys.ToList())
      TerminateProcessById(processId);
  }

  private static async Task<int> DelayBeforeRestart(
    ProcessSupervision supervision,
    TimeSpan uptime,
    int streak,
    ILogger processLogger,
    string resolvedPath,
    CancellationToken stoppingToken
  ) {
    var wait = supervision.RestartDelay;
    if (supervision.Throttle > TimeSpan.Zero && uptime < supervision.Throttle) {
      streak++;
      var throttledMs = Math.Min(supervision.Throttle.TotalMilliseconds * streak, MaxThrottle.TotalMilliseconds);
      var throttled = TimeSpan.FromMilliseconds(throttledMs);
      if (throttled > wait)
        wait = throttled;

      processLogger.LogWarning($"Process {resolvedPath} exited after {uptime.TotalMilliseconds:0} ms. Next start waits {wait.TotalMilliseconds:0} ms.");
    }
    else {
      streak = 0;
    }

    if (wait > TimeSpan.Zero)
      await Task.Delay(wait, stoppingToken);

    return streak;
  }

  private void Publish(
    string path,
    string state,
    int? processId,
    int? lastExitCode,
    DateTimeOffset? startedUtc,
    int restarts) {
    _status?.Upsert(new ProcessStatusEntry {
      Path = path,
      State = state,
      ProcessId = processId,
      LastExitCode = lastExitCode,
      StartedUtc = startedUtc,
      Restarts = restarts
    });
  }

  private async Task<(int ExitCode, DateTimeOffset StartedUtc)> RunOnceAsync(
    string resolvedPath,
    string[]? args,
    string? workingDirectory,
    ILogger processLogger,
    int restarts,
    int? lastExitCode,
    CancellationToken stoppingToken
  ) {
    var process = new Process();
    var started = false;
    var argsString = args != null ? string.Join(", ", args) : "";
    processLogger.LogInformation($"Starting process {resolvedPath} with arguments {argsString}");

    try {
      process.StartInfo = new ProcessStartInfo {
        FileName = resolvedPath,
        UseShellExecute = false,
        RedirectStandardOutput = true,
        RedirectStandardError = true,
        CreateNoWindow = true
      };

      var directory = string.IsNullOrWhiteSpace(workingDirectory)
        ? Path.GetDirectoryName(resolvedPath)
        : workingDirectory;
      if (!string.IsNullOrEmpty(directory))
        process.StartInfo.WorkingDirectory = directory;

      if (args != null) {
        foreach (var arg in args)
          process.StartInfo.ArgumentList.Add(arg);
      }

      process.OutputDataReceived += (_, e) => {
        if (!string.IsNullOrEmpty(e.Data))
          processLogger.LogInformation($"[Output] {e.Data}");
      };
      process.ErrorDataReceived += (_, e) => {
        if (!string.IsNullOrEmpty(e.Data))
          processLogger.LogError($"[Error] {e.Data}");
      };

      if (!process.Start())
        throw new InvalidOperationException($"Failed to start process {resolvedPath}");

      started = true;
      _runningProcesses.TryAdd(process.Id, process);
      var startedUtc = DateTimeOffset.UtcNow;
      processLogger.LogInformation($"Process {resolvedPath} started with ID {process.Id}");
      Publish(resolvedPath, ProcessStates.Running, process.Id, lastExitCode, startedUtc, restarts);
      process.BeginOutputReadLine();
      process.BeginErrorReadLine();
      await process.WaitForExitAsync(stoppingToken);
      return (process.ExitCode, startedUtc);
    }
    catch (OperationCanceledException) {
      Kill(process, started);
      throw;
    }
    finally {
      if (started) {
        _runningProcesses.TryRemove(process.Id, out _);
        try {
          process.CancelOutputRead();
        }
        catch (InvalidOperationException) {
        }

        try {
          process.CancelErrorRead();
        }
        catch (InvalidOperationException) {
        }
      }

      process.Dispose();
    }
  }

  private void Kill(Process process, bool started) {
    if (!started)
      return;

    try {
      if (!process.HasExited)
        process.Kill(entireProcessTree: true);
    }
    catch (Exception ex) {
      _logger.LogError($"Error terminating process {process.Id}: {ex.Message}");
    }
  }
}
