using CrestCore.Application;

namespace CrestCore.Contracts;

/// Collapses a split's tabs under its header in the sidebar, or expands them.
public sealed record CollapseSplit(Guid WorkspaceId, Guid SpaceId, Guid GroupId, bool IsCollapsed) : SessionIntent(WorkspaceId) {
    #region Actions - Session

    internal override SessionEdit? Edit(NativeSessionAuthority workspace, SessionTurn turn) =>
        workspace.Identifying(turn.Basis, SpaceId, GroupId, turn.Now, group => group with { IsCollapsed = IsCollapsed },
            (group, changedAt) => group with { CollapseModifiedAt = changedAt });

    #endregion
}
