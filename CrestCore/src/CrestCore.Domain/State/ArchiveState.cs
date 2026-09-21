namespace CrestCore.Domain;

public sealed record ArchiveState(TabState Tab, DateTimeOffset ClosedAt, string Reason);
