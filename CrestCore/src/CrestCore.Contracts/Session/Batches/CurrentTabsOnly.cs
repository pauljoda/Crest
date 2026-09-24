namespace CrestCore.Contracts;

/// The tab is saved or pinned, and only open tabs are archived together.
public sealed record CurrentTabsOnly(Guid TabId) : Rejection {
    #region Variables

    /// What the person is told.
    [Localized]
    public string Message =>
        "Archive applies to current tabs. Use Unload Pages to close saved or pinned pages, or Delete Tabs to remove their saved entries.";

    #endregion
}
