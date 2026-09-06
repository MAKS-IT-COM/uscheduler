namespace MaksIT.UScheduler.Shared;

/// <summary>
/// Builds Windows SCM and systemd registration payloads used by the Worker host.
/// </summary>
public static class HostServiceRegistration {
  /// <summary>systemd unit path for a service name.</summary>
  public static string GetSystemdUnitPath(string serviceName) =>
    $"/etc/systemd/system/{serviceName}.service";

  /// <summary>
  /// Returns true when <paramref name="serviceName"/> is valid for both Windows SCM and systemd.
  /// </summary>
  public static bool IsValidServiceName(string? serviceName) {
    if (string.IsNullOrWhiteSpace(serviceName))
      return false;

    foreach (var c in serviceName) {
      if (char.IsAsciiLetterOrDigit(c) || c is '.' or '-' or '_' or '@')
        continue;

      return false;
    }

    return true;
  }

  /// <summary>
  /// <c>sc.exe create</c> arguments. Spaces after <c>=</c> are required by SCM.
  /// </summary>
  public static string FormatWindowsCreateArguments(string serviceName, string executablePath) {
    ArgumentException.ThrowIfNullOrWhiteSpace(serviceName);
    ArgumentException.ThrowIfNullOrWhiteSpace(executablePath);
    if (!IsValidServiceName(serviceName))
      throw new ArgumentException("Service name contains characters that Windows SCM or systemd reject.", nameof(serviceName));

    var path = Path.GetFullPath(executablePath);
    return $"create \"{serviceName}\" binPath= \"{path}\" start= auto";
  }

  /// <summary><c>sc.exe description</c> arguments.</summary>
  public static string FormatWindowsDescriptionArguments(string serviceName, string description) {
    ArgumentException.ThrowIfNullOrWhiteSpace(serviceName);
    var text = string.IsNullOrWhiteSpace(description)
      ? "MaksIT Unified Scheduler"
      : description.Replace("\"", "'", StringComparison.Ordinal);
    return $"description \"{serviceName}\" \"{text}\"";
  }

  /// <summary>
  /// systemd unit file body. <c>Type=notify</c> matches <c>AddSystemd()</c> on the Worker host.
  /// </summary>
  public static string FormatSystemdUnit(string serviceName, string executablePath, string description) {
    ArgumentException.ThrowIfNullOrWhiteSpace(serviceName);
    ArgumentException.ThrowIfNullOrWhiteSpace(executablePath);
    if (!IsValidServiceName(serviceName))
      throw new ArgumentException("Service name contains characters that Windows SCM or systemd reject.", nameof(serviceName));

    var exe = Path.GetFullPath(executablePath);
    var workingDirectory = Path.GetDirectoryName(exe) ?? "/";
    var desc = string.IsNullOrWhiteSpace(description)
      ? "MaksIT Unified Scheduler"
      : description.Replace("%", "%%", StringComparison.Ordinal).Replace('\n', ' ').Replace('\r', ' ');

    return
      $"""
      [Unit]
      Description={desc}
      After=network.target

      [Service]
      Type=notify
      WorkingDirectory={QuoteSystemdPath(workingDirectory)}
      ExecStart={QuoteSystemdPath(exe)}
      Restart=on-failure
      RestartSec=10
      KillSignal=SIGTERM
      SyslogIdentifier={serviceName}

      [Install]
      WantedBy=multi-user.target

      """;
  }

  private static string QuoteSystemdPath(string path) {
    var escaped = path.Replace("\"", "\\\"", StringComparison.Ordinal);
    return $"\"{escaped}\"";
  }
}
