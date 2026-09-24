using CrestCore.Contracts;

namespace CrestCore.Domain;

/// Stable browser rule error code identifiers exposed to native callers.
public static class BrowserRuleCodes {
    #region Variables

    public const string AccessAlreadyAttached = "access_already_attached";
    public const string AlreadyClosing = "already_closing";
    public const string AlreadyInSplit = "already_in_split";
    public const string AuthenticationBusy = "authentication_busy";
    public const string BorrowedProfile = "borrowed_profile";
    public const string BorrowedProfileRequiresOwner = "borrowed_profile_requires_owner";
    public const string BorrowedSourceRequired = "borrowed_source_required";
    public const string CannotDeleteLastSpace = "cannot_delete_last_space";
    public const string DeletionRequiresCommand = "deletion_requires_command";
    public const string DifferentProfileOwner = "different_profile_owner";
    public const string DuplicateFolder = "duplicate_folder";
    public const string DuplicateMediaSession = "duplicate_media_session";
    public const string DuplicatePersistedIdentity = "duplicate_persisted_identity";
    public const string DuplicateResidencyCandidate = "duplicate_residency_candidate";
    public const string DuplicateSearchName = "duplicate_search_name";
    public const string DuplicateShortcutCommand = "duplicate_shortcut_command";
    public const string DuplicateSpace = "duplicate_space";
    public const string DuplicateSpaceProfile = "duplicate_space_profile";
    public const string DuplicateSyncRecord = "duplicate_sync_record";
    public const string DuplicateTab = "duplicate_tab";
    public const string EngineAlreadyRegistered = "engine_already_registered";
    public const string FolderActionUnavailable = "folder_action_unavailable";
    public const string FolderCycle = "folder_cycle";
    public const string FolderDepthLimit = "folder_depth_limit";
    public const string FolderLimit = "folder_limit";
    public const string IncompleteSplit = "incomplete_split";
    public const string InvalidAccent = "invalid_accent";
    public const string InvalidAccessPolicy = "invalid_access_policy";
    public const string InvalidAddress = "invalid_address";
    public const string InvalidContentBlockingPolicy = "invalid_content_blocking_policy";
    public const string InvalidDate = "invalid_date";
    public const string InvalidDeletionIntent = "invalid_deletion_intent";
    public const string InvalidDestination = "invalid_destination";
    public const string InvalidEngineRegistration = "invalid_engine_registration";
    public const string InvalidFocusedIndex = "invalid_focused_index";
    public const string InvalidFolderAnchor = "invalid_folder_anchor";
    public const string InvalidFolderPlacement = "invalid_folder_placement";
    public const string InvalidFolderSymbol = "invalid_folder_symbol";
    public const string InvalidFolderTree = "invalid_folder_tree";
    public const string InvalidHistoryRange = "invalid_history_range";
    public const string InvalidHistoryVisit = "invalid_history_visit";
    public const string InvalidIdentity = "invalid_identity";
    public const string InvalidMediaSessionCount = "invalid_media_session_count";
    public const string InvalidName = "invalid_name";
    public const string InvalidNativeKind = "invalid_native_kind";
    public const string InvalidNewSpace = "invalid_new_space";
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
    public const string InvalidSavedSelection = "invalid_saved_selection";
    public const string InvalidSavedState = "invalid_saved_state";
    public const string InvalidSavedUrl = "invalid_saved_url";
    public const string InvalidSearchName = "invalid_search_name";
    public const string InvalidSearchPlaceholder = "invalid_search_placeholder";
    public const string InvalidSearchProvider = "invalid_search_provider";
    public const string InvalidSearchTemplate = "invalid_search_template";
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
    public const string InvalidTabAnchor = "invalid_tab_anchor";
    public const string InvalidTabContent = "invalid_tab_content";
    public const string InvalidTabCount = "invalid_tab_count";
    public const string InvalidTabIcon = "invalid_tab_icon";
    public const string InvalidTerminationCount = "invalid_termination_count";
    public const string InvalidTitle = "invalid_title";
    public const string InvalidTransferTransaction = "invalid_transfer_transaction";
    public const string InvalidTransientPage = "invalid_transient_page";
    public const string InvalidTransition = "invalid_transition";
    public const string InvalidWorkspaceKind = "invalid_workspace_kind";
    public const string MediaSessionLimit = "media_session_limit";
    public const string MissingSpaceIdentity = "missing_space_identity";
    public const string NoCurrentTabs = "no_current_tabs";
    public const string NoIncludedSpaces = "no_included_spaces";
    public const string NotBorrowedWorkspace = "not_borrowed_workspace";
    public const string NotDurableTab = "not_durable_tab";
    public const string NotPrivateWorkspace = "not_private_workspace";
    public const string NotStartPageDraft = "not_start_page_draft";
    public const string PageBusy = "page_busy";
    public const string PageClosing = "page_closing";
    public const string PageNotReady = "page_not_ready";
    public const string PageNotUnloadable = "page_not_unloadable";
    public const string PersistentWorkspaceRequired = "persistent_workspace_required";
    public const string PinnedLimit = "pinned_limit";
    public const string PinnedLimitReached = "pinned_limit_reached";
    public const string PrivateWorkspaceBoundary = "private_workspace_boundary";
    public const string ProfileLeaseRevoked = "profile_lease_revoked";
    public const string ResidencyCandidateLimit = "residency_candidate_limit";
    public const string SameCollectionTransfer = "same_collection_transfer";
    public const string SameSessionTransfer = "same_session_transfer";
    public const string SameSpaceTransfer = "same_space_transfer";
    public const string SearchNameTooLong = "search_name_too_long";
    public const string SearchPlaceholderInFragment = "search_placeholder_in_fragment";
    public const string SearchPlaceholderMissing = "search_placeholder_missing";
    public const string SearchProviderLimit = "search_provider_limit";
    public const string SearchTemplateContainsSecret = "search_template_contains_secret";
    public const string SearchTemplateCredentials = "search_template_credentials";
    public const string SearchTemplatePort = "search_template_port";
    public const string SearchTemplateRequiresHttps = "search_template_requires_https";
    public const string SearchTemplateTooLong = "search_template_too_long";
    public const string SessionEditLimit = "session_edit_limit";
    public const string SessionReleased = "session_released";
    public const string SessionSizeLimit = "session_size_limit";
    public const string SessionTransactionInProgress = "session_transaction_in_progress";
    public const string ShortcutCommandLimit = "shortcut_command_limit";
    public const string SpaceDeleting = "space_deleting";
    public const string SpaceDeletionInProgress = "space_deletion_in_progress";
    public const string SpaceLimitReached = "space_limit_reached";
    public const string SpaceLocked = "space_locked";
    public const string SplitBoundary = "split_boundary";
    public const string SplitLimit = "split_limit";
    public const string StaleAuthentication = "stale_authentication";
    public const string StaleBorrowedSource = "stale_borrowed_source";
    public const string StaleSelection = "stale_selection";
    public const string StaleSessionRevision = "stale_session_revision";
    public const string SyncClockExhausted = "sync_clock_exhausted";
    public const string SyncIdentityMismatch = "sync_identity_mismatch";
    public const string SyncRecordLimit = "sync_record_limit";
    public const string SyncSizeLimit = "sync_size_limit";
    public const string SyncTransactionInProgress = "sync_transaction_in_progress";
    public const string SyncTransactionNotSealed = "sync_transaction_not_sealed";
    public const string TabLimit = "tab_limit";
    public const string TemporaryWorkspaceRequired = "temporary_workspace_required";
    public const string TransientAlreadyCompleted = "transient_already_completed";
    public const string TransientRequiresCommand = "transient_requires_command";
    public const string TransientSpaceLocked = "transient_space_locked";
    public const string TranslationRuleLimit = "translation_rule_limit";
    public const string UnknownArchive = "unknown_archive";
    public const string UnknownArchivedTab = "unknown_archived_tab";
    public const string UnknownCurrentTab = "unknown_current_tab";
    public const string UnknownFolder = "unknown_folder";
    public const string UnknownHistoryCommand = "unknown_history_command";
    public const string UnknownRecordCommand = "unknown_record_command";
    public const string UnknownSearchProvider = "unknown_search_provider";
    public const string UnknownSpace = "unknown_space";
    public const string UnknownSpaceCommand = "unknown_space_command";
    public const string UnknownSplitCommand = "unknown_split_command";
    public const string UnknownSplitGroup = "unknown_split_group";
    public const string UnknownSyncOperation = "unknown_sync_operation";
    public const string UnknownTab = "unknown_tab";
    public const string UnknownTransientCommand = "unknown_transient_command";
    public const string UnknownWorkspaceCommand = "unknown_workspace_command";
    public const string UnsafeSearchTemplate = "unsafe_search_template";
    public const string UnsupportedAccessPolicy = "unsupported_access_policy";
    public const string UnsupportedUrl = "unsupported_url";
    public const string VersionMismatch = "version_mismatch";
    public const string WindowStateLimit = "window_state_limit";
    public const string WrongDeletionOperation = "wrong_deletion_operation";
    public const string WrongProfile = "wrong_profile";
    public const string WrongProfileIdentity = "wrong_profile_identity";
    public const string WrongSpaceIdentity = "wrong_space_identity";
    public const string WrongTransientProfile = "wrong_transient_profile";

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

