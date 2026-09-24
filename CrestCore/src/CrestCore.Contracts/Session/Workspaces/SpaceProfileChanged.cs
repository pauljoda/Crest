namespace CrestCore.Contracts;

/// The Space no longer uses the profile the intent names.
public sealed record SpaceProfileChanged(Guid SpaceId) : Rejection {
    #region Variables

    /// What the person is told.
    [Localized]
    public string Message => "That Space is no longer available.";

    #endregion
}
