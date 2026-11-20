namespace CrestCore.Contracts;

#region Models

/// What a read model that starts late applies, as one batch of changes: each
/// download the core keeps, in its order, then the changes that asked the
/// questions still waiting on the person, oldest first.
public sealed record CaughtUp(IReadOnlyList<Change> Changes);

#endregion
