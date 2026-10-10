namespace MaksIT.UScheduler.Shared;

public static class ReleaseNotes {
  public const string ResourceName = "MaksIT.UScheduler.Shared.WHATSNEW.md";

  public static string Text() {
    using var stream = typeof(ReleaseNotes).Assembly.GetManifestResourceStream(ResourceName);

    if (stream is null)
      return "";

    using var reader = new StreamReader(stream);

    return reader.ReadToEnd();
  }

  public static IReadOnlyList<MaksIT.Core.Desktop.ReleaseNote> AddedSince(
    string markdown,
    string? seenVersion,
    string currentVersion) =>
    MaksIT.Core.Desktop.ReleaseNotes.AddedSince(markdown, seenVersion, currentVersion);
}
