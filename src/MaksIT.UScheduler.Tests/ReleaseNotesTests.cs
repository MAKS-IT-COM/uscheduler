using MaksIT.UScheduler.Shared;


namespace MaksIT.UScheduler.Tests;

public class ReleaseNotesTests {
  private const string Sample = """
    ## [Unreleased]

    ### Added

    - Helm Charts lists installed chart versions.

    ## [1.3.0] - 2026-09-30

    ### Added

    - An unhandled error opens a window you can copy.

    ### Changed

    - The desktop program is the scheduler.

    ## [1.2.0] - 2026-09-21

    ### Added

    - Windows setup offers Standard or Portable.
    """;

  [Fact]
  public void Current_version_hides_unreleased_and_older_notes() {
    var notes = ReleaseNotes.AddedSince(Sample, seenVersion: null, currentVersion: "1.3.0");

    var note = Assert.Single(notes);
    Assert.Equal("1.3.0", note.Version);
    Assert.Contains("An unhandled error opens a window you can copy.", note.Added);
    Assert.DoesNotContain(note.Added, line => line.Contains("Helm", StringComparison.Ordinal));
    Assert.DoesNotContain(note.Added, line => line.Contains("Portable", StringComparison.Ordinal));
    Assert.DoesNotContain(note.Added, line => line.Contains("scheduler", StringComparison.Ordinal));
  }

  [Fact]
  public void Skipped_versions_are_listed_newest_first() {
    var notes = ReleaseNotes.AddedSince(Sample, seenVersion: "1.1.0", currentVersion: "1.3.0");

    Assert.Equal(["1.3.0", "1.2.0"], notes.Select(note => note.Version));
  }

  [Fact]
  public void Same_or_newer_seen_version_has_nothing_to_show() {
    Assert.Empty(ReleaseNotes.AddedSince(Sample, "1.3.0", "1.3.0"));
    Assert.Empty(ReleaseNotes.AddedSince(Sample, "1.4.0", "1.3.0"));
  }

  [Fact]
  public void Shipped_notes_keep_older_work_out_of_the_current_version() {
    var notes = ReleaseNotes.AddedSince(ReleaseNotes.Text(), seenVersion: null, currentVersion: "1.5.0");

    var note = Assert.Single(notes);
    Assert.Equal("1.5.0", note.Version);
    Assert.Contains(note.Added, line => line.Contains("Processes", StringComparison.Ordinal));
    Assert.DoesNotContain(note.Added, line => line.Contains("What's New", StringComparison.Ordinal));
    Assert.DoesNotContain(note.Added, line => line.Contains("logs folder", StringComparison.Ordinal));
    Assert.DoesNotContain(note.Added, line => line.Contains("Portable", StringComparison.Ordinal));
    Assert.DoesNotContain(note.Added, line => line.Contains("grayed out", StringComparison.Ordinal));
  }

  [Fact]
  public void Version_bullets_skip_a_technical_heading() {
    const string markdown = """
      ## [1.3.0] - 2026-09-30

      - An unhandled error opens a window you can copy.

      ### Changed

      - The window footer is a separate control.
      """;

    var notes = ReleaseNotes.AddedSince(markdown, seenVersion: null, currentVersion: "1.3.0");

    var note = Assert.Single(notes);
    Assert.Equal(["An unhandled error opens a window you can copy."], note.Added);
  }
}
