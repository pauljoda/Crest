namespace CrestCore.Contracts;

/// Only a page can join a split or keep its page loaded, and a Start Page or
/// a native view is not one.
public sealed record WebPagesOnly(Guid TabId) : Rejection {
    #region Variables

    /// What the person is told.
    [Localized]
    public string Message => "This action requires webpage tabs. Deselect built-in pages first.";

    #endregion
}
