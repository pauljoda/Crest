using CrestCore.Contracts;

namespace CrestCore.Domain;

/// A rule the browser's state keeps, which a `BrowserRuleException` names when
/// something breaks it. A rule the sync journal keeps also says what breaking
/// it means for sync: reading the cloud's records and staging this device's
/// session share the journal's rules, and each answers them its own way.
public sealed class BrowserRule {
    #region Static Variables

    public static readonly BrowserRule AccessAlreadyAttached = new("access_already_attached");
    public static readonly BrowserRule BorrowedProfileRequiresOwner = new("borrowed_profile_requires_owner");
    public static readonly BrowserRule DuplicateSyncRecord = new("duplicate_sync_record", recordFlaw: SyncRecordFlaw.DuplicateRecord);
    public static readonly BrowserRule InvalidAddress = new("invalid_address");
    public static readonly BrowserRule InvalidDeletionIntent = new("invalid_deletion_intent");
    public static readonly BrowserRule InvalidFolderTree = new("invalid_folder_tree", recordFlaw: SyncRecordFlaw.InvalidFolderHierarchy);
    public static readonly BrowserRule InvalidHistoryRange = new("invalid_history_range");
    public static readonly BrowserRule InvalidHistoryVisit = new("invalid_history_visit");
    public static readonly BrowserRule InvalidIdentity = new("invalid_identity", recordFlaw: SyncRecordFlaw.MalformedRecord);
    public static readonly BrowserRule InvalidNativeKind = new("invalid_native_kind");
    public static readonly BrowserRule InvalidRecordDate = new("invalid_record_date");
    public static readonly BrowserRule InvalidRecoveryIdentity = new("invalid_recovery_identity");
    public static readonly BrowserRule InvalidRetentionInterval = new("invalid_retention_interval");
    public static readonly BrowserRule InvalidSavedDate = new("invalid_saved_date", recordFlaw: SyncRecordFlaw.MalformedRecord);
    public static readonly BrowserRule InvalidSavedIdentity = new("invalid_saved_identity", recordFlaw: SyncRecordFlaw.MalformedRecord);
    public static readonly BrowserRule InvalidSavedState = new("invalid_saved_state", recordFlaw: SyncRecordFlaw.MalformedRecord);
    public static readonly BrowserRule InvalidSavedUrl = new("invalid_saved_url", recordFlaw: SyncRecordFlaw.MalformedRecord);
    public static readonly BrowserRule InvalidSessionTransaction = new("invalid_session_transaction");
    public static readonly BrowserRule InvalidShortcut = new("invalid_shortcut");
    public static readonly BrowserRule InvalidSplit = new("invalid_split");
    public static readonly BrowserRule InvalidSyncDate = new("invalid_sync_date", recordFlaw: SyncRecordFlaw.MalformedRecord);
    public static readonly BrowserRule InvalidSyncDeletion = new("invalid_sync_deletion", recordFlaw: SyncRecordFlaw.MalformedRecord);
    public static readonly BrowserRule InvalidSyncKind = new("invalid_sync_kind", recordFlaw: SyncRecordFlaw.MalformedRecord);
    public static readonly BrowserRule InvalidSyncPending = new("invalid_sync_pending");
    public static readonly BrowserRule InvalidSyncPlacement = new("invalid_sync_placement", recordFlaw: SyncRecordFlaw.MalformedRecord);
    public static readonly BrowserRule InvalidSyncRecord = new("invalid_sync_record", recordFlaw: SyncRecordFlaw.MalformedRecord);
    public static readonly BrowserRule InvalidSyncSessionOwner = new("invalid_sync_session_owner");
    public static readonly BrowserRule InvalidSyncTransaction = new("invalid_sync_transaction");
    public static readonly BrowserRule InvalidTabContent = new("invalid_tab_content");
    public static readonly BrowserRule InvalidTerminationCount = new("invalid_termination_count");
    public static readonly BrowserRule NotBorrowedWorkspace = new("not_borrowed_workspace");
    public static readonly BrowserRule ProfileLeaseRevoked = new("profile_lease_revoked");
    public static readonly BrowserRule SessionReleased = new("session_released");
    public static readonly BrowserRule SessionTransactionInProgress = new("session_transaction_in_progress");
    public static readonly BrowserRule StaleBorrowedSource = new("stale_borrowed_source");
    /// The journal has issued every version it can.
    public static readonly BrowserRule SyncClockExhausted = new("sync_clock_exhausted", stagingFailure: SyncStagingFailure.ClockExhausted);
    public static readonly BrowserRule SyncIdentityMismatch = new("sync_identity_mismatch", recordFlaw: SyncRecordFlaw.IdentityMismatch);
    /// More records than sync carries: too many in the cloud's batch, or in
    /// the session a stage writes.
    public static readonly BrowserRule SyncRecordLimit = new("sync_record_limit", recordFlaw: SyncRecordFlaw.TooManyRecords,
        stagingFailure: SyncStagingFailure.TooLarge);
    /// A journal larger than sync keeps.
    public static readonly BrowserRule SyncSizeLimit = new("sync_size_limit", stagingFailure: SyncStagingFailure.TooLarge);
    public static readonly BrowserRule SyncTransactionNotSealed = new("sync_transaction_not_sealed");
    public static readonly BrowserRule UnknownCurrentTab = new("unknown_current_tab");
    public static readonly BrowserRule UnknownFolder = new("unknown_folder");
    public static readonly BrowserRule UnsupportedUrl = new("unsupported_url");
    public static readonly BrowserRule VersionMismatch = new("version_mismatch");

