using CrestCore.Application;
using CrestCore.Domain;

namespace CrestCore.Contracts;

/// Sets whether the Sub-Spaces of a Space's group each show the pinned tabs
/// stored in them, or all show the primary's, which reaches the person's other
/// devices with the time they chose. Nothing moves either way: each Space keeps
/// the pins stored in it.
public sealed record SetSeparatePinnedTabs(Guid WorkspaceId, Guid SpaceId, bool Separates) : SessionIntent(WorkspaceId) {
    #region Actions - Session

    internal override SessionEdit? Edit(NativeSessionAuthority workspace, SessionTurn turn) {
        workspace.RequireOwnedSpaces();
        var space = workspace.Editable(turn.Basis, SpaceId);
        if (space.Settings.SeparatesPinnedTabs == Separates) return new(turn.Basis, SyncStaging.Edit);
        var edited = space.Configured(space.Settings with { SeparatesPinnedTabs = Separates, SeparatesPinnedTabsModifiedAt = SpaceSettings.Chosen(space.Settings.SeparatesPinnedTabsModifiedAt, turn.Now) });
        return new(turn.Basis.Sharing(edited, GroupSetting.PinnedTabs), SyncStaging.Edit);
    }

    #endregion
}
