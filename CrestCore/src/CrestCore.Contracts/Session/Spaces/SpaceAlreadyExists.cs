namespace CrestCore.Contracts;

/// The workspace already holds a Space with this identity.
public sealed record SpaceAlreadyExists(Guid SpaceId) : Rejection {
    #region Variables

    /// What the person is told.
    [Localized]
    public string Message => "That Space already exists.";

    #endregion
}