    public static IReadOnlyList<BrowserRule> All { get; } = [
        AccessAlreadyAttached, BorrowedProfileRequiresOwner, DuplicateSyncRecord, InvalidAddress, InvalidDeletionIntent, InvalidFolderTree,
        InvalidHistoryRange, InvalidHistoryVisit, InvalidIdentity, InvalidNativeKind, InvalidRecordDate, InvalidRecoveryIdentity,
        InvalidRetentionInterval, InvalidSavedDate, InvalidSavedIdentity, InvalidSavedState, InvalidSavedUrl, InvalidSessionTransaction,
        InvalidShortcut, InvalidSplit, InvalidSyncDate, InvalidSyncDeletion, InvalidSyncKind, InvalidSyncPending, InvalidSyncPlacement,
        InvalidSyncRecord, InvalidSyncSessionOwner, InvalidSyncTransaction, InvalidTabContent, InvalidTerminationCount,
        NotBorrowedWorkspace, ProfileLeaseRevoked, SessionReleased, SessionTransactionInProgress, StaleBorrowedSource,
        SyncClockExhausted, SyncIdentityMismatch, SyncRecordLimit, SyncSizeLimit, SyncTransactionNotSealed, UnknownCurrentTab,
        UnknownFolder, UnsupportedUrl, VersionMismatch
    ];

    #endregion

    #region Variables

    /// The rule's stable spelling, which a failure's message carries.
    public string Code { get; }

    /// What the cloud's records are when reading them breaks the rule, or
    /// null when the rule names no flaw of theirs. Records that break a rule
    /// naming none are refused as a staging failure where the rule names one,
    /// and as unexpected otherwise.
    public SyncRecordFlaw? RecordFlaw { get; }

    /// Why a stage of this device's session fails when it breaks the rule,
    /// or null when breaking it means the session is one sync cannot carry.
    public SyncStagingFailure? StagingFailure { get; }

    #endregion

    #region Constructors

    private BrowserRule(string code, SyncRecordFlaw? recordFlaw = null, SyncStagingFailure? stagingFailure = null) {
        Code = code;
        RecordFlaw = recordFlaw;
        StagingFailure = stagingFailure;
    }

    #endregion
}
