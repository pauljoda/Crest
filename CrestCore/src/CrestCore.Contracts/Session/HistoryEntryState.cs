namespace CrestCore.Contracts;

/// <summary>One address in a Space's history, with its first and latest visit.</summary>
public sealed record HistoryEntryState(Guid Id, string Url, string Title, DateTimeOffset FirstVisitedAt,
    DateTimeOffset LastVisitedAt, int VisitCount);
