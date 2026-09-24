using System.Text.Json.Nodes;

using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

internal enum SessionOperation {
    Unknown,
    TabTransfer,
    TabsBatch,
    WorkspaceImport,
}

internal static class SessionOperationCodes {
    #region Actions - Decoding

    public static SessionOperation Parse(string? value) => value switch {
        "tab.transfer" => SessionOperation.TabTransfer,
        "tabs.batch" => SessionOperation.TabsBatch,
        "workspace.import" => SessionOperation.WorkspaceImport,
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
}
