namespace CrestCore.Contracts;

/// Copies a tab into `Placement`'s section, or among the open tabs when null,
/// with an identity the core gives it, published as `TabCopied`. A copy of a
/// web page starts from where the source's page is now. When `Shows`, the
/// window that asked shows the copy and its Space.
public sealed record DuplicateTab(Guid WorkspaceId, Guid WindowId, Guid SpaceId, Guid TabId, TabPlacement? Placement, bool Shows)
    : SessionIntent(WorkspaceId);
