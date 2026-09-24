using CrestCore.Contracts;

namespace CrestCore.Application;

/// How an accepted revision reaches the sync journal: why the records it
/// removed are deleted, and how soon it stages.
internal sealed record SyncStaging(SyncDeletionReason Reason, SyncUrgency Urgency) {
    #region Variables

    /// A launch stages the session it loaded; what the file lost while the app
    /// was closed was removed by retention.
    public static SyncStaging Launch { get; } = new(SyncDeletionReason.Retention, SyncUrgency.Immediate);

    /// A window showed a tab, which records when it was used.
    public static SyncStaging TabUse { get; } = new(SyncDeletionReason.Superseded, SyncUrgency.Coalesced);

    /// A tab moved between workspaces.
    public static SyncStaging Transfer { get; } = new(SyncDeletionReason.Superseded, SyncUrgency.WithSave);

    #endregion
}
