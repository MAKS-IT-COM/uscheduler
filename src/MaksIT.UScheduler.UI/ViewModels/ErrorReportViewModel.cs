using CommunityToolkit.Mvvm.ComponentModel;


namespace MaksIT.UScheduler.UI.ViewModels;


public sealed partial class ErrorReportViewModel : ObservableObject {
  public ErrorReportViewModel(string report) {
    Report = report ?? "";
  }

  public string Report { get; }

  [ObservableProperty]
  private string copyStatus = "";

  public void MarkCopied() =>
    CopyStatus = "Copied";
}
