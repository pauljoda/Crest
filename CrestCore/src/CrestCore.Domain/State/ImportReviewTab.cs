namespace CrestCore.Domain;

/// A tab as the import review sees it: identity, address and placement.
public sealed record ImportReviewTab(Guid Id, string? Url, TabPlacement Placement);
