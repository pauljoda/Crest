namespace CrestCore.Contracts;

/// Adds a tab to the split of `TargetTabId`, or makes the two a split, at
/// member `Index` or after the others. A saved or pinned tab stays where it is
/// and an open copy joins in its place, with an identity the core gives it,
/// showing what `SourcePages` says its source's page shows; each copy is
/// published as `TabCopied`. The window that asked shows the joined tab in its
/// Space. `SourcePages` is TRANSITIONAL until WP C slice (c); see `SourcePage`.
public sealed record JoinSplit(Guid WorkspaceId, Guid WindowId, Guid SpaceId, Guid TabId, Guid TargetTabId, int? Index,
    IReadOnlyList<SourcePage> SourcePages) : SessionIntent(WorkspaceId);
