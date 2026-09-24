namespace CrestCore.Contracts;

/// The workspace already holds `Limit` Spaces, or would hold more.
public sealed record SpaceLimitReached(int Limit) : Rejection {
    #region Variables

    /// What the person is told.
    [Localized(Argument = nameof(Limit))]
    public string Message => "Crest supports up to %lld Spaces.";

    #endregion
}
