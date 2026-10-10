using MaksIT.Core.UI.Errors;
using MaksIT.UScheduler.Shared;
using CoreErrorDialog = MaksIT.Core.UI.Errors.ErrorDialog;


namespace MaksIT.UScheduler.UI.Dialogs;

internal static class ErrorDialog {
  private static int _ready;

  public static void Report(Exception? exception) {
    Ensure();
    CoreErrorDialog.Report(exception);
  }

  public static void ReportBlocking(Exception? exception) {
    Ensure();
    CoreErrorDialog.ReportBlocking(exception);
  }

  private static void Ensure() {
    if (Interlocked.Exchange(ref _ready, 1) != 0)
      return;

    CoreErrorDialog.Use(new DesktopErrorOptions {
      Capture = ErrorReport.Capture,
      Text = () => new DesktopErrorText {
        Title = AppInfo.ProductName,
        Hint = "Something went wrong. The details below are also saved under Help → Logs."
      }
    });
  }
}
