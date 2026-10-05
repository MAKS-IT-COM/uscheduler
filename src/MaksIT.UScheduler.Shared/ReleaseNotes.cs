namespace MaksIT.UScheduler.Shared;

public sealed record ReleaseNote(string Version, IReadOnlyList<string> Added);

public static class ReleaseNotes {
  public const string ResourceName = "MaksIT.UScheduler.Shared.WHATSNEW.md";

  public static string Text() {
    using var stream = typeof(ReleaseNotes).Assembly.GetManifestResourceStream(ResourceName);

    if (stream is null)
      return "";

    using var reader = new StreamReader(stream);

    return reader.ReadToEnd();
  }

  public static IReadOnlyList<ReleaseNote> AddedSince(string markdown, string? seenVersion, string currentVersion) {
    if (!TryParse(currentVersion, out var current))
      return [];

    var seenKnown = TryParse(seenVersion, out var seen);

    if (seenKnown && seen >= current)
      return [];

    var matches = new List<ReleaseNote>();

    foreach (var section in Parse(markdown)) {
      if (section.Number > current || section.Added.Count == 0)
        continue;

      if (!seenKnown) {
        if (section.Number != current)
          continue;
      }
      else if (section.Number <= seen)
        continue;

      matches.Add(new ReleaseNote(section.Text, section.Added));
    }

    matches.Sort((left, right) => {
      TryParse(right.Version, out var newer);
      TryParse(left.Version, out var older);

      return newer.CompareTo(older);
    });

    return matches;
  }

  private static List<ParsedSection> Parse(string markdown) {
    var sections = new List<ParsedSection>();
    ParsedSection? current = null;
    var inAdded = false;

    foreach (var raw in markdown.Split('\n')) {
      var line = raw.TrimEnd('\r').Trim();

      if (line.StartsWith("## ", StringComparison.Ordinal)) {
        if (current is not null)
          sections.Add(current);

        current = null;
        inAdded = false;

        if (!TryHeading(line, out var text, out var number))
          continue;

        current = new ParsedSection(text, number);
        inAdded = true;

        continue;
      }

      if (current is null)
        continue;

      if (line.StartsWith("### ", StringComparison.Ordinal)) {
        inAdded = line.Equals("### Added", StringComparison.OrdinalIgnoreCase);

        continue;
      }

      if (inAdded && line.StartsWith("- ", StringComparison.Ordinal))
        current.Added.Add(line[2..].Trim());
    }

    if (current is not null)
      sections.Add(current);

    return sections;
  }

  private static bool TryHeading(string line, out string text, out Version number) {
    text = "";
    number = new Version();

    if (!line.StartsWith("## [", StringComparison.Ordinal))
      return false;

    var end = line.IndexOf(']', 4);

    if (end < 0)
      return false;

    text = line[4..end];

    if (text.Equals("Unreleased", StringComparison.OrdinalIgnoreCase))
      return false;

    return TryParse(text, out number);
  }

  private static bool TryParse(string? version, out Version number) {
    number = new Version();

    if (string.IsNullOrWhiteSpace(version))
      return false;

    var text = version.Trim();
    var plus = text.IndexOf('+', StringComparison.Ordinal);

    if (plus >= 0)
      text = text[..plus];

    return Version.TryParse(text, out number!);
  }

  private sealed class ParsedSection(string text, Version number) {
    public string Text { get; } = text;

    public Version Number { get; } = number;

    public List<string> Added { get; } = [];
  }
}
