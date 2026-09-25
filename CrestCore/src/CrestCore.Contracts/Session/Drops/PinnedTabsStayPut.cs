namespace CrestCore.Contracts;

/// Several pinned tabs would drop on another Space or the cards a window shows,
/// where pinned tabs move one at a time.
public sealed record PinnedTabsStayPut : Rejection {
    #region Variables

    /// What the person is told.
    [Localized]
    public string Message => "Move selected pinned tabs within their pinned area or into saved or current tabs.";

    #endregion
}
