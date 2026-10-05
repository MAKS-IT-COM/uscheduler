namespace MaksIT.UScheduler.Shared;

/// <summary>Program log under the user logs folder. Script output is not written here.</summary>
public static class AppLog {
  private static readonly Lock Gate = new();

  public static string Directory() =>
    Helpers.UserSettingsPath.LogsDirectory(HostPaths.ProductFolder);

  public static string FilePath() =>
    Path.Combine(Directory(), "app.log");

  public static void Write(string message) {
    try {
      System.IO.Directory.CreateDirectory(Directory());
      var line = DateTimeOffset.UtcNow.ToString("u") + " " + (message ?? "").TrimEnd();
      lock (Gate)
        File.AppendAllText(FilePath(), line + Environment.NewLine);
    }
    catch {
    }
  }

  public static void Write(Exception exception) {
    if (exception is null)
      return;

    Write(ErrorReport.Format(exception));
  }
}
