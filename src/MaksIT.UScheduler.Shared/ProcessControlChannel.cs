using System.IO.Pipes;
using System.Text;
using System.Text.Json;
using MaksIT.UScheduler.Shared.Helpers;


namespace MaksIT.UScheduler.Shared;

/// <summary>
/// Asks the running scheduler to start, stop, or restart one configured program.
/// The desktop window uses this so the program runs as the service account.
/// </summary>
public static class ProcessControlChannel {
  public const string PipeName = "MaksIT.UScheduler.Process";

  public const string Start = "start";

  public const string Stop = "stop";

  public const string Restart = "restart";

  private static readonly JsonSerializerOptions JsonOptions = new() {
    PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
    PropertyNameCaseInsensitive = true
  };

  public static ProcessConfiguration? Find(Configuration configuration, string requestedPath) {
    ArgumentNullException.ThrowIfNull(configuration);
    if (string.IsNullOrWhiteSpace(requestedPath))
      return null;

    foreach (var process in configuration.Processes) {
      if (string.IsNullOrWhiteSpace(process.Path))
        continue;

      if (PathsEqual(process.Path, requestedPath))
        return process;

      if (PathsEqual(PathHelper.ResolvePath(process.Path), requestedPath))
        return process;
    }

    return null;
  }

  public static async Task<ProcessControlResult> RequestAsync(
    string processPath,
    string action,
    CancellationToken cancellationToken = default,
    string? pipeName = null,
    int timeoutMs = 8000
  ) {
    if (string.IsNullOrWhiteSpace(processPath))
      return new ProcessControlResult(false, "This program is not in the service configuration.");

    if (action is not Start and not Stop and not Restart)
      return new ProcessControlResult(false, "The request was not start, stop, or restart.");

    var name = string.IsNullOrWhiteSpace(pipeName) ? PipeName : pipeName;
    using var timeout = new CancellationTokenSource(Math.Max(1, timeoutMs));
    using var linked = CancellationTokenSource.CreateLinkedTokenSource(timeout.Token, cancellationToken);

    try {
      using var pipe = new NamedPipeClientStream(".", name, PipeDirection.InOut, PipeOptions.Asynchronous);
      await pipe.ConnectAsync(linked.Token).ConfigureAwait(false);

      using var reader = new StreamReader(pipe, Encoding.UTF8, detectEncodingFromByteOrderMarks: false, leaveOpen: true);
      await using var writer = new StreamWriter(pipe, Encoding.UTF8, leaveOpen: true) {
        AutoFlush = true
      };

      var payload = JsonSerializer.Serialize(new ProcessControlRequest { Path = processPath, Action = action }, JsonOptions);
      await writer.WriteLineAsync(payload.AsMemory(), linked.Token).ConfigureAwait(false);

      var line = await reader.ReadLineAsync(linked.Token).ConfigureAwait(false);
      if (string.IsNullOrWhiteSpace(line))
        return new ProcessControlResult(false, "The scheduler service did not answer.");

      return JsonSerializer.Deserialize<ProcessControlResult>(line, JsonOptions)
        ?? new ProcessControlResult(false, "The scheduler service did not answer.");
    }
    catch (OperationCanceledException) when (!cancellationToken.IsCancellationRequested) {
      return new ProcessControlResult(false, "The scheduler service is not running. Start the service, then try again.");
    }
    catch (TimeoutException) {
      return new ProcessControlResult(false, "The scheduler service is not running. Start the service, then try again.");
    }
    catch (IOException) {
      return new ProcessControlResult(false, "The scheduler service is not running. Start the service, then try again.");
    }
    catch (UnauthorizedAccessException) {
      return new ProcessControlResult(false, "The scheduler service refused the connection.");
    }
  }

  public static string SerializeRequest(ProcessControlRequest request) =>
    JsonSerializer.Serialize(request, JsonOptions);

  public static ProcessControlRequest? DeserializeRequest(string json) =>
    JsonSerializer.Deserialize<ProcessControlRequest>(json, JsonOptions);

  public static string SerializeResult(ProcessControlResult result) =>
    JsonSerializer.Serialize(result, JsonOptions);

  public static ProcessControlResult? DeserializeResult(string json) =>
    JsonSerializer.Deserialize<ProcessControlResult>(json, JsonOptions);

  private static bool PathsEqual(string left, string right) {
    try {
      left = Path.GetFullPath(left);
      right = Path.GetFullPath(right);
    }
    catch (Exception ex) when (ex is ArgumentException or NotSupportedException or PathTooLongException) {
    }

    return string.Equals(
      left.TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar),
      right.TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar),
      OperatingSystem.IsWindows() ? StringComparison.OrdinalIgnoreCase : StringComparison.Ordinal);
  }
}

public sealed class ProcessControlRequest {
  public string Path { get; set; } = string.Empty;

  public string Action { get; set; } = string.Empty;
}

public sealed record ProcessControlResult(bool Accepted, string Message);
