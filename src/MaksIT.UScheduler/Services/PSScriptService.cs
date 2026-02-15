using System.Collections.Concurrent;
using System.Management.Automation;
using System.Management.Automation.Runspaces;
using MaksIT.UScheduler.Shared.Helpers;
using MaksIT.UScheduler.Shared.Extensions;


namespace MaksIT.UScheduler.Services;

/// <summary>
/// Service responsible for executing and managing PowerShell scripts.
/// Provides parallel script execution using a RunspacePool and supports
/// signature verification for signed scripts.
/// </summary>
public sealed class PSScriptService : IPSScriptService {

  private readonly ILogger<PSScriptService> _logger;
  private readonly ILoggerFactory _loggerFactory;
  private readonly ConcurrentDictionary<string, PowerShell> _runningScripts = new();
  private readonly RunspacePool _runspacePool;
  private bool _disposed;

  /// <summary>
  /// Initializes a new instance of the <see cref="PSScriptService"/> class.
  /// Creates a RunspacePool for parallel script execution.
  /// </summary>
  /// <param name="logger">The logger instance for this service.</param>
  /// <param name="loggerFactory">The logger factory for creating script-specific loggers.</param>
  public PSScriptService(
    ILogger<PSScriptService> logger,
    ILoggerFactory loggerFactory
  ) {
    _logger = logger;
    _loggerFactory = loggerFactory;

    // Create a RunspacePool to allow parallel script execution
    _runspacePool = RunspaceFactory.CreateRunspacePool(1, Environment.ProcessorCount);
    _runspacePool.Open();
    _logger.LogInformation($"RunspacePool opened with max {Environment.ProcessorCount} runspaces");
  }

  /// <summary>
  /// Executes a PowerShell script asynchronously with optional signature verification.
  /// Automatically passes Automated and CurrentDateTimeUtc parameters to the script.
  /// </summary>
  /// <param name="scriptPath">The path to the PowerShell script to execute.</param>
  /// <param name="signed">If true, validates the script's Authenticode signature before execution.</param>
  /// <param name="stoppingToken">Cancellation token to signal when script execution should stop.</param>
  /// <returns>A task representing the asynchronous operation.</returns>
  public async Task RunScriptAsync(string scriptPath, bool signed, CancellationToken stoppingToken) {
    // Resolve relative paths against application base directory
    var resolvedPath = PathHelper.ResolvePath(scriptPath);
    
    _logger.LogInformation($"Preparing to run script {resolvedPath}");

    if (GetRunningScriptTasks().Contains(resolvedPath)) {
      _logger.LogInformation($"PowerShell script {resolvedPath} is already running");
      return;
    }

    if (!File.Exists(resolvedPath)) {
      _logger.LogError($"Script file {resolvedPath} does not exist");
      return;
    }

    if (!TryUnblockScript(resolvedPath)) {
      _logger.LogError($"Script {resolvedPath} could not be unblocked. Aborting execution.");
      return;
    }

    var ps = PowerShell.Create();
    ps.RunspacePool = _runspacePool;

    if (!_runningScripts.TryAdd(resolvedPath, ps)) {
      _logger.LogWarning($"Script {resolvedPath} was already added by another thread");
      ps.Dispose();
      return;
    }

    try {
      // Set execution policy
      var scriptPolicy = signed ? "AllSigned" : "Unrestricted";
      ps.AddScript($"Set-ExecutionPolicy -Scope Process -ExecutionPolicy {scriptPolicy}");
      await Task.Factory.FromAsync(ps.BeginInvoke(), ps.EndInvoke);

      if (signed) {
        ps.Commands.Clear();
        ps.AddScript($"Get-AuthenticodeSignature \"{resolvedPath}\"");
        var signatureResults = await Task.Factory.FromAsync(ps.BeginInvoke(), ps.EndInvoke);
        if (signatureResults.Count == 0 || ((Signature)signatureResults[0].BaseObject).Status != SignatureStatus.Valid) {
          _logger.LogWarning($"Script {resolvedPath} signature is invalid. Correct and restart the service.");
          return;
        }
      }

      stoppingToken.ThrowIfCancellationRequested();

      _logger.LogInformation($"Invoking: {resolvedPath}");

      ps.Commands.Clear();
      var myCommand = new Command(resolvedPath);

      var currentDateTimeUtcString = DateTime.UtcNow.ToString("o");
      myCommand.Parameters.Add(new CommandParameter("Automated", true));
      myCommand.Parameters.Add(new CommandParameter("CurrentDateTimeUtc", currentDateTimeUtcString));
      ps.Commands.Commands.Add(myCommand);

      _logger.LogInformation($"Added parameters: Automated=true, CurrentDateTimeUtc={currentDateTimeUtcString}");

      // Execute asynchronously
      var outputResults = await Task.Factory.FromAsync(ps.BeginInvoke(), ps.EndInvoke);

      #region Script Output Logging
      var scriptLogger = _loggerFactory.CreateFolderLogger(resolvedPath);

      // Log standard output
      if (outputResults != null && outputResults.Count > 0) {
        foreach (var outputItem in outputResults) {
          scriptLogger.LogInformation($"[PS Output] {outputItem}");
        }
      }

      // Log errors
      if (ps.Streams.Error.Count > 0) {
        foreach (var errorItem in ps.Streams.Error) {
          scriptLogger.LogError($"[PS Error] {errorItem}");
        }
      }
      #endregion
    }
    catch (OperationCanceledException) {
      _logger.LogInformation($"Stopping script {resolvedPath} due to cancellation request");
    }
    catch (Exception ex) {
      _logger.LogError($"Error running script {resolvedPath}: {ex.Message}");
    }
    finally {
      TerminateScript(resolvedPath);
      _logger.LogInformation($"Script {resolvedPath} completed and removed from running scripts");
    }
  }

