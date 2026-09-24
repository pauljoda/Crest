namespace CrestCore.Contracts;

/// Removes the history entries of a Space last visited from `Start` up to,
/// but not including, `End`. A range that ends before it starts is refused
/// with `InvalidDateRange`.
public sealed record RemoveHistoryRange(Guid WorkspaceId, Guid SpaceId, DateTimeOffset Start, DateTimeOffset End)
    : SessionIntent(WorkspaceId);
