namespace CrestCore.Contracts;

/// Copies a tab into `Placement`'s section, or among the open tabs when null,
/// with an identity the core gives it, published as `TabCopied`. When
/// `Shows`, the window that asked shows the copy and its Space. `Source` is
/// TRANSITIONAL until WP C slice (c) keeps each page's live state in `Pages`:
/// it says what the source's page shows now, which the copy starts from.
public sealed record DuplicateTab(Guid WorkspaceId, Guid WindowId, Guid SpaceId, Guid TabId, TabPlacement? Placement, bool Shows,
    SourcePage? Source) : SessionIntent(WorkspaceId);
