using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;

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
        var preferences = edit.Apply(session.AppPreferences);
        var output = Encoding.UTF8.GetBytes(new JsonObject { [PreferenceCodes.Record] = StoredSessionCodec.Encode(preferences) }.ToJsonString());
        return new NativeSessionCommand(this, expected, session with { AppPreferences = preferences }, output);
    }

    /// A read of the owned startup preference. The caller releases the prepared
    /// plan instead of committing it; committing would change nothing.
    private NativeSessionCommand PrepareLaunchPlan(ulong expected, JsonObject request) {
        using var parsed = JsonDocument.Parse(request.ToJsonString());
        var launch = LaunchPlanRequest.Decode(parsed.RootElement);
        var plan = launch.Plan(session.AppPreferences?.Startup);
        var output = Encoding.UTF8.GetBytes(LaunchCodes.Plan(plan).ToJsonString());
        return new NativeSessionCommand(this, expected, session, output);
    }

    private void RequirePreferenceOwner(SessionOperation operation) {
        BorrowedCommandRouting.RequireLocal(operation, workspaceKind == BrowserWorkspaceKind.Temporary);
        if (workspaceKind != BrowserWorkspaceKind.Persistent)
            throw new BrowserRuleException(BrowserRuleCodes.PersistentWorkspaceRequired);
    }

    #endregion
}
