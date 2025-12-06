using System.Collections.Concurrent;
using System.Management.Automation;
using System.Management.Automation.Runspaces;


namespace MaksIT.UScheduler.Services;

public sealed class PSScriptService {

  private readonly ILogger<PSScriptService> _logger;
  private readonly ConcurrentDictionary<string, PowerShell> _runningScripts = new ConcurrentDictionary<string, PowerShell>();
  private readonly Runspace _rs = RunspaceFactory.CreateRunspace();

  public PSScriptService(ILogger<PSScriptService> logger) {
    _logger = logger;
    if (_rs.RunspaceStateInfo.State != RunspaceState.Opened) {
      _rs.Open();
      _logger.LogInformation($"Runspace opened");
    }
  }

  public Task RunScript(string scriptPath, bool signed, CancellationToken stoppingToken) {
    _logger.LogInformation($"Preparing to run script {scriptPath}");

    if (GetRunningScriptTasks().Contains(scriptPath)) {
      _logger.LogInformation($"PowerShell script {scriptPath} is already running");
      return Task.CompletedTask;
    }

    if (!File.Exists(scriptPath)) {
      _logger.LogError($"Script file {scriptPath} does not exist");
      return Task.CompletedTask;
    }

    if (!TryUnblockScript(scriptPath)) {
      _logger.LogError($"Script {scriptPath} could not be unblocked. Aborting execution.");
      return Task.CompletedTask;
    }

    var ps = PowerShell.Create();
    ps.Runspace = _rs;
    _runningScripts.TryAdd(scriptPath, ps);

    try {
      var scriptPolicy = signed ? "AllSigned" : "Unrestricted";
      ps.AddScript($"Set-ExecutionPolicy -Scope Process -ExecutionPolicy {scriptPolicy}");
      ps.Invoke();

      if (signed) {
        ps.Commands.Clear();
        ps.AddScript($"Get-AuthenticodeSignature \"{scriptPath}\"");
        var signatureResults = ps.Invoke();
        if (signatureResults.Count == 0 || ((Signature)signatureResults[0].BaseObject).Status != SignatureStatus.Valid) {
          _logger.LogWarning($"Script {scriptPath} signature is invalid. Correct and restart the service.");
          return Task.CompletedTask;
        }
      }

      _logger.LogInformation($"Invoking: {scriptPath}");

      ps.Commands.Clear();
      var myCommand = new Command(scriptPath);

      var currentDateTimeUtcString = DateTime.UtcNow.ToString("o");
      myCommand.Parameters.Add(new CommandParameter("Automated", true));
      myCommand.Parameters.Add(new CommandParameter("CurrentDateTimeUtc", currentDateTimeUtcString));
      ps.Commands.Commands.Add(myCommand);

      _logger.LogInformation($"Added parameters: Automated=true, CurrentDateTimeUtc={currentDateTimeUtcString}");

      // Log standard output
      var outputResults = ps.Invoke();
      if (outputResults != null && outputResults.Count > 0) {
        foreach (var outputItem in outputResults) {
          _logger.LogInformation($"[PS Output] {outputItem}");
        }
      }

      // Log errors
      if (ps.Streams.Error.Count > 0) {
        foreach (var errorItem in ps.Streams.Error) {
          _logger.LogError($"[PS Error] {errorItem}");
        }
      }
    }
    catch (OperationCanceledException) {
      _logger.LogInformation($"Stopping script {scriptPath} due to cancellation request");
    }
    catch (Exception ex) {
      _logger.LogError($"Error running script {scriptPath}: {ex.Message}");
    }
    finally {
      TerminateScript(scriptPath);
      _logger.LogInformation($"Script {scriptPath} completed and removed from running scripts");
    }

    return Task.CompletedTask;
  }

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

  public List<string> GetRunningScriptTasks() {
    _logger.LogInformation($"Retrieving running script tasks. Current count: {_runningScripts.Count}");
    return _runningScripts.Keys.ToList();
  }

  public void TerminateScript(string scriptPath) {
    _logger.LogInformation($"Attempting to terminate script {scriptPath}");

    if (_runningScripts.TryRemove(scriptPath, out var ps)) {
      ps.Stop();
      _logger.LogInformation($"Script {scriptPath} terminated");
    }
    else {
      _logger.LogWarning($"Failed to terminate script {scriptPath}. Script not found.");
    }
  }
}
