namespace CrestCore.Contracts;

/// What a person chose for the imported Space `SourceSpaceId`: whether it is
/// imported, the existing Space it joins or none for a new Space, the name and
/// look that Space takes, the tabs it brings, and the tabs that move to
/// another placement.
public sealed record SpaceReview(Guid SourceSpaceId, bool Included, Guid? DestinationId, SpaceCustomization Customization,
    IReadOnlyList<Guid> IncludedTabIds, IReadOnlyList<TabPlacementChoice> Placements);
