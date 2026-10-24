using Avalonia.Media;


namespace MaksIT.UScheduler.UI.ViewModels;

/// <summary>
/// One console line. Info is white, Success green, Warning yellow, Error red.
/// Warning is brighter than the Campbell cream yellow, which reads as white beside Info.
/// </summary>
public sealed class ScriptConsoleLine {
  public ScriptConsoleLine(string text, string level) {
    Text = text;
    Level = level is "Success" or "Warning" or "Error" ? level : "Info";
  }

  public string Text { get; }

  public string Level { get; }

  public Color Color =>
    Level switch {
      "Success" => Success,
      "Warning" => Warning,
      "Error" => Error,
      _ => Info
    };

  private static readonly Color Info = Color.Parse("#F2F2F2");
  private static readonly Color Success = Color.Parse("#16C60C");
  private static readonly Color Warning = Color.Parse("#FFCC00");
  private static readonly Color Error = Color.Parse("#E74856");
}
