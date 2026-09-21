namespace CrestCore.Domain;

public sealed record HistoryVisit(Guid Id, string Url, string Title, DateTimeOffset FirstVisitedAt,
    DateTimeOffset VisitedAt, int VisitCount);
