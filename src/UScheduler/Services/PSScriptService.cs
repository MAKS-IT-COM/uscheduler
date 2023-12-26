using System.Management.Automation;
using System.Management.Automation.Runspaces;
using System.Collections.Concurrent;

namespace UScheduler.Services {
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

    public Task RunScript(string scriptPath, bool signed) {
      _logger.LogInformation($"Preparing to run script {scriptPath}");

      if (!File.Exists(scriptPath)) {
        _logger.LogError($"Script file {scriptPath} does not exist");
        return Task.CompletedTask;
      }

      var ps = PowerShell.Create();
      ps.Runspace = _rs;
      _runningScripts.TryAdd(scriptPath, ps);

      try {
        var scriptPolicy = "Unrestricted";
        if (signed)
          scriptPolicy = "AllSigned";

        ps.AddScript($"Set-ExecutionPolicy -Scope Process -ExecutionPolicy {scriptPolicy}");
        ps.Invoke();

        ps.AddScript($"Get-AuthenticodeSignature \"{scriptPath}\"");

        foreach (var result in ps.Invoke()) {
          if (signed) {
            if (((Signature)result.BaseObject).Status != SignatureStatus.Valid) {
              _logger.LogWarning($"Script {Directory.GetParent(scriptPath)?.Name} Signature Error! Correct, and restart the service.");

              return Task.CompletedTask;
            }
          }

          _logger.LogInformation($"Invoking: {scriptPath}");

          var myCommand = new Command(scriptPath);

          // Pass -Automated switch and -CuttrentDateTimeUtc, as UTC ISO 8601 string
          myCommand.Parameters.Add(new CommandParameter("Automated", true));
          myCommand.Parameters.Add(new CommandParameter("CurrentDateTimeUtc", DateTime.UtcNow.ToString("o")));

          ps.Commands.Commands.Add(myCommand);
          ps.Invoke();
        }
      }
      catch (Exception ex) {
        _logger.LogError($"Error running script {scriptPath}: {ex.Message}");
      }
      finally {
        _runningScripts.TryRemove(scriptPath, out _);
        _logger.LogInformation($"Script {scriptPath} completed and removed from running scripts");
      }

      return Task.CompletedTask;
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

    public void TerminateAllScripts() {
      foreach (var script in _runningScripts) {
        TerminateScript(script.Key);
      }
    }
  }
}
