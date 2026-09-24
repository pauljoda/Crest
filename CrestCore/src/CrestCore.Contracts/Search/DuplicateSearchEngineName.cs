namespace CrestCore.Contracts;

/// Another custom engine in the Space already uses this name, ignoring case and
/// diacritics.
public sealed record DuplicateSearchEngineName() : Rejection {
    #region Variables

    /// What the engine editor tells the person.
    [Localized]
    public string Message => "A custom search engine already uses this name.";

    #endregion
}
