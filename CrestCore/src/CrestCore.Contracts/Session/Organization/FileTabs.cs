namespace CrestCore.Contracts;

/// Moves tabs, in the order the Space holds them, into `FolderId` or to the
/// top level of `Placement`'s section, before the tab `BeforeTabId` or the
/// folder `BeforeFolderId` names. A split member brings its split along,
/// unless `LeavesSplits` takes it out.
public sealed record FileTabs(Guid WorkspaceId, Guid SpaceId, IReadOnlyList<Guid> TabIds, TabPlacement Placement, Guid? FolderId,
    Guid? BeforeTabId, Guid? BeforeFolderId, bool LeavesSplits) : SessionIntent(WorkspaceId);
