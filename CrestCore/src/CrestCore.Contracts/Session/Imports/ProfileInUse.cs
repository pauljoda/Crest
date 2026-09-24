namespace CrestCore.Contracts;

/// Another Space already uses the profile `ProfileId`, and a profile belongs
/// to one Space.
public sealed record ProfileInUse(Guid ProfileId) : Rejection {
    #region Variables

    /// What the person is told.
    [Localized]
    public string Message => "Another Space already uses this Space’s browsing data.";

    #endregion
}
