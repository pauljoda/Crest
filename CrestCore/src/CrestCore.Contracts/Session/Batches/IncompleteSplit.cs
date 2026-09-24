namespace CrestCore.Contracts;

/// The selection holds some members of the split `GroupId` and not the rest.
public sealed record IncompleteSplit(Guid GroupId) : Rejection {
    #region Variables

    /// What the person is told.
    [Localized]
    public string Message => "The split changed. Select the whole group again.";

    #endregion
}
