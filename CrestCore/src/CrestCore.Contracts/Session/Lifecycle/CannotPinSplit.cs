namespace CrestCore.Contracts;

/// The tab is in a split, and the section it would move to holds no splits,
/// so it moves only by leaving its split.
public sealed record CannotPinSplit(Guid TabId) : Rejection {
    #region Variables

    /// What the person is told.
    [Localized]
    public string Message => "Split View groups cannot be pinned. Separate the split first.";

    #endregion
}
