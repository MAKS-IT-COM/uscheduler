using System.Diagnostics;


namespace MaksIT.UScheduler.Shared;

/// <summary>
/// Opens folders and files with the host shell (Explorer on Windows, xdg-open on Linux).
/// </summary>
public static class ShellOpen {
  public static void OpenDirectory(string path) {
    ArgumentException.ThrowIfNullOrWhiteSpace(path);
    if (OperatingSystem.IsWindows()) {
      Process.Start(new ProcessStartInfo {
        FileName = "explorer.exe",
        Arguments = path,
        UseShellExecute = true
      });
      return;
    }

    Process.Start(new ProcessStartInfo {
      FileName = "xdg-open",
      Arguments = path,
      UseShellExecute = false
    });
  }

  public static void RevealFile(string path) {
    ArgumentException.ThrowIfNullOrWhiteSpace(path);
    if (OperatingSystem.IsWindows()) {
      Process.Start(new ProcessStartInfo {
        FileName = "explorer.exe",
        Arguments = $"/select,\"{path}\"",
        UseShellExecute = true
      });
      return;
    }

    var directory = Path.GetDirectoryName(path);
    if (!string.IsNullOrEmpty(directory))
      OpenDirectory(directory);
  }
}
