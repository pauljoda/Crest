namespace CrestCore.Contracts;

/// The Space already holds `Limit` custom search engines.
public sealed record SearchEngineLimitReached(int Limit) : Rejection {
    #region Variables

    /// What the engine editor tells the person.
    [Localized(Argument = nameof(Limit))]
    public string Message => "A Space can contain up to %lld custom search engines.";

    #endregion
}
