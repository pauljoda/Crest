namespace CrestCore.Contracts;

/// Stable protocol error code identifiers exposed to native callers.
public static class ProtocolErrorCodes {
    #region Variables

    public const string CapabilityLimit = "capability_limit";
    public const string DuplicateMember = "duplicate_member";
    public const string HandleCollision = "handle_collision";
    public const string InvalidAdapter = "invalid_adapter";
    public const string InvalidCounter = "invalid_counter";
    public const string InvalidCredentialEvent = "invalid_credential_event";
    public const string InvalidEndpoint = "invalid_endpoint";
    public const string InvalidEntryPoint = "invalid_entry_point";
    public const string InvalidFillSource = "invalid_fill_source";
    public const string InvalidInput = "invalid_input";
    public const string InvalidLimit = "invalid_limit";
    public const string InvalidPasskeyState = "invalid_passkey_state";
    public const string InvalidPasswordKind = "invalid_password_kind";
    public const string InvalidPeekModifier = "invalid_peek_modifier";
    public const string InvalidPermissionDecision = "invalid_permission_decision";
    public const string InvalidPlacement = "invalid_placement";
    public const string InvalidPlatform = "invalid_platform";
    public const string InvalidPlaybackState = "invalid_playback_state";
    public const string InvalidPressureLevel = "invalid_pressure_level";
    public const string InvalidPressurePlatform = "invalid_pressure_platform";
    public const string InvalidStatus = "invalid_status";
    public const string InvalidString = "invalid_string";
    public const string InvalidUuid = "invalid_uuid";
    public const string InvalidVersion = "invalid_version";
    public const string InvalidWriteThroughAvailability = "invalid_write_through_availability";
    public const string LanguageBatchLimit = "language_batch_limit";
    public const string PolicyInputLimit = "policy_input_limit";
    public const string RecordBatchLimit = "record_batch_limit";
    public const string ResidencyCandidateLimit = "residency_candidate_limit";
    public const string SearchProviderBatchLimit = "search_provider_batch_limit";
    public const string SessionEditLimit = "session_edit_limit";
    public const string UnexpectedMember = "unexpected_member";
    public const string UnknownPolicy = "unknown_policy";
    public const string UnknownSessionEdit = "unknown_session_edit";
    public const string VersionMismatch = "version_mismatch";

    // Site permissions and origins.
    public const string InvalidAuthenticationMethod = "invalid_authentication_method";
    public const string InvalidMediaPermission = "invalid_media_permission";
    public const string InvalidPopupEvent = "invalid_popup_event";
    public const string InvalidSitePermission = "invalid_site_permission";
    public const string SitePermissionInputLimit = "site_permission_input_limit";

    #endregion

    #region Variables - Links, Quick Windows and presentation

    public const string InvalidArchivePolicy = "invalid_archive_policy";
    public const string InvalidBranding = "invalid_branding";
    public const string InvalidLinkDestination = "invalid_link_destination";
    public const string InvalidLinkRouteMatch = "invalid_link_route_match";
    public const string InvalidPagePresentation = "invalid_page_presentation";
    public const string LinkRouteBatchLimit = "link_route_batch_limit";

    #endregion
}
