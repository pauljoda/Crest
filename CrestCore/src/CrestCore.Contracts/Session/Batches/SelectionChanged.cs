namespace CrestCore.Contracts;

/// The selection is not what the window saw: the window no longer shows its
/// Space, or a selected tab or folder is gone, or its folders hold other tabs.
public sealed record SelectionChanged : Rejection {
    #region Variables

    /// What the person is told.
    [Localized]
    public string Message => "The selected items changed. Select them again before continuing.";

    #endregion
}
