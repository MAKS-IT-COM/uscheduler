using System.Reflection;


namespace MaksIT.UScheduler.Shared;

public readonly record struct AppContact(string Role, string Address) {
  public string Uri => "mailto:" + Address;
}

public static class AppInfo {
  public const string Brand = "MaksIT";
  public const string ProductName = "UScheduler";
  public const string AboutTitle = "About " + ProductName;
  public const string Credits = "Maksym Sadovnychyy";
  public static readonly AppContact Security = new("Security", "security@maks-it.com");
  public static readonly AppContact Support = new("Support", "support@maks-it.com");
  public const string Site = "maks-it.com";
  public const string SiteUri = "https://maks-it.com";
  public const string License = "Apache License 2.0";
  public const string Summary = "Schedule PowerShell scripts and console programs.";

  public static string Copyright =>
    $"Copyright {DateTime.UtcNow.Year} Maksym Sadovnychyy (MAKS-IT)";

  public static string Version {
    get {
      var assembly = Assembly.GetEntryAssembly() ?? typeof(AppInfo).Assembly;
      var informational = assembly.GetCustomAttribute<AssemblyInformationalVersionAttribute>()?.InformationalVersion;

      if (!string.IsNullOrWhiteSpace(informational)) {
        var plus = informational.IndexOf('+', StringComparison.Ordinal);

        return plus >= 0 ? informational[..plus] : informational;
      }

      var version = assembly.GetName().Version;

      if (version is null)
        return "";

      if (version.Build < 0)
        return $"{version.Major}.{version.Minor}";

      return $"{version.Major}.{version.Minor}.{version.Build}";
    }
  }
}
