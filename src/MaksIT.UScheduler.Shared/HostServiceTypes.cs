namespace MaksIT.UScheduler.Shared;


public record HostServiceOperationResult(bool Success, string Message);

public readonly record struct SeedCopyResult(int CopiedFiles, int SkippedItems);

public enum HostServiceStatus {
  NotInstalled,
  Stopped,
  StartPending,
  StopPending,
  Running,
  ContinuePending,
  PausePending,
  Paused,
  Unknown
}
