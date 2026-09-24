namespace CrestCore.Contracts;

/// What a review means for each imported Space, in the order they came, and
/// the pinned tabs that would move to the overflow folder.
public sealed record AnalyzedImportReview(IReadOnlyList<AnalyzedSpaceReview> Spaces, IReadOnlyList<Guid> OverflowTabIds);
