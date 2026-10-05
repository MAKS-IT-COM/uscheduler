using System.Diagnostics;
using CommunityToolkit.Mvvm.Input;
using MaksIT.UScheduler.Shared;


namespace MaksIT.UScheduler.UI.ViewModels;

public sealed partial class AboutViewModel {
  public string Brand => AppInfo.Brand;

  public string ProductName => AppInfo.ProductName;

  public string Summary => AppInfo.Summary;

  public string Version => AppInfo.Version;

  public string Credits => AppInfo.Credits;

  public AppContact SecurityContact => AppInfo.Security;

  public AppContact SupportContact => AppInfo.Support;

  public string License => AppInfo.License;

  public string Copyright => AppInfo.Copyright;

  public string Site => AppInfo.Site;

  [RelayCommand]
  private void OpenContact(string? uri) {
    if (string.IsNullOrWhiteSpace(uri))
      return;

    OpenUrl(uri);
  }

  [RelayCommand]
  private void OpenSite() =>
    OpenUrl(AppInfo.SiteUri);

  private static void OpenUrl(string url) {
    try {
      Process.Start(new ProcessStartInfo {
        FileName = url,
        UseShellExecute = true
      });
    }
    catch {
    }
  }
}
