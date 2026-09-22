namespace CrestCore.Domain;

/// What the current review choices mean, per imported Space in review order:
/// tabs its destination already holds and destination tabs they match, plus
/// the pinned tabs that exceed their destination's pinned limit.
public sealed record ImportReviewAnalysis(IReadOnlyList<IReadOnlyList<Guid>> DuplicateTabIds,
    IReadOnlyList<IReadOnlyList<Guid>> MatchedDestinationTabIds, IReadOnlyList<Guid> OverflowTabIds);
