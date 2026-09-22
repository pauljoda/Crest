namespace CrestCore.Domain;

/// The review a person starts from for one imported Space: the existing Space
/// with the same name, the tabs it already holds, and the tabs to import.
public sealed record ImportReviewSuggestion(Guid? DestinationId, IReadOnlyList<Guid> DuplicateTabIds,
    IReadOnlyList<Guid> IncludedTabIds);