    #region Variables - Tab batches

    public const string CannotMoveSplitAcrossSpaces = "cannot_move_split_across_spaces";
    public const string CannotPinSplit = "cannot_pin_split";
    public const string CurrentTabsOnly = "current_tabs_only";
    public const string PinnedCapacity = "pinned_capacity";
    public const string SplitCapacity = "split_capacity";
    public const string WebPagesOnly = "web_pages_only";

    #endregion

    #region Variables - App preferences

    public const string InvalidPreferenceValue = "invalid_preference_value";
    public const string UnknownPreference = "unknown_preference";
    public const string UnknownPreferenceCommand = "unknown_preference_command";

    #endregion

    #region Actions - Search engines

    /// TRANSITIONAL: the code a session command reports for a refused custom
    /// search engine, until those commands answer typed rejections. Deleted
    /// with that bridge.
    private static readonly Dictionary<SearchEngineFlaw, string> SearchEngineFlawCodes = new() {
        [SearchEngineFlaw.EmptyName] = InvalidSearchName,
        [SearchEngineFlaw.NameTooLong] = SearchNameTooLong,
        [SearchEngineFlaw.TemplateTooLong] = SearchTemplateTooLong,
        [SearchEngineFlaw.MissingPlaceholder] = SearchPlaceholderMissing,
        [SearchEngineFlaw.AmbiguousPlaceholder] = InvalidSearchPlaceholder,
        [SearchEngineFlaw.InvalidTemplate] = InvalidSearchTemplate,
        [SearchEngineFlaw.RequiresHttps] = SearchTemplateRequiresHttps,
        [SearchEngineFlaw.UnsafeHost] = UnsafeSearchTemplate,
        [SearchEngineFlaw.NonstandardPort] = SearchTemplatePort,
        [SearchEngineFlaw.CredentialsInTemplate] = SearchTemplateCredentials,
        [SearchEngineFlaw.PlaceholderInFragment] = SearchPlaceholderInFragment,
        [SearchEngineFlaw.SecretInTemplate] = SearchTemplateContainsSecret
    };

    /// TRANSITIONAL: the code a session command reports for a refused custom
    /// search engine, until those commands answer typed rejections.
    public static string SearchEngine(Rejection rejection) => rejection switch {
        DuplicateSearchEngineName => DuplicateSearchName,
        SearchEngineLimitReached => SearchProviderLimit,
        InvalidSearchEngine invalid => SearchEngineFlawCodes.GetValueOrDefault(invalid.Flaw, InvalidSearchProvider),
        _ => InvalidSearchProvider
    };

    #endregion
}
