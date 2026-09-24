namespace CrestCore.Contracts;

/// The selection holds folders, which only filing and keeping pages loaded act on.
public sealed record SelectionHoldsFolders : Rejection {
    #region Variables

    /// What the person is told.
    [Localized]
    public string Message =>
        "Move selected folders into saved or current tabs, or another folder. Use a folder’s own menu for other folder actions.";

    #endregion
}
