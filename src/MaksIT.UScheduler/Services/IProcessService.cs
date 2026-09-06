using System.Diagnostics;
using System.Collections.Concurrent;


namespace MaksIT.UScheduler.Services;

/// <summary>
/// Interface for managing and executing external processes.
/// </summary>
public interface IProcessService {
  /// <summary>
  /// Starts and monitors an external process asynchronously.
  /// </summary>
  /// <param name="processPath">The path to the executable to run.</param>
  /// <param name="args">Optional command-line arguments to pass to the process.</param>
  /// <param name="stoppingToken">Cancellation token to signal when the process should stop.</param>
  /// <returns>A task representing the asynchronous operation.</returns>
  Task RunProcessAsync(string processPath, string[]? args, CancellationToken stoppingToken);

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
