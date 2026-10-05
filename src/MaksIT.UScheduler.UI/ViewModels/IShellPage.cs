using System.ComponentModel;
using MaksIT.UScheduler.UI.Controls.Footer;


namespace MaksIT.UScheduler.UI.ViewModels;

/// <summary>
/// A shell page. It owns the actions for its view and injects them into the shared footer.
/// </summary>
public interface IShellPage : INotifyPropertyChanged {
  string Header { get; }

  IReadOnlyList<FooterItem> FooterItems { get; }
}
