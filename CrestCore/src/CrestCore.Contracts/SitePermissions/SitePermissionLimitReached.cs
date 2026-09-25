namespace CrestCore.Contracts;

/// This device already keeps `Limit` saved site permission choices.
public sealed record SitePermissionLimitReached(int Limit) : Rejection {
    #region Variables

    /// What the person is told.
    [Localized(Argument = nameof(Limit))]
    public string Message => "Crest can keep up to %lld saved site permissions. Reset some to save more.";

    #endregion
}
