namespace MaksIT.UScheduler.UI.Services;

/// <summary>Screens the snapshot tour can save. An empty request means every screen.</summary>
public static class SnapshotViews {
  public static readonly string[] All = [
    "main",
    "processes",
    "logs",
    "script-logs",
    "settings",
    "about",
    "program-log"
  ];

  public static IReadOnlyList<string> Resolve(IReadOnlyList<string> requested) =>
    requested.Count == 0 ? All : requested;

  public static bool IsKnown(string id) =>
    All.Any(view => string.Equals(view, id, StringComparison.OrdinalIgnoreCase));
}
