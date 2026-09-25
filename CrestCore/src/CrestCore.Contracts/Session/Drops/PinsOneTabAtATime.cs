namespace CrestCore.Contracts;

/// Several tabs, or a folder, would drop among the pinned tabs, which take tabs
/// one at a time.
public sealed record PinsOneTabAtATime : Rejection {
    #region Variables

    /// What the person is told.
    [Localized]
    public string Message => "Drag one tab at a time to pin it.";

    #endregion
}
