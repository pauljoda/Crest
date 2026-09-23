using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;

using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

public sealed partial class NativeSessionAuthority {
    #region Actions - App preferences

    /// The app-wide behavior preferences belong to the persistent workspace and
    /// stay on this device: sync neither uploads nor replaces them. Commands
    /// (see `PreferenceEdit`) answer `{"preferences": record}` and change nothing else.
    private NativeSessionCommand PreparePreferencesCommand(ulong expected, JsonObject request, SessionOperation operation) {
        RequirePreferenceOwner(operation);
        if (operation == SessionOperation.LaunchPlan) return PrepareLaunchPlan(expected, request);
        var edit = PreferenceEdit.Decode(operation, request["arguments"] as JsonObject);
        var stored = document.Metadata[PreferencesDocument.Field];
        var metadata = document.Metadata.DeepClone().AsObject();
        var record = PreferencesDocument.Write(stored, edit.Apply(stored));
        metadata[PreferencesDocument.Field] = record;
        var output = Encoding.UTF8.GetBytes(new JsonObject { [PreferenceCodes.Record] = record.DeepClone() }.ToJsonString());
        return new NativeSessionCommand(this, expected, new SessionDocument(metadata, document.Spaces), output);
    }

    /// A read of the owned startup preference. The caller releases the prepared
    /// plan instead of committing it; committing would change nothing.
    private NativeSessionCommand PrepareLaunchPlan(ulong expected, JsonObject request) {
        var stored = document.Metadata[PreferencesDocument.Field];
        using var parsed = JsonDocument.Parse(request.ToJsonString());
        Protocol.Members(parsed.RootElement, LaunchCodes.RequestMembers);
        var plan = NativePolicyEvaluator.PlanLaunch(parsed.RootElement,
            stored is null ? null : PreferencesDocument.Read(stored).Startup);
        var output = Encoding.UTF8.GetBytes(LaunchCodes.Plan(plan).ToJsonString());
        return new NativeSessionCommand(this, expected, document, output);
    }

    /// Only the preference commands change the record. A value edit or a sync
    /// replacement that carries a different or missing record keeps the owned one.
    private JsonObject KeepingPreferences(JsonObject metadata) {
        if (document.Metadata[PreferencesDocument.Field] is { } owned) metadata[PreferencesDocument.Field] = owned.DeepClone();
        else metadata.Remove(PreferencesDocument.Field);
        return metadata;
    }

    private void RequirePreferenceOwner(SessionOperation operation) {
        BorrowedCommandRouting.RequireLocal(operation, workspaceKind == BrowserWorkspaceKind.Temporary);
        if (workspaceKind != BrowserWorkspaceKind.Persistent)
            throw new BrowserRuleException(BrowserRuleCodes.PersistentWorkspaceRequired);
    }

    #endregion
}
