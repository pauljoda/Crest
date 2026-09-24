namespace CrestCore.Contracts;

/// Deleting the Space would leave the workspace without one.
public sealed record CannotDeleteLastSpace() : Rejection {
    #region Variables

    /// What the person is told.
    [Localized]
    public string Message => "Crest needs at least one Space.";

    #endregion
}
