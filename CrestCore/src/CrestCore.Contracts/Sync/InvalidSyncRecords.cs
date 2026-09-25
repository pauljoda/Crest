namespace CrestCore.Contracts;

/// The core cannot take the records the cloud sent, for the reason `Flaw`
/// names, about the record, tab, Space or profile `Subject` names when there is
/// one. Nothing changed.
public sealed record InvalidSyncRecords(SyncRecordFlaw Flaw, Guid? Subject) : Rejection {
    #region Variables

    /// What the person is told.
    [Localized]
    public string Message => "Crest couldn’t apply the latest changes from iCloud.";

    #endregion
}
