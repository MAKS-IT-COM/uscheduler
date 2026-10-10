using Avalonia.Controls;
using MaksIT.UScheduler.Shared;
using CoreAbout = MaksIT.Core.UI.About.AboutWindow;
using CoreContact = MaksIT.Core.UI.About.AppContact;
using CoreInfo = MaksIT.Core.UI.About.DesktopAppInfo;
using CoreModel = MaksIT.Core.UI.About.AboutViewModel;


namespace MaksIT.UScheduler.UI.Windows;

public static class AboutWindow {
  public static Task ShowAsync(Window owner) =>
    Create(owner).ShowDialog(owner);

  public static Window Create(Window owner) {
    var info = Info();

    return new CoreAbout {
      Title = info.WindowTitle,
      DataContext = new CoreModel(info),
      WindowStartupLocation = WindowStartupLocation.CenterOwner,
      Icon = owner.Icon
    };
  }

  private static CoreInfo Info() =>
    new() {
      Brand = AppInfo.Brand,
      ProductName = AppInfo.ProductName,
      Summary = AppInfo.Summary,
      Version = AppInfo.Version,
      Credits = AppInfo.Credits,
      License = AppInfo.License,
      Copyright = AppInfo.Copyright,
      Site = AppInfo.Site,
      SiteUri = AppInfo.SiteUri,
      Title = AppInfo.AboutTitle,
      Contacts = [
        new CoreContact(AppInfo.Security.Role, AppInfo.Security.Address),
        new CoreContact(AppInfo.Support.Role, AppInfo.Support.Address)
      ]
    };
}
