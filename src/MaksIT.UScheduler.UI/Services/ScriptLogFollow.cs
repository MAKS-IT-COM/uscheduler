using System.Text;
using MaksIT.UScheduler.Shared;


namespace MaksIT.UScheduler.UI.Services;

/// <summary>One PowerShell log line and the <c>Write-Log</c> level used to color it.</summary>
public readonly record struct PowerShellLogLine(string Text, string Level);

/// <summary>
/// Reads the script log the service appends while a run is in progress.
/// The file name matches <c>MaksIT.Core</c> file logging: <c>log_yyyy-MM-dd.txt</c> under a folder named for the script.
/// </summary>
public static class ScriptLogFollow {
  public static string Today(string logDirectory, string scriptPath) {
    var folder = Path.GetFileNameWithoutExtension(scriptPath);

    if (string.IsNullOrEmpty(folder))
      folder = "script";

    var day = DateTime.UtcNow.ToString("yyyy-MM-dd");
    return Path.Combine(logDirectory, folder, $"log_{day}.txt");
  }

  public static long Length(string path) {
    if (string.IsNullOrWhiteSpace(path) || !File.Exists(path))
      return 0;

    return new FileInfo(path).Length;
  }

  /// <summary>
  /// Returns text appended after <paramref name="position"/> and advances <paramref name="position"/>.
  /// A shorter replacement file is read from the start.
  /// </summary>
  public static string ReadNewText(string path, ref long position) {
    if (string.IsNullOrWhiteSpace(path) || !File.Exists(path))
      return "";

    try {
      return ReadNewTextCore(path, ref position);
    }
    catch (Exception ex) when (ex is IOException or UnauthorizedAccessException) {
      return "";
    }
  }

  private static string ReadNewTextCore(string path, ref long position) {
    using var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite);

    if (stream.Length < position)
      position = 0;

    var available = stream.Length - position;

    if (available <= 0)
      return "";

    stream.Position = position;
    var count = (int)Math.Min(available, 1024 * 1024);
    var buffer = new byte[count];
    var read = stream.Read(buffer, 0, count);
    var usable = TrimPartialUtf8(buffer, read);
    position += usable;
    return Encoding.UTF8.GetString(buffer, 0, usable);
  }

  /// <summary>
  /// Turns file-logger lines into PowerShell text and a <c>Write-Log</c> level.
  /// An unfinished last line stays in <paramref name="pending"/>.
  /// <paramref name="level"/> carries the color of a record that spans lines.
  /// The scheduler's finished marker is not included; <paramref name="finished"/> reports it.
  /// </summary>
  public static IReadOnlyList<PowerShellLogLine> FormatPowerShell(
    string chunk,
    ref string pending,
    ref string level,
    out bool finished) {
    finished = false;
    var text = pending + chunk;
    pending = "";
    var lastNewLine = text.LastIndexOf('\n');

    if (lastNewLine < 0) {
      pending = text;
      return [];
    }

    var complete = text[..(lastNewLine + 1)];
    pending = text[(lastNewLine + 1)..];
    var parts = complete.Split('\n');
    var lines = new List<PowerShellLogLine>();

    for (var i = 0; i < parts.Length - 1; i++) {
      var (shown, channel) = StripDecorations(parts[i].TrimEnd('\r'));

      if (shown.Equals(ScriptRunMarkers.FinishedLine, StringComparison.Ordinal)) {
        finished = true;
        continue;
      }

      var lineLevel = LevelOf(shown, channel, ref level);
      lines.Add(new PowerShellLogLine(shown, lineLevel));
    }

    return lines;
  }

  private static (string Text, string Channel) StripDecorations(string line) {
    var outputAt = line.IndexOf("[PS Output] ", StringComparison.Ordinal);
    var errorAt = line.IndexOf("[PS Error] ", StringComparison.Ordinal);

    if (outputAt >= 0 && (errorAt < 0 || outputAt <= errorAt))
      return (line[(outputAt + "[PS Output] ".Length)..], "Output");

    if (errorAt >= 0)
      return (line[(errorAt + "[PS Error] ".Length)..], "Error");

    var text = line;

    if (text.Length > 20 && text[4] == '-' && text[10] == 'T') {
      var space = text.IndexOf(' ');

      if (space > 0)
        text = text[(space + 1)..];
    }

    if (StartsWithLoggerLevel(text)) {
      var close = text.IndexOf("] ", StringComparison.Ordinal);

      if (close > 0)
        text = text[(close + 2)..];
    }

    return (text, "");
  }

  private static string LevelOf(string shown, string channel, ref string carry) {
    if (TryReadLevel(shown, out var level)) {
      carry = level;
      return level;
    }

    if (channel == "Error") {
      carry = "Error";
      return "Error";
    }

    if (carry.Length > 0)
      return carry;

    return "Info";
  }

  private static bool TryReadLevel(string text, out string level) {
    level = "";

    for (var open = 0; open < text.Length; open++) {
      if (text[open] != '[')
        continue;

      if (!TryReadLevelAt(text, open, out level))
        continue;

      return true;
    }

    return false;
  }

  private static bool TryReadLevelAt(string text, int open, out string level) {
    level = "";
    var close = text.IndexOf(']', open + 1);

    if (close < 0)
      return false;

    if (close + 1 < text.Length && text[close + 1] != ' ')
      return false;

    var name = text[(open + 1)..close];

    if (name is not ("Info" or "Success" or "Warning" or "Error"))
      return false;

    level = name;
    return true;
  }

  private static bool StartsWithLoggerLevel(string text) =>
    text.StartsWith("[Trace] ", StringComparison.Ordinal)
    || text.StartsWith("[Debug] ", StringComparison.Ordinal)
    || text.StartsWith("[Information] ", StringComparison.Ordinal)
    || text.StartsWith("[Warning] ", StringComparison.Ordinal)
    || text.StartsWith("[Error] ", StringComparison.Ordinal)
    || text.StartsWith("[Critical] ", StringComparison.Ordinal);

  private static int TrimPartialUtf8(byte[] buffer, int count) {
    if (count <= 0)
      return 0;

    var i = count - 1;
    var continuation = 0;

    while (i >= 0 && (buffer[i] & 0xC0) == 0x80) {
      continuation++;
      i--;

      if (continuation > 3)
        return count;
    }

    if (i < 0)
      return count;

    var lead = buffer[i];
    var needed = lead switch {
      >= 0xF0 and <= 0xF4 => 4,
      >= 0xE0 and <= 0xEF => 3,
      >= 0xC2 and <= 0xDF => 2,
      _ => 1
    };

    if (continuation + 1 < needed)
      return i;

    return count;
  }
}
