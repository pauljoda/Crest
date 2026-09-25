namespace CrestCore.Domain;

/// Stable browser rule error code identifiers exposed to native callers.
public static class BrowserRuleCodes {
    #region Variables

    public const string AccessAlreadyAttached = "access_already_attached";
    public const string BorrowedProfileRequiresOwner = "borrowed_profile_requires_owner";
    public const string DeletionRequiresCommand = "deletion_requires_command";
    public const string DuplicateMediaSession = "duplicate_media_session";
    public const string DuplicateResidencyCandidate = "duplicate_residency_candidate";
    public const string DuplicateShortcutCommand = "duplicate_shortcut_command";
    public const string DuplicateSyncRecord = "duplicate_sync_record";
    public const string InvalidAddress = "invalid_address";
    public const string InvalidDeletionIntent = "invalid_deletion_intent";
    public const string InvalidFocusedIndex = "invalid_focused_index";
    public const string InvalidFolderTree = "invalid_folder_tree";
    public const string InvalidHistoryRange = "invalid_history_range";
    public const string InvalidHistoryVisit = "invalid_history_visit";
    public const string InvalidIdentity = "invalid_identity";
    public const string InvalidMediaSessionCount = "invalid_media_session_count";
    public const string InvalidName = "invalid_name";
    public const string InvalidNativeKind = "invalid_native_kind";
    public const string InvalidPageCount = "invalid_page_count";
    public const string InvalidPlacement = "invalid_placement";
    public const string InvalidPresentedCandidate = "invalid_presented_candidate";
    public const string InvalidRecordDate = "invalid_record_date";
    public const string InvalidRecordOrder = "invalid_record_order";
    public const string InvalidRecoveryIdentity = "invalid_recovery_identity";
    public const string InvalidResidencyStamp = "invalid_residency_stamp";
    public const string InvalidRetention = "invalid_retention";
    public const string InvalidRetentionInterval = "invalid_retention_interval";
    public const string InvalidSavedDate = "invalid_saved_date";
    public const string InvalidSavedIdentity = "invalid_saved_identity";
    public const string InvalidSavedState = "invalid_saved_state";
    public const string InvalidSavedUrl = "invalid_saved_url";
    public const string InvalidSessionTransaction = "invalid_session_transaction";
    public const string InvalidShortcut = "invalid_shortcut";
    public const string InvalidSpaceCount = "invalid_space_count";
    public const string InvalidSpaceOrder = "invalid_space_order";
    public const string InvalidSplit = "invalid_split";
    public const string InvalidSyncDate = "invalid_sync_date";
    public const string InvalidSyncDeletion = "invalid_sync_deletion";
    public const string InvalidSyncKind = "invalid_sync_kind";
    public const string InvalidSyncPending = "invalid_sync_pending";
    public const string InvalidSyncPlacement = "invalid_sync_placement";
    public const string InvalidSyncRecord = "invalid_sync_record";
    public const string InvalidSyncSessionOwner = "invalid_sync_session_owner";
    public const string InvalidSyncTransaction = "invalid_sync_transaction";
    public const string InvalidTabContent = "invalid_tab_content";
    public const string InvalidTabCount = "invalid_tab_count";
    public const string InvalidTerminationCount = "invalid_termination_count";
    public const string MediaSessionLimit = "media_session_limit";
    public const string NotBorrowedWorkspace = "not_borrowed_workspace";
    public const string PinnedLimitReached = "pinned_limit_reached";
    public const string ProfileLeaseRevoked = "profile_lease_revoked";
    public const string ResidencyCandidateLimit = "residency_candidate_limit";
    public const string SessionEditLimit = "session_edit_limit";
    public const string SessionReleased = "session_released";
    public const string SessionSizeLimit = "session_size_limit";
    public const string SessionTransactionInProgress = "session_transaction_in_progress";
    public const string ShortcutCommandLimit = "shortcut_command_limit";
    public const string SpaceDeletionInProgress = "space_deletion_in_progress";
    public const string SpaceLimitReached = "space_limit_reached";
    public const string SpaceLocked = "space_locked";
    public const string StaleBorrowedSource = "stale_borrowed_source";
    public const string SyncClockExhausted = "sync_clock_exhausted";
    public const string SyncIdentityMismatch = "sync_identity_mismatch";
    public const string SyncRecordLimit = "sync_record_limit";
    public const string SyncSizeLimit = "sync_size_limit";
    public const string SyncTransactionNotSealed = "sync_transaction_not_sealed";
    public const string UnknownCurrentTab = "unknown_current_tab";
    public const string UnknownFolder = "unknown_folder";
    public const string UnknownSearchProvider = "unknown_search_provider";
    public const string UnsupportedUrl = "unsupported_url";
    public const string VersionMismatch = "version_mismatch";
    public const string WrongSpaceIdentity = "wrong_space_identity";

    // Site permissions and origins.
    public const string DuplicateSitePermissionRecord = "duplicate_site_permission_record";
    public const string InvalidBlockedPopup = "invalid_blocked_popup";
    public const string InvalidSiteOrigin = "invalid_site_origin";
    public const string InvalidSitePermissionDetail = "invalid_site_permission_detail";
    public const string SitePermissionLedgerLimit = "site_permission_ledger_limit";
    public const string SitePermissionRecordLimit = "site_permission_record_limit";
    public const string UnknownSitePermissionCommand = "unknown_site_permission_command";

    #endregion

    #region Variables - Link routes

    public const string DuplicateLinkRoute = "duplicate_link_route";
    public const string InvalidLinkRouteEdit = "invalid_link_route_edit";
    public const string LinkPatternTooLong = "link_pattern_too_long";
    public const string LinkRouteLimit = "link_route_limit";

    #endregion
}
