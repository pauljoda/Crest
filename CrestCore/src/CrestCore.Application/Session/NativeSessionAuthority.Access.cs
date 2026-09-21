using System.Text.Json.Nodes;

using CrestCore.Domain;

namespace CrestCore.Application;

public sealed partial class NativeSessionAuthority {
    #region Variables

    private SpaceAccessAuthority? access;

    /// Operations that must still work while a Space is locked. None of them
    /// returns tab, folder, history or archive contents to the caller: the
    /// deletion intents that sync and cleanup depend on, and retention or
    /// current-tab maintenance sweeps.
    private static readonly string[] UnlockedOperations =
        ["space.deletion.begin", "space.remove", "records.sweep", "records.cleanup"];

    #endregion

    #region Actions - Access

    /// Locking is process-local, so the grants and the session records that name
    /// the policy have to meet in the same process. A borrowed workspace inherits
    /// its source's authority; nothing else can substitute one.
    public void AttachAccess(SpaceAccessAuthority authority) {
        ArgumentNullException.ThrowIfNull(authority);
        lock (Gate) {
            if (access is not null && !ReferenceEquals(access, authority))
                throw new BrowserRuleException("access_already_attached");
            access = authority;
        }
    }

    /// An unnamed policy was somebody restricting this Space in a build that knew
    /// more terms than this one. Resolve it to the guarded side, exactly as the
    /// native decoder does, instead of treating it as open.
    private static bool RequiresAuthentication(SpaceDocument space)
        => space.Metadata["accessPolicy"] is { } policy && policy.GetValue<string>() != "open";

    private static Guid? OptionalSpace(JsonNode? value) {
        if (value is null) return null;
        try { return Id(value); } catch (Exception error) when (error is BrowserRuleException or FormatException or InvalidOperationException) {
            // Malformed identities are the command's own rejection to make.
            return null;
        }
    }

    /// Rejects a command that would read or mutate a locked Space before any
    /// preparation runs. The native controllers keep their own gates; this one
    /// answers for the records and cannot be skipped by a view.
    private void RequireAccessibleCommand(JsonObject request) {
        if (access is null) return;
        var operation = request["operation"]!.GetValue<string>();
        if (UnlockedOperations.Contains(operation)) return;
        // Raising protection on a Space is always allowed. Taking it away is the
        // decision authentication exists to guard, so it needs the grant.
        if (operation == "space.access" && (request["arguments"] as JsonObject)?["value"] is JsonValue policy
            && policy.TryGetValue<string>(out var value) && value != "open") return;
        foreach (var space in CommandSpaces(request, operation)) RequireAccessible(space);
    }

    private static IEnumerable<Guid> CommandSpaces(JsonObject request, string operation) {
        foreach (var field in new[] { "spaceId", "destinationSpaceId" })
            if (OptionalSpace(request[field]) is { } id) yield return id;
        if (request["arguments"] is not JsonObject args) yield break;
        foreach (var field in new[] { "sourceSpaceId", "destinationSpaceId", "leaseSpaceId" })
            if (OptionalSpace(args[field]) is { } id) yield return id;
        if (operation != "workspace.import") yield break;
        // Importing into an existing Space writes its tabs and folders. A new
        // Space names no destination and cannot be locked yet.
        var sources = args["sources"] as JsonArray ?? [];
        foreach (var draft in args["drafts"] as JsonArray ?? []) {
            if (draft!["isNew"]?.GetValue<bool>() != false) continue;
            var index = draft["sourceIndex"]?.GetValue<int>() ?? -1;
            if (index >= 0 && index < sources.Count && OptionalSpace(sources[index]!["id"]) is { } id) yield return id;
        }
        foreach (var review in args["reviews"] as JsonArray ?? [])
            if (OptionalSpace(review!["destinationID"]) is { } id) yield return id;
    }

    private void RequireAccessible(Guid spaceId) {
        if (access is null) return;
        // An unknown identity is rejected by the command itself, with the error
        // that names the real problem.
        if (document.Spaces.FirstOrDefault(s => Id(s.Metadata["id"]) == spaceId) is not { } space) return;
        var assignment = new SpaceAccessAssignment(spaceId, Id(space.Metadata["profile"]!["id"]));
        lock (access) access.RequireAccessible(assignment, RequiresAuthentication(space));
    }

    #endregion
}
