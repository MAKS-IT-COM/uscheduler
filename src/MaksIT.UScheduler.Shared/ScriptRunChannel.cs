using System.IO.Pipes;
using System.Text;
using System.Text.Json;


namespace MaksIT.UScheduler.Shared;

/// <summary>
/// Asks the running scheduler to start a configured script. The desktop window
/// uses this so the script runs as the service account.
/// </summary>
public static class ScriptRunChannel {
  public const string PipeName = "MaksIT.UScheduler.Run";

  private static readonly JsonSerializerOptions JsonOptions = new() {
    PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
    PropertyNameCaseInsensitive = true
  };

  public static PowershellScript? FindConfiguredScript(Configuration configuration, string requestedPath) {
    ArgumentNullException.ThrowIfNull(configuration);
    if (string.IsNullOrWhiteSpace(requestedPath))
      return null;

    foreach (var script in configuration.Powershell) {
      if (string.IsNullOrWhiteSpace(script.Path))
        continue;

      if (PathsEqual(script.Path, requestedPath))
        return script;

      if (PathsEqual(configuration.ResolveScriptPath(script.Path), requestedPath))
        return script;
    }

    return null;
  }

  public static async Task<ScriptRunResult> RequestAsync(
    string scriptPath,
    CancellationToken cancellationToken = default,
    string? pipeName = null,
    int timeoutMs = 3000
  ) {
    if (string.IsNullOrWhiteSpace(scriptPath))
      return new ScriptRunResult(false, "This script is not in the service configuration.");

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

      var payload = JsonSerializer.Serialize(new ScriptRunRequest { Path = scriptPath }, JsonOptions);
      await writer.WriteLineAsync(payload.AsMemory(), linked.Token).ConfigureAwait(false);

      var line = await reader.ReadLineAsync(linked.Token).ConfigureAwait(false);
      if (string.IsNullOrWhiteSpace(line))
        return new ScriptRunResult(false, "The scheduler service did not answer.");

      return JsonSerializer.Deserialize<ScriptRunResult>(line, JsonOptions)
        ?? new ScriptRunResult(false, "The scheduler service did not answer.");
    }
    catch (OperationCanceledException) when (!cancellationToken.IsCancellationRequested) {
      return new ScriptRunResult(false, "The scheduler service is not running. Start the service, then launch the script again.");
    }
    catch (TimeoutException) {
      return new ScriptRunResult(false, "The scheduler service is not running. Start the service, then launch the script again.");
    }
    catch (IOException) {
      return new ScriptRunResult(false, "The scheduler service is not running. Start the service, then launch the script again.");
    }
    catch (UnauthorizedAccessException) {
      return new ScriptRunResult(false, "The scheduler service refused the connection.");
    }
  }

  public static string SerializeRequest(ScriptRunRequest request) =>
    JsonSerializer.Serialize(request, JsonOptions);

  public static ScriptRunRequest? DeserializeRequest(string json) =>
    JsonSerializer.Deserialize<ScriptRunRequest>(json, JsonOptions);

  public static string SerializeResult(ScriptRunResult result) =>
    JsonSerializer.Serialize(result, JsonOptions);

  public static ScriptRunResult? DeserializeResult(string json) =>
    JsonSerializer.Deserialize<ScriptRunResult>(json, JsonOptions);

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

public sealed class ScriptRunRequest {
  public string Path { get; set; } = string.Empty;
}

public sealed record ScriptRunResult(bool Accepted, string Message);
