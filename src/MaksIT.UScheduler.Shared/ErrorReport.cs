using MaksIT.Core.Desktop;


namespace MaksIT.UScheduler.Shared;

/// <summary>Formats unhandled exceptions for a copyable dialog and a crash log file.</summary>
public static class ErrorReport {
  public static string Capture(Exception exception) =>
    CrashReport.Capture(
      exception,
      AppInfo.ProductName + " " + AppInfo.Version,
      AppInfo.Brand,
      AppLog.Directory,
      AppLog.Write);

  public static string Format(Exception exception) =>
    CrashReport.Format(exception, AppInfo.ProductName + " " + AppInfo.Version, AppInfo.Brand);
}
