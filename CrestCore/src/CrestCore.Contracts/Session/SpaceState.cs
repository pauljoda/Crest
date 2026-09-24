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
