namespace CrestCore.Contracts;

/// Its owner released a page, which is gone.
public sealed record PageRemoved(Guid PageId) : Change;