  /// <summary>
  /// Attempts to unblock a downloaded script by removing the Zone.Identifier alternate data stream.
  /// This is equivalent to right-clicking a file and selecting "Unblock" in Windows.
  /// </summary>
  /// <param name="scriptPath">The path to the script to unblock.</param>
  /// <returns>True if the script was successfully unblocked or was not blocked; false if unblocking failed.</returns>
  private bool TryUnblockScript(string scriptPath) {
    try {
      var zoneIdentifier = scriptPath + ":Zone.Identifier";
      if (File.Exists(zoneIdentifier)) {
        File.Delete(zoneIdentifier);
        _logger.LogInformation($"Unblocked script {scriptPath} by removing Zone.Identifier.");
      }
      return true;
    }
    catch (Exception ex) {
      _logger.LogWarning($"Failed to unblock script {scriptPath}: {ex.Message}");
      return false;
    }
  }

  /// <summary>
  /// Gets a list of script paths that are currently being executed.
  /// </summary>
  /// <returns>A list of script paths currently running.</returns>
  public List<string> GetRunningScriptTasks() {
    _logger.LogInformation($"Retrieving running script tasks. Current count: {_runningScripts.Count}");
    return _runningScripts.Keys.ToList();
  }

  /// <summary>
  /// Terminates a running PowerShell script by its path.
  /// Stops the script execution and disposes of its PowerShell instance.
  /// </summary>
  /// <param name="scriptPath">The path of the script to terminate.</param>
  public void TerminateScript(string scriptPath) {
    _logger.LogInformation($"Attempting to terminate script {scriptPath}");

    if (_runningScripts.TryRemove(scriptPath, out var ps)) {
      ps.Stop();
      ps.Dispose();
      _logger.LogInformation($"Script {scriptPath} terminated");
    }
    else {
      _logger.LogWarning($"Failed to terminate script {scriptPath}. Script not found.");
    }
  }

  /// <summary>
  /// Terminates all currently running PowerShell scripts.
  /// </summary>
  public void TerminateAllScripts() {
    _logger.LogInformation("Terminating all running scripts");

    foreach (var scriptPath in _runningScripts.Keys.ToList()) {
      TerminateScript(scriptPath);
    }
  }

  /// <summary>
  /// Releases all resources used by the <see cref="PSScriptService"/>.
  /// Terminates all running scripts and closes the RunspacePool.
  /// </summary>
  public void Dispose() {
    if (_disposed)
      return;

    _disposed = true;
    TerminateAllScripts();

    _runspacePool?.Close();
    _runspacePool?.Dispose();
    _logger.LogInformation("RunspacePool disposed");
  }
}
