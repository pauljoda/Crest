namespace CrestCore.Contracts;

/// <summary>
/// A Space: one browsing profile with its <see cref="Settings"/>, its tabs, folders
/// and split metadata, and the history and archive it keeps. Space and profile are
/// one to one.
/// </summary>
public sealed record SpaceState(
    Guid Id,
    Guid ProfileId,
    SpaceSettings Settings,
    IReadOnlyList<FolderState> Folders,
    IReadOnlyList<TabState> Tabs,
    IReadOnlyList<SplitGroupState> SplitGroups,
    IReadOnlyList<ArchivedTabState> ArchivedTabs,
    IReadOnlyList<HistoryEntryState> History) {
    #region Types

    /// An outline with the lists it was resolved from.
    private sealed class ResolvedSidebar(IReadOnlyList<TabState> tabs, IReadOnlyList<FolderState> folders, SidebarOutline outline) {
        public SidebarOutline? Outline(IReadOnlyList<TabState> currentTabs, IReadOnlyList<FolderState> currentFolders) =>
            ReferenceEquals(tabs, currentTabs) && ReferenceEquals(folders, currentFolders) ? outline : null;
    }

    #endregion

    #region Variables

    /// <summary>What the Space's sidebar lists, resolved from its tabs and folders. It is
    /// resolved once for the lists it reads; a copy made with <c>with</c> keeps it only
    /// while it holds the same tab and folder lists.</summary>
    [Resolved]
    public SidebarOutline Sidebar {
        get {
            if (sidebar?.Outline(Tabs, Folders) is { } outline) return outline;
            var resolved = SidebarOutline.Of(Tabs, Folders);
            sidebar = new ResolvedSidebar(Tabs, Folders, resolved);
            return resolved;
        }
    }

    private ResolvedSidebar? sidebar;

    #endregion

    #region Actions - Equality

    public bool Equals(SpaceState? other) => other is not null
        && Id == other.Id
        && ProfileId == other.ProfileId
        && Settings == other.Settings
        && Folders.SequenceEqual(other.Folders)
        && Tabs.SequenceEqual(other.Tabs)
        && SplitGroups.SequenceEqual(other.SplitGroups)
        && ArchivedTabs.SequenceEqual(other.ArchivedTabs)
        && History.SequenceEqual(other.History);

    public override int GetHashCode() => HashCode.Combine(Id, ProfileId, Settings.Name, Tabs.Count, Settings.AccessPolicy);

    #endregion
}
