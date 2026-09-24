namespace CrestCore.Contracts;

/// What a review means for the imported Space `SourceSpaceId`: its tabs the
/// destination already holds, and the destination's tabs it matches when it is
/// included.
public sealed record AnalyzedSpaceReview(Guid SourceSpaceId, IReadOnlyList<Guid> DuplicateTabIds, IReadOnlyList<Guid> MatchedTabIds);
