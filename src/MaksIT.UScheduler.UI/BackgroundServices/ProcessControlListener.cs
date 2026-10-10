using System.Text;
using System.IO.Pipes;
using System.Security.Principal;
using System.Security.AccessControl;
using MaksIT.UScheduler.Shared;


namespace MaksIT.UScheduler.BackgroundServices;

/// <summary>
/// Accepts start, stop, and restart requests from the desktop window.
/// </summary>
public sealed class ProcessControlListener : BackgroundService {
  private readonly ILogger<ProcessControlListener> _logger;
  private readonly ProcessBackgroundService _processes;

  public ProcessControlListener(
    ILogger<ProcessControlListener> logger,
    ProcessBackgroundService processes
  ) {
    _logger = logger;
    _processes = processes;
  }

  protected override async Task ExecuteAsync(CancellationToken stoppingToken) {
    _logger.LogInformation("Starting process control listener");

    while (!stoppingToken.IsCancellationRequested) {
      NamedPipeServerStream? server = null;
      try {
        server = CreateServer();
        await server.WaitForConnectionAsync(stoppingToken).ConfigureAwait(false);
        var result = await AcceptAsync(server, stoppingToken).ConfigureAwait(false);
        await using var writer = new StreamWriter(server, Encoding.UTF8, leaveOpen: true) {
          AutoFlush = true
        };
        await writer.WriteLineAsync(ProcessControlChannel.SerializeResult(result).AsMemory(), stoppingToken).ConfigureAwait(false);
      }
      catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested) {
        break;
      }
      catch (Exception ex) {
        _logger.LogError(ex, "Process control listener failed while accepting a request");
      }
      finally {
        if (server is not null)
          await server.DisposeAsync().ConfigureAwait(false);
      }
    }
  }

  private async Task<ProcessControlResult> AcceptAsync(NamedPipeServerStream server, CancellationToken stoppingToken) {
    using var reader = new StreamReader(server, Encoding.UTF8, detectEncodingFromByteOrderMarks: false, leaveOpen: true);
    var line = await reader.ReadLineAsync(stoppingToken).ConfigureAwait(false);
    if (string.IsNullOrWhiteSpace(line))
      return new ProcessControlResult(false, "The request was empty.");

    var request = ProcessControlChannel.DeserializeRequest(line);
    if (request is null || string.IsNullOrWhiteSpace(request.Path))
      return new ProcessControlResult(false, "The request was empty.");

    if (request.Action == ProcessControlChannel.Start)
      return await _processes.StartProgramAsync(request.Path, stoppingToken).ConfigureAwait(false);

    if (request.Action == ProcessControlChannel.Stop)
      return await _processes.StopProgramAsync(request.Path, stoppingToken).ConfigureAwait(false);

    if (request.Action == ProcessControlChannel.Restart)
      return await _processes.RestartProgramAsync(request.Path, stoppingToken).ConfigureAwait(false);

    return new ProcessControlResult(false, "The request was not start, stop, or restart.");
  }

  private static NamedPipeServerStream CreateServer() {
    if (!OperatingSystem.IsWindows()) {
      return new NamedPipeServerStream(
        ProcessControlChannel.PipeName,
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
      ProcessControlChannel.PipeName,
      PipeDirection.InOut,
      1,
      PipeTransmissionMode.Byte,
      PipeOptions.Asynchronous,
      0,
      0,
      security);
  }
}
