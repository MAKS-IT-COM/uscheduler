namespace MaksIT.UScheduler.Services;

/// <summary>
/// Interface for executing and managing PowerShell scripts.
/// </summary>
public interface IPSScriptService : IDisposable {
  /// <summary>
  /// Executes a PowerShell script asynchronously with optional signature verification.
  /// </summary>
  /// <param name="scriptPath">The path to the PowerShell script to execute.</param>
  /// <param name="signed">If true, validates the script's Authenticode signature before execution.</param>
  /// <param name="stoppingToken">Cancellation token to signal when script execution should stop.</param>
  /// <returns>A task representing the asynchronous operation.</returns>
  Task RunScriptAsync(string scriptPath, bool signed, CancellationToken stoppingToken);

  /// <summary>
  /// Gets a list of script paths that are currently being executed.
  /// </summary>
  /// <returns>A list of script paths currently running.</returns>
  List<string> GetRunningScriptTasks();

  /// <summary>
  /// Terminates a running PowerShell script by its path.
  /// </summary>
  /// <param name="scriptPath">The path of the script to terminate.</param>
  void TerminateScript(string scriptPath);

  /// <summary>
  /// Terminates all currently running PowerShell scripts.
  /// </summary>
  void TerminateAllScripts();
}
