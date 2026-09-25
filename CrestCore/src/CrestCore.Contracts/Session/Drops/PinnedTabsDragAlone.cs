namespace CrestCore.Contracts;

/// The lift holds pinned tabs with saved or open tabs or folders, which move
/// apart.
public sealed record PinnedTabsDragAlone : Rejection {
    #region Variables

    /// What the person is told.
    [Localized]
    public string Message => "Pinned tabs cannot join a drag with saved or current tabs. Start the drag again.";

    #endregion
}
