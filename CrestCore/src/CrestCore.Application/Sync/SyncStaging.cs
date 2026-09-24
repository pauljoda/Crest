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

    /// A page reported where a navigation landed or which icon it shows, or a
    /// tab took an address to load.
    public static SyncStaging PageReport { get; } = new(SyncDeletionReason.Superseded, SyncUrgency.Coalesced);

    /// A tab moved between workspaces.
    public static SyncStaging Transfer { get; } = new(SyncDeletionReason.Superseded, SyncUrgency.WithSave);

    /// The person deleted records: history, or a folder.
    public static SyncStaging Deletion { get; } = new(SyncDeletionReason.ExplicitDelete, SyncUrgency.Immediate);

    /// Records aged out under their Space's retention, or open tabs its
    /// cleanup archived.
    public static SyncStaging Expiry { get; } = new(SyncDeletionReason.Retention, SyncUrgency.Immediate);

    /// Something another device should see soon: a new folder or a restored tab.
    public static SyncStaging Creation { get; } = new(SyncDeletionReason.Superseded, SyncUrgency.Immediate);

    /// An organizing edit, staged once edits pause: a rename, a move or a split.
    public static SyncStaging Edit { get; } = new(SyncDeletionReason.Superseded, SyncUrgency.Coalesced);

    #endregion
}
