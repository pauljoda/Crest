using System.Text.Json.Nodes;

using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

internal enum SessionOperation {
    Unknown,
    UnknownPreferences,
    UnknownSpace,
    UnknownTransient,
    LaunchPlan,
    PreferencesImport,
    PreferencesSet,
    PreferencesTranslationRule,
    SpaceAccess,
    SpaceBranding,
    SpaceBrowsingPreferences,
    SpaceCreate,
    SpaceCredentialPreferences,
    SpaceDefault,
    SpaceDeletionBegin,
    SpaceIdentity,
    SpaceRemove,
    SpaceReorder,
    SpaceResetPrivate,
    SpaceSavedExpansion,
    SpaceSearchProviderRemove,
    SpaceSearchProviderUpsert,
    TabArchiveTransient,
    TabClearCurrent,
    TabClose,
    TabCloseDurable,
    TabCopy,
    TabDelete,
    TabMove,
    TabOpen,
    TabPromoteTransient,
    TabTransfer,
    TabsBatch,
    TransientArchive,
    TransientPromote,
    WorkspaceImport,
}

internal static class SessionOperationCodes {
    #region Actions - Decoding

    public static SessionOperation Parse(string? value) => value switch {
        "launch.plan" => SessionOperation.LaunchPlan,
        "preferences.import" => SessionOperation.PreferencesImport,
        "preferences.set" => SessionOperation.PreferencesSet,
        "preferences.translation_rule" => SessionOperation.PreferencesTranslationRule,
        "space.access" => SessionOperation.SpaceAccess,
        "space.branding" => SessionOperation.SpaceBranding,
        "space.browsing_preferences" => SessionOperation.SpaceBrowsingPreferences,
        "space.create" => SessionOperation.SpaceCreate,
        "space.credential_preferences" => SessionOperation.SpaceCredentialPreferences,
        "space.default" => SessionOperation.SpaceDefault,
        "space.deletion.begin" => SessionOperation.SpaceDeletionBegin,
        "space.identity" => SessionOperation.SpaceIdentity,
        "space.remove" => SessionOperation.SpaceRemove,
        "space.reorder" => SessionOperation.SpaceReorder,
        "space.reset_private" => SessionOperation.SpaceResetPrivate,
        "space.saved_expansion" => SessionOperation.SpaceSavedExpansion,
        "space.search_provider.remove" => SessionOperation.SpaceSearchProviderRemove,
        "space.search_provider.upsert" => SessionOperation.SpaceSearchProviderUpsert,
        "tab.archive_transient" => SessionOperation.TabArchiveTransient,
        "tab.clear_current" => SessionOperation.TabClearCurrent,
        "tab.close" => SessionOperation.TabClose,
        "tab.close_durable" => SessionOperation.TabCloseDurable,
        "tab.copy" => SessionOperation.TabCopy,
        "tab.delete" => SessionOperation.TabDelete,
        "tab.move" => SessionOperation.TabMove,
        "tab.open" => SessionOperation.TabOpen,
        "tab.promote_transient" => SessionOperation.TabPromoteTransient,
        "tab.transfer" => SessionOperation.TabTransfer,
        "tabs.batch" => SessionOperation.TabsBatch,
        "transient.archive" => SessionOperation.TransientArchive,
        "transient.promote" => SessionOperation.TransientPromote,
        "workspace.import" => SessionOperation.WorkspaceImport,
        _ when value?.StartsWith("preferences.", StringComparison.Ordinal) == true => SessionOperation.UnknownPreferences,
        _ when value?.StartsWith("space.", StringComparison.Ordinal) == true => SessionOperation.UnknownSpace,
        _ when value?.StartsWith("transient.", StringComparison.Ordinal) == true => SessionOperation.UnknownTransient,
        _ => SessionOperation.Unknown
    };

    #endregion

    #region Actions - Sync

    /// How a command's accepted revision reaches the sync journal: why the
    /// records it removed are deleted, and how soon it stages. Null for a
    /// command that changes nothing the journal reads.
    ///
    /// TRANSITIONAL until the typed session intents land (S5.3 onward): each
    /// intent then carries its own staging, and this switch goes with the
    /// operation strings.
    public static SyncStaging? Staging(SessionOperation operation, JsonObject request) {
        var explicitDelete = SyncDeletionReason.ExplicitDelete;
        var superseded = SyncDeletionReason.Superseded;
        return operation switch {
            SessionOperation.TabDelete => new(explicitDelete, SyncUrgency.Immediate),
            SessionOperation.TabOpen or SessionOperation.TabCopy or SessionOperation.TabClose or SessionOperation.TabClearCurrent
                or SessionOperation.TabCloseDurable or SessionOperation.TransientPromote
                or SessionOperation.SpaceCreate or SessionOperation.SpaceAccess
                or SessionOperation.SpaceCredentialPreferences => new(superseded, SyncUrgency.Immediate),
            SessionOperation.SpaceRemove => new(explicitDelete, SyncUrgency.WithSave),
            SessionOperation.SpaceDeletionBegin or SessionOperation.WorkspaceImport or SessionOperation.TabTransfer =>
                new(superseded, SyncUrgency.WithSave),
            SessionOperation.TabsBatch => new(Enum.TryParse<TabBatchKind>(request["arguments"]?["kind"]?.GetValue<string>(), out var kind)
                && kind == TabBatchKind.Delete ? explicitDelete : superseded, SyncUrgency.WithSave),
            SessionOperation.LaunchPlan or SessionOperation.SpaceResetPrivate => null,
            _ => new(superseded, SyncUrgency.Coalesced)
        };
    }

    #endregion

    #region Actions - Families

    /// App-wide behavior preferences and the launch plan that reads them.
    public static bool IsPreferences(SessionOperation operation) => operation is
        SessionOperation.UnknownPreferences
        or SessionOperation.LaunchPlan
        or SessionOperation.PreferencesImport
        or SessionOperation.PreferencesSet
        or SessionOperation.PreferencesTranslationRule;

    public static bool IsTransient(SessionOperation operation) => operation is
        SessionOperation.UnknownTransient
        or SessionOperation.TransientArchive
        or SessionOperation.TransientPromote;

    public static bool IsSpace(SessionOperation operation) => operation is
        SessionOperation.UnknownSpace
        or SessionOperation.SpaceAccess
        or SessionOperation.SpaceBranding
        or SessionOperation.SpaceBrowsingPreferences
        or SessionOperation.SpaceCreate
        or SessionOperation.SpaceCredentialPreferences
        or SessionOperation.SpaceDefault
        or SessionOperation.SpaceDeletionBegin
        or SessionOperation.SpaceIdentity
        or SessionOperation.SpaceRemove
        or SessionOperation.SpaceReorder
        or SessionOperation.SpaceResetPrivate
        or SessionOperation.SpaceSavedExpansion
        or SessionOperation.SpaceSearchProviderRemove
        or SessionOperation.SpaceSearchProviderUpsert;

    #endregion
}
