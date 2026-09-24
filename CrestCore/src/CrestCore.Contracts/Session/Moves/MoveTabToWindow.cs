namespace CrestCore.Contracts;

/// Moves a tab from the window `WindowId` to the window
/// `DestinationWindowId`, which then shows it in its Space.
///
/// When both windows show this workspace the tab stays where it is. When the
/// destination shows another workspace, one that borrows this one's Space or
/// whose Space this one borrows, the tab leaves this workspace and joins that
/// one's open tabs after the tab its window shows. Both workspaces change
/// together, the one that keeps a file saved with its sync journal before the
/// intent returns, or neither changes; the window the tab left shows the tab
/// it showed before. Refused with `WindowNotOpen` for a destination window
/// that is gone, `PrivateWorkspaceBoundary` between private and other
/// browsing, `UnrelatedWorkspaces` for workspaces that share no Space,
/// `UnknownSpace` when the destination does not hold the tab's Space,
/// `TabAlreadyExists` when it holds the tab, and `TabLimitReached`.
public sealed record MoveTabToWindow(Guid WorkspaceId, Guid WindowId, Guid SpaceId, Guid TabId, Guid DestinationWindowId)
    : SessionIntent(WorkspaceId);
