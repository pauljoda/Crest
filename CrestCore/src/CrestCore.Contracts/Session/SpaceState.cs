namespace CrestCore.Contracts;

/// <summary>
/// A Space: one browsing profile with its name, look and preferences, its tabs,
/// folders and split metadata, and the history and archive it keeps. Space and
/// profile are one to one. <see cref="Branding"/> is null for a Space stored before
/// branding existed; the native reader derives that look from the accent and symbol.
/// </summary>
public sealed record SpaceState(
    Guid Id,
    Guid ProfileId,
    string Name,
    string Symbol,
    SpaceAccent Accent,
    SpaceBranding? Branding,
    IReadOnlyList<FolderState> Folders,
    IReadOnlyList<TabState> Tabs,
    IReadOnlyList<SplitGroupState> SplitGroups,
    IReadOnlyList<ArchivedTabState> ArchivedTabs,
    IReadOnlyList<HistoryEntryState> History,
    BrowsingPreferences BrowsingPreferences,
    CredentialPreferences CredentialPreferences,
    SpaceAccessPolicy AccessPolicy,
    bool IsSavedTabsExpanded,
    DateTimeOffset? SavedTabsExpansionModifiedAt) {
    #region Actions - Equality

    public bool Equals(SpaceState? other) => other is not null
        && Id == other.Id
        && ProfileId == other.ProfileId
        && Name == other.Name
        && Symbol == other.Symbol
        && Accent == other.Accent
        && Branding == other.Branding
        && Folders.SequenceEqual(other.Folders)
        && Tabs.SequenceEqual(other.Tabs)
        && SplitGroups.SequenceEqual(other.SplitGroups)
        && ArchivedTabs.SequenceEqual(other.ArchivedTabs)
        && History.SequenceEqual(other.History)
        && BrowsingPreferences == other.BrowsingPreferences
        && CredentialPreferences == other.CredentialPreferences
        && AccessPolicy == other.AccessPolicy
        && IsSavedTabsExpanded == other.IsSavedTabsExpanded
        && SavedTabsExpansionModifiedAt == other.SavedTabsExpansionModifiedAt;

    public override int GetHashCode() => HashCode.Combine(Id, ProfileId, Name, Tabs.Count, AccessPolicy);

    #endregion
}
