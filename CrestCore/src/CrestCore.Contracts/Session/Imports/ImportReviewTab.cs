namespace CrestCore.Contracts;

/// A tab as the review of an import reads it.
public sealed record ImportReviewTab(Guid Id, string? Url, TabPlacement Placement);
