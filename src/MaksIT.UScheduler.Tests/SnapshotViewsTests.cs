using MaksIT.UScheduler.UI.Services;


namespace MaksIT.UScheduler.Tests;

public class SnapshotViewsTests {
  [Fact]
  public void Empty_request_is_every_screen() {
    var views = SnapshotViews.Resolve([]);

    Assert.Equal(SnapshotViews.All, views);
  }

  [Fact]
  public void Requested_ids_stay_in_order() {
    var views = SnapshotViews.Resolve(["settings", "main"]);

    Assert.Equal(["settings", "main"], views);
  }

  [Theory]
  [InlineData("main", true)]
  [InlineData("Script-Logs", true)]
  [InlineData("processes", true)]
  [InlineData("chat", false)]
  public void Known_ids_match_ignoring_case(string id, bool known) {
    Assert.Equal(known, SnapshotViews.IsKnown(id));
  }
}
