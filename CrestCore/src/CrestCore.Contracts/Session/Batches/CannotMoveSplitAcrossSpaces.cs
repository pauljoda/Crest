namespace CrestCore.Contracts;

/// The tab is in a split, and a split stays in its Space.
public sealed record CannotMoveSplitAcrossSpaces(Guid TabId) : Rejection {
    #region Variables

    /// What the person is told.
    [Localized]
    public string Message => "Split View groups stay in their Space. Separate the split before moving it to another Space.";

    #endregion
}
