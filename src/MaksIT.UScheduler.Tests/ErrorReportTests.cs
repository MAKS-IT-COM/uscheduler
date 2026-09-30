using MaksIT.UScheduler.Shared;


namespace MaksIT.UScheduler.Tests;

public class ErrorReportTests {
  [Fact]
  public void Format_IncludesTypeMessageInnerAndStack() {
    Exception thrown;
    try {
      throw new InvalidOperationException("outer", new ArgumentException("inner"));
    }
    catch (Exception ex) {
      thrown = ex;
    }

    var text = ErrorReport.Format(thrown);
    Assert.Contains("UScheduler", text, StringComparison.Ordinal);
    Assert.Contains("MaksIT", text, StringComparison.Ordinal);
    Assert.Contains("InvalidOperationException", text, StringComparison.Ordinal);
    Assert.Contains("outer", text, StringComparison.Ordinal);
    Assert.Contains("--- inner ---", text, StringComparison.Ordinal);
    Assert.Contains("ArgumentException", text, StringComparison.Ordinal);
    Assert.Contains("inner", text, StringComparison.Ordinal);
    Assert.Contains(nameof(Format_IncludesTypeMessageInnerAndStack), text, StringComparison.Ordinal);
  }

  [Fact]
  public void Format_IncludesAggregateInners() {
    var error = new AggregateException(
      "batch",
      new InvalidOperationException("one"),
      new ArgumentException("two"));
    var text = ErrorReport.Format(error);
    Assert.Contains("AggregateException", text, StringComparison.Ordinal);
    Assert.Contains("one", text, StringComparison.Ordinal);
    Assert.Contains("two", text, StringComparison.Ordinal);
    Assert.Contains("--- aggregate ---", text, StringComparison.Ordinal);
  }
}
