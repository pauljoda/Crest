namespace CrestCore.Contracts;

/// The split would hold one tab, and a split holds two to `Limit` tabs.
public sealed record SplitNeedsTwoTabs(int Limit) : Rejection {
    #region Variables

    /// What the person is told.
    [Localized(Argument = nameof(Limit))]
    public string Message => "Split View needs 2 to %lld tabs. Select fewer tabs or use a smaller split.";

    #endregion
}
