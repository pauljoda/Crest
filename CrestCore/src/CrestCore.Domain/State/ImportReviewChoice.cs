namespace CrestCore.Domain;

/// What the person chose for one imported Space: whether it is imported, into
/// which existing Space (null for a new one), which tabs, and any placement
/// they changed.
public sealed record ImportReviewChoice(bool Included, Guid? DestinationId, IReadOnlySet<Guid> IncludedTabIds,
    IReadOnlyDictionary<Guid, TabPlacement> Placements);
