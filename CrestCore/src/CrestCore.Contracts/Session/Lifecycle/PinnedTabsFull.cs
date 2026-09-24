namespace CrestCore.Contracts;

/// The Space already pins `Capacity` tabs, so it pins no more.
public sealed record PinnedTabsFull(int Capacity) : Rejection {
    #region Variables

    /// What the person is told.
    [Localized(Argument = nameof(Capacity))]
    public string Message => "A Space can hold up to %lld pinned tabs. Unpin tabs or select fewer tabs.";

    #endregion
}
