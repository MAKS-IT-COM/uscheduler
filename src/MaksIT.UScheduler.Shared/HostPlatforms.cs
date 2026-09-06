using MaksIT.Core.Abstractions;


namespace MaksIT.UScheduler.Shared;

/// <summary>
/// Host operating systems a script or process may declare. An empty platforms list means all hosts.
/// </summary>
public sealed class HostPlatforms : Enumeration {
  public static readonly HostPlatforms Windows = new(1, "Windows");
  public static readonly HostPlatforms Linux = new(2, "Linux");

  private HostPlatforms(int id, string name) : base(id, name) { }

  /// <summary>
  /// Returns true when <paramref name="platforms"/> is empty (all hosts) or lists the current OS.
  /// </summary>
  public static bool IsCompatible(IReadOnlyList<string>? platforms) {
    if (platforms is null || platforms.Count == 0)
      return true;

    HostPlatforms? current = null;
    if (OperatingSystem.IsWindows())
      current = Windows;
    else if (OperatingSystem.IsLinux())
      current = Linux;

    if (current is null)
      return false;

    foreach (var item in platforms) {
      if (string.Equals(item, current.Name, StringComparison.OrdinalIgnoreCase))
        return true;
    }

    return false;
  }

  /// <summary>
  /// Short label for the UI (e.g. "Windows only", "Windows and Linux").
  /// </summary>
  public static string FormatLabel(IReadOnlyList<string>? platforms) {
    if (platforms is null || platforms.Count == 0)
      return "Windows and Linux";

    var names = GetAll<HostPlatforms>()
      .Where(platform => platforms.Any(item => string.Equals(item, platform.Name, StringComparison.OrdinalIgnoreCase)))
      .Select(platform => platform.Name)
      .ToList();

    if (names.Count == 0)
      return string.Join(", ", platforms);

    if (names.Count == 1)
      return $"{names[0]} only";

    return string.Join(" and ", names);
  }
}
