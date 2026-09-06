namespace MaksIT.UScheduler.Shared.Helpers;


/// <summary>
/// Settings file locations. The product folder must match the WiX
/// <c>installFolderName</c> (or <c>Get-DesktopInstallFolderName</c> from
/// <c>appName</c> + <c>manufacturer</c>), e.g. <c>UScheduler</c>.
/// Shipped JSON next to the exe is seed-only.
/// </summary>
public static class UserSettingsPath {
  public const string Manufacturer = "MaksIT";

  /// <summary>
  /// Per-user UI prefs under roaming AppData,
  /// e.g. <c>%AppData%/MaksIT/UScheduler/settings.json</c>.
  /// </summary>
  public static string Get(string product, string fileName = "settings.json") =>
    Combine(Environment.SpecialFolder.ApplicationData, product, fileName);

  /// <summary>
  /// Machine-wide settings shared by every user and the Windows service
  /// (LocalSystem). On Windows this is all-users AppData:
  /// <c>%ProgramData%/MaksIT/UScheduler/settings.json</c>.
  /// </summary>
  public static string GetShared(string product, string fileName = "settings.json") {
    if (OperatingSystem.IsWindows())
      return Combine(Environment.SpecialFolder.CommonApplicationData, product, fileName);

    return Path.Combine("/var/lib", "maksit", Sanitize(product), fileName);
  }

  private static string Combine(Environment.SpecialFolder folder, string product, string fileName) =>
    Path.Combine(Environment.GetFolderPath(folder), Manufacturer, product, fileName);

  private static string Sanitize(string product) =>
    product.Trim().ToLowerInvariant().Replace(' ', '-');
}
