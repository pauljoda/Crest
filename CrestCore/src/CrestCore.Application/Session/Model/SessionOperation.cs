using System.Text.Json.Nodes;

using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

internal enum SessionOperation {
    Unknown,
    UnknownSpace,
    SpaceBrowsingPreferences,
    SpaceSearchProviderRemove,
    SpaceSearchProviderUpsert,
    TabTransfer,
    TabsBatch,
    WorkspaceImport,
}

internal static class SessionOperationCodes {
    #region Actions - Decoding

    public static SessionOperation Parse(string? value) => value switch {
        "space.browsing_preferences" => SessionOperation.SpaceBrowsingPreferences,
        "space.search_provider.remove" => SessionOperation.SpaceSearchProviderRemove,
        "space.search_provider.upsert" => SessionOperation.SpaceSearchProviderUpsert,
        "tab.transfer" => SessionOperation.TabTransfer,
        "tabs.batch" => SessionOperation.TabsBatch,
        "workspace.import" => SessionOperation.WorkspaceImport,
        _ when value?.StartsWith("space.", StringComparison.Ordinal) == true => SessionOperation.UnknownSpace,
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
            SessionOperation.WorkspaceImport or SessionOperation.TabTransfer => new(superseded, SyncUrgency.WithSave),
            SessionOperation.TabsBatch => new(Enum.TryParse<TabBatchKind>(request["arguments"]?["kind"]?.GetValue<string>(), out var kind)
                && kind == TabBatchKind.Delete ? explicitDelete : superseded, SyncUrgency.WithSave),
            _ => new(superseded, SyncUrgency.Coalesced)
        };
    }

    #endregion

    #region Actions - Families

    public static bool IsSpace(SessionOperation operation) => operation is
        SessionOperation.UnknownSpace
        or SessionOperation.SpaceBrowsingPreferences
        or SessionOperation.SpaceSearchProviderRemove
        or SessionOperation.SpaceSearchProviderUpsert;

    #endregion
}
