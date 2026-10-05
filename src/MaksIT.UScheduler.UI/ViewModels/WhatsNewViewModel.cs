using CommunityToolkit.Mvvm.ComponentModel;
using MaksIT.UScheduler.Shared;


namespace MaksIT.UScheduler.UI.ViewModels;

public sealed partial class WhatsNewViewModel : ObservableObject {
  public WhatsNewViewModel(IReadOnlyList<ReleaseNote> notes) {
    Notes = notes;
  }

  public IReadOnlyList<ReleaseNote> Notes { get; }

  [ObservableProperty]
  private bool doNotShowAgain;
}
