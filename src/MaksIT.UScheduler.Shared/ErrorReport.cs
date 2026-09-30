using System.Reflection;
using System.Runtime.InteropServices;
using System.Text;
using MaksIT.UScheduler.Shared.Helpers;


namespace MaksIT.UScheduler.Shared;


/// <summary>Formats unhandled exceptions for a copyable dialog and a crash log file.</summary>
public static class ErrorReport {
  public static string Capture(Exception exception) {
    ArgumentNullException.ThrowIfNull(exception);
    var body = Format(exception);
    var path = TryWrite(body);
    if (string.IsNullOrWhiteSpace(path))
      return body;
    return body + Environment.NewLine + Environment.NewLine + "Log: " + path;
  }

  public static string Format(Exception exception) {
    ArgumentNullException.ThrowIfNull(exception);
    var text = new StringBuilder();
    text.AppendLine("UScheduler " + Version());
    text.AppendLine("MaksIT");
    text.AppendLine(DateTimeOffset.UtcNow.ToString("u"));
    text.AppendLine(RuntimeInformation.OSDescription);
    text.AppendLine(RuntimeInformation.FrameworkDescription);
    text.AppendLine((Environment.Is64BitProcess ? "64-bit" : "32-bit") + " process");
    text.AppendLine();
    AppendException(text, exception);
    return text.ToString().TrimEnd();
  }

  public static string? TryWrite(string report) {
    try {
      var dir = UserSettingsPath.LogsDirectory(HostPaths.ProductFolder);
      Directory.CreateDirectory(dir);
      var name = "crash-" + DateTime.UtcNow.ToString("yyyyMMdd-HHmmss") + "-" + Environment.ProcessId + ".txt";
      var path = Path.Combine(dir, name);
      File.WriteAllText(path, report ?? "");
      return path;
    }
    catch {
      return null;
    }
  }

  private static string Version() {
    var version = Assembly.GetEntryAssembly()?.GetName().Version;
    return version is null ? "" : version.ToString();
  }

  private static void AppendException(StringBuilder text, Exception exception) {
    var seen = new HashSet<Exception>();
    var current = exception;
    var depth = 0;
    while (current is not null && seen.Add(current)) {
      if (depth > 0)
        text.AppendLine().AppendLine("--- inner ---");
      text.AppendLine(current.GetType().FullName);
      text.AppendLine(current.Message);
      if (!string.IsNullOrWhiteSpace(current.StackTrace))
        text.AppendLine(current.StackTrace);
      if (current is AggregateException aggregate) {
        foreach (var inner in aggregate.InnerExceptions) {
          if (inner is null || ReferenceEquals(inner, current.InnerException) || !seen.Add(inner))
            continue;
          text.AppendLine().AppendLine("--- aggregate ---");
          text.AppendLine(inner.ToString());
        }
      }

      current = current.InnerException;
      depth++;
    }
  }
}
