namespace CrestCore.Contracts;

/// The Space is locked, and this process holds no grant to read or change it.
public sealed record SpaceLocked(Guid SpaceId) : Rejection {
    #region Variables

    /// What the person is told.
    [Localized]
    public string Message => "The Space is locked or no longer active. Unlock it and select the tabs again.";

    #endregion
}
