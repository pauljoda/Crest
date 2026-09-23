namespace CrestCore.Contracts;

/// <summary>A tab in its Space's archive, when it arrived there and why.</summary>
public sealed record ArchivedTabState(TabState Tab, DateTimeOffset ArchivedAt, ArchiveReason Reason);
