namespace CrestCore.Contracts;

/// Opens `Address` as a new open tab, `TabId`, titled `Title`, and joins it to
/// the split of `TargetTabId` as `JoinSplit` does, copies included. The window
/// that asked shows the new tab.
public sealed record OpenLinkInSplit(Guid WorkspaceId, Guid WindowId, Guid SpaceId, Guid TabId, Guid TargetTabId,
    string Address, string Title) : SessionIntent(WorkspaceId);
