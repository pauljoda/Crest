namespace CrestCore.Contracts;

/// Stable protocol error code identifiers exposed to native callers.
public static class ProtocolErrorCodes {
    #region Variables

    public const string CapabilityLimit = "capability_limit";
    public const string DownloadInputLimit = "download_input_limit";
    public const string DuplicateMember = "duplicate_member";
    public const string InvalidAdapter = "invalid_adapter";
    public const string InvalidCounter = "invalid_counter";
    public const string InvalidDate = "invalid_date";
    public const string InvalidEndpoint = "invalid_endpoint";
    public const string InvalidInput = "invalid_input";
    public const string InvalidLimit = "invalid_limit";
    public const string InvalidPeekModifier = "invalid_peek_modifier";
    public const string InvalidPermissionDecision = "invalid_permission_decision";
    public const string InvalidPlacement = "invalid_placement";
    public const string InvalidPressureLevel = "invalid_pressure_level";
    public const string InvalidPressurePlatform = "invalid_pressure_platform";
    public const string InvalidStatus = "invalid_status";
    public const string InvalidRiskReason = "invalid_risk_reason";
    public const string InvalidString = "invalid_string";
    public const string InvalidUuid = "invalid_uuid";
    public const string InvalidVersion = "invalid_version";
    public const string InvalidVisitCount = "invalid_visit_count";
    public const string PolicyInputLimit = "policy_input_limit";
    public const string RecordBatchLimit = "record_batch_limit";
    public const string ResidencyCandidateLimit = "residency_candidate_limit";
    public const string SessionEditLimit = "session_edit_limit";
    public const string UnexpectedMember = "unexpected_member";
    public const string UnknownPolicy = "unknown_policy";
    public const string UnknownSessionEdit = "unknown_session_edit";
    public const string VersionMismatch = "version_mismatch";

    #endregion
}
