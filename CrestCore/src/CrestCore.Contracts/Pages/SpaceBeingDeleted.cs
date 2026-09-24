namespace CrestCore.Contracts;

/// The Space is being deleted, so nothing new may live in its profile.
public sealed record SpaceBeingDeleted(Guid SpaceId) : Rejection {
    #region Variables

    /// What the person is told.
    [Localized]
    public string Message => "That Space is being deleted.";

    #endregion
}
