using System.IO.Pipes;
using System.Security.AccessControl;
using System.Security.Principal;
using System.Text;
using MaksIT.UScheduler.Services;
using MaksIT.UScheduler.Shared;


namespace MaksIT.UScheduler.BackgroundServices;

/// <summary>
/// Accepts manual run requests from the desktop window and starts them in this process.
/// </summary>
public sealed class ScriptRunListener : BackgroundService {
  private readonly ILogger<ScriptRunListener> _logger;
  private readonly IOptionsMonitor<Configuration> _optionsMonitor;
  private readonly IPSScriptService _scripts;

  public ScriptRunListener(
    ILogger<ScriptRunListener> logger,
    IOptionsMonitor<Configuration> optionsMonitor,
    IPSScriptService scripts
  ) {
    _logger = logger;
    _optionsMonitor = optionsMonitor;
    _scripts = scripts;
  }

  protected override async Task ExecuteAsync(CancellationToken stoppingToken) {
    _logger.LogInformation("Starting script run listener");

    while (!stoppingToken.IsCancellationRequested) {
      NamedPipeServerStream? server = null;
      try {
        server = CreateServer();
        await server.WaitForConnectionAsync(stoppingToken).ConfigureAwait(false);
        var result = await AcceptAsync(server, stoppingToken).ConfigureAwait(false);
        await using var writer = new StreamWriter(server, Encoding.UTF8, leaveOpen: true) {
          AutoFlush = true
        };
        await writer.WriteLineAsync(ScriptRunChannel.SerializeResult(result).AsMemory(), stoppingToken).ConfigureAwait(false);
      }
      catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested) {
        break;
      }
      catch (Exception ex) {
        _logger.LogError(ex, "Script run listener failed while accepting a request");
      }
      finally {
        if (server is not null)
          await server.DisposeAsync().ConfigureAwait(false);
      }
    }
  }

  private async Task<ScriptRunResult> AcceptAsync(NamedPipeServerStream server, CancellationToken stoppingToken) {
    using var reader = new StreamReader(server, Encoding.UTF8, detectEncodingFromByteOrderMarks: false, leaveOpen: true);
    var line = await reader.ReadLineAsync(stoppingToken).ConfigureAwait(false);
    if (string.IsNullOrWhiteSpace(line))
      return new ScriptRunResult(false, "The launch request was empty.");

    var request = ScriptRunChannel.DeserializeRequest(line);
    if (request is null || string.IsNullOrWhiteSpace(request.Path))
      return new ScriptRunResult(false, "The launch request was empty.");

    var configuration = _optionsMonitor.CurrentValue;
    var script = ScriptRunChannel.FindConfiguredScript(configuration, request.Path);
    if (script is null)
      return new ScriptRunResult(false, "That script is not in the service configuration.");

    if (!HostPlatforms.IsCompatible(script.Platforms))
      return new ScriptRunResult(false, "That script cannot run on this operating system.");

    var resolved = configuration.ResolveScriptPath(script.Path);
    if (_scripts.GetRunningScriptTasks().Contains(resolved, OperatingSystem.IsWindows()
          ? StringComparer.OrdinalIgnoreCase
          : StringComparer.Ordinal))
      return new ScriptRunResult(false, "That script is already running.");

    _logger.LogInformation("Manual launch requested for {Path}", resolved);
    _ = _scripts.RunScriptAsync(resolved, script.IsSigned, stoppingToken, automated: false);
    return new ScriptRunResult(true, "The service started the script.");
  }

  private static NamedPipeServerStream CreateServer() {
    if (!OperatingSystem.IsWindows()) {
      return new NamedPipeServerStream(
        ScriptRunChannel.PipeName,
        PipeDirection.InOut,
        1,
        PipeTransmissionMode.Byte,
        PipeOptions.Asynchronous);
    }

    var security = new PipeSecurity();
    security.AddAccessRule(new PipeAccessRule(
      new SecurityIdentifier(WellKnownSidType.AuthenticatedUserSid, null),
      PipeAccessRights.ReadWrite,
      AccessControlType.Allow));
    security.AddAccessRule(new PipeAccessRule(
      new SecurityIdentifier(WellKnownSidType.LocalSystemSid, null),
      PipeAccessRights.FullControl,
      AccessControlType.Allow));
    security.AddAccessRule(new PipeAccessRule(
      new SecurityIdentifier(WellKnownSidType.BuiltinAdministratorsSid, null),
      PipeAccessRights.FullControl,
      AccessControlType.Allow));

    return NamedPipeServerStreamAcl.Create(
      ScriptRunChannel.PipeName,
      PipeDirection.InOut,
      1,
      PipeTransmissionMode.Byte,
      PipeOptions.Asynchronous,
      0,
      0,
      security);
  }
}
