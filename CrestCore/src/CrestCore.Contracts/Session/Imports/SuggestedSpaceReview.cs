namespace CrestCore.Contracts;

/// The starting review for the imported Space `SourceSpaceId`: the existing
/// Space it joins, or none for a new Space, its tabs that Space already holds,
/// and the tabs it brings.
public sealed record SuggestedSpaceReview(Guid SourceSpaceId, Guid? DestinationId, IReadOnlyList<Guid> DuplicateTabIds,
    IReadOnlyList<Guid> IncludedTabIds);
