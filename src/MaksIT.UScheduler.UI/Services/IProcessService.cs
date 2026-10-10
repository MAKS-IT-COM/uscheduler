using System.Diagnostics;
using System.Collections.Concurrent;
using MaksIT.UScheduler.Shared;
using MaksIT.UScheduler.Shared.Helpers;


namespace MaksIT.UScheduler.Services;

/// <summary>
/// How a configured program is kept running.
/// </summary>
/// <param name="KeepRunning">Restart after any exit. False leaves it stopped.</param>
/// <param name="RestartDelay">Wait after a run that lasted at least <paramref name="Throttle"/>.</param>
/// <param name="Throttle">A shorter run waits at least this long, and longer if it keeps exiting immediately.</param>
/// <param name="WorkingDirectory">Empty uses the executable's directory.</param>
public readonly record struct ProcessSupervision(
  bool KeepRunning,
  TimeSpan RestartDelay,
  TimeSpan Throttle,
  string? WorkingDirectory) {

  public static ProcessSupervision For(ProcessConfiguration process) {
    string? directory = null;
    if (!string.IsNullOrWhiteSpace(process.Directory))
      directory = PathHelper.ResolvePath(process.Directory);

    return new ProcessSupervision(
      process.RestartOnFailure,
      TimeSpan.FromMilliseconds(Math.Max(0, process.RestartDelayMs)),
      TimeSpan.FromMilliseconds(Math.Max(0, process.ThrottleMs)),
      directory);
  }
}

/// <summary>
/// Result of one supervised process run.
/// </summary>
/// <param name="Started">False when that executable was already running.</param>
/// <param name="ExitCode">Process exit code, when the run finished.</param>
/// <param name="StayDown">True when the program must not be started again.</param>
public readonly record struct ProcessRunResult(bool Started, int? ExitCode, bool StayDown);

/// <summary>
/// Interface for managing and executing external processes.
/// </summary>
public interface IProcessService {
  /// <summary>
  /// Starts and monitors an external process asynchronously.
  /// A process that is already running is left alone.
  /// When <paramref name="supervision"/> keeps it running, any exit starts it again.
  /// </summary>
  /// <param name="processPath">The path to the executable to run.</param>
  /// <param name="args">Optional command-line arguments to pass to the process.</param>
  /// <param name="supervision">Restart and throttle settings.</param>
  /// <param name="stoppingToken">Cancellation token to signal when the process should stop.</param>
  /// <returns>A task representing the asynchronous operation.</returns>
  Task<ProcessRunResult> RunProcessAsync(
    string processPath,
    string[]? args,
    ProcessSupervision supervision,
    CancellationToken stoppingToken);

  /// <summary>
  /// Gets the dictionary of currently running processes.
  /// </summary>
  /// <returns>A concurrent dictionary mapping process IDs to their Process objects.</returns>
  ConcurrentDictionary<int, Process> GetRunningProcesses();

  /// <summary>
  /// Terminates a running process by its ID.
  /// </summary>
  /// <param name="processId">The ID of the process to terminate.</param>
  void TerminateProcessById(int processId);

  /// <summary>
  /// Terminates all currently running processes managed by this service.
  /// </summary>
  void TerminateAllProcesses();
}
