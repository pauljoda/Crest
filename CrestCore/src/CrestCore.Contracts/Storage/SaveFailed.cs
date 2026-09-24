namespace CrestCore.Contracts;

/// A save the intent had to finish before returning failed. Nothing was
/// published, and the file is as it was.
public sealed record SaveFailed(StorageFailure Reason) : Rejection {
    #region Variables

    /// What the person is told.
    [Localized]
    public string Message => "Crest couldn’t save this change. Try again.";

    #endregion
}
