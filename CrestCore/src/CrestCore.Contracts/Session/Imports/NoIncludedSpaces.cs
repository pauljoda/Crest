namespace CrestCore.Contracts;

/// A reviewed import includes none of its Spaces.
public sealed record NoIncludedSpaces : Rejection {
    #region Variables

    /// What the person is told.
    [Localized]
    public string Message => "Choose at least one Space to import.";

    #endregion
}
