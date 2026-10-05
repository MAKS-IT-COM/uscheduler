using CommunityToolkit.Mvvm.ComponentModel;
using MaksIT.UScheduler.Shared;


namespace MaksIT.UScheduler.UI.ViewModels;

public sealed partial class LogViewModel : ObservableObject {
  public LogViewModel() {
    Refresh();
  }

  public IReadOnlyList<string> Files { get; private set; } = [];

  [ObservableProperty]
  private string selectedFile = "";

  [ObservableProperty]
  private string report = "";

  [ObservableProperty]
  private string copyStatus = "";

  public void Refresh() {
    try {
      var dir = AppLog.Directory();
      Directory.CreateDirectory(dir);
      Files = Directory.GetFiles(dir)
        .OrderByDescending(File.GetLastWriteTimeUtc)
        .Select(Path.GetFileName)
        .Where(name => !string.IsNullOrWhiteSpace(name))
        .Cast<string>()
        .ToList();
    }
    catch {
      Files = [];
    }

    OnPropertyChanged(nameof(Files));

    if (Files.Count == 0) {
      SelectedFile = "";
      Report = "";

      return;
    }

    if (string.IsNullOrWhiteSpace(SelectedFile) || !Files.Contains(SelectedFile, StringComparer.OrdinalIgnoreCase))
      SelectedFile = Files[0];
    else
      LoadSelected();
  }

  partial void OnSelectedFileChanged(string value) =>
    LoadSelected();

  public void MarkCopied() =>
    CopyStatus = "Copied";

  private void LoadSelected() {
    CopyStatus = "";

    if (string.IsNullOrWhiteSpace(SelectedFile)) {
      Report = "";

      return;
    }

    try {
      var path = Path.Combine(AppLog.Directory(), SelectedFile);
      Report = File.Exists(path) ? File.ReadAllText(path) : "";
    }
    catch (Exception ex) {
      Report = ex.Message;
    }
  }
}
