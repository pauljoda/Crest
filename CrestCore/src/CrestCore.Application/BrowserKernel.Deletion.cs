using System.Text.Json.Nodes;
using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

public sealed partial class BrowserKernel
{
    private readonly Dictionary<SpaceId, Outgoing> deletionEffects = [];
    private readonly Dictionary<SpaceId, string> deletionFailures = [];
    private readonly HashSet<SpaceId> deletedEngineProfiles = [];

    private bool DeletionIntentSaved(SpaceDeletionState deletion) => storage is null ||
        savedState?["spaceDeletions"] is JsonArray saved && saved.Any(value =>
            value?["spaceId"]?.GetValue<string>() == deletion.Space.Value.ToString()
            && value?["profileId"]?.GetValue<string>() == deletion.Profile.Value.ToString());
    internal bool IsDeletionDurable(SpaceId id) => workspace.SpaceDeletions.FirstOrDefault(d => d.Space == id) is { } deletion
        && DeletionIntentSaved(deletion);

    // Called by the session coordinator only after all profile borrowers release
    // their native objects. Persisted intent fences every irreversible provider call.
    internal IReadOnlyList<Outgoing> ContinueDeletions(Envelope m, IReadOnlySet<SpaceId> released)
    {
        output.Clear();
        foreach (var deletion in workspace.SpaceDeletions.Where(d => !d.Completed && released.Contains(d.Space)))
        {
            if (quiescing || SaveFailed || !DeletionIntentSaved(deletion)
                || deletionEffects.ContainsKey(deletion.Space) || deletionFailures.ContainsKey(deletion.Space)
                || contentBlockingEffects.ContainsKey(deletion.Space)
                || pending.Values.Any(p => p.Space == deletion.Space) || surfaceAssignments.Count != 0
                || handoffs.Values.Any(h => h.Space == deletion.Space) || attachingHandoffs.Values.Any(h => h.Space == deletion.Space)) continue;
            if (!engine.Supports("profile-deletion") || services?.Supports("space-data-deletion") != true)
            { deletionFailures[deletion.Space] = "capability_unavailable"; Snapshot(m); continue; }
            bool engineDone = deletedEngineProfiles.Contains(deletion.Space);
            var effect = new Outgoing(engineDone ? services!.Id : engine.Id, "effect",
                engineDone ? "services.delete_space_data" : "engine.delete_profile", new()
                {
                    ["spaceId"] = deletion.Space.Value.ToString(), ["profileId"] = deletion.Profile.Value.ToString(),
                    ["workspaceId"] = workspace.Id.Value.ToString()
                }, ids.Next(), m.CorrelationId, m.Id);
            deletionEffects.Add(deletion.Space, effect); output.Add(effect);
        }
        return output.ToArray();
    }
    private void CompleteDeletionEffect(Envelope m)
    {
        Protocol.Members(m.Payload, "spaceId", "profileId", "code");
        var space = new SpaceId(Protocol.Id(m.Payload, "spaceId"));
        var profile = new ProfileId(Protocol.Id(m.Payload, "profileId"));
        if (!deletionEffects.TryGetValue(space, out var effect) || effect.Id != m.CausationId
            || effect.CorrelationId != m.CorrelationId || effect.Payload["profileId"]!.GetValue<string>() != profile.Value.ToString()
            || (effect.Type == "engine.delete_profile") != m.Type.StartsWith("engine.", StringComparison.Ordinal))
            throw new BrowserRuleException("unknown_deletion_effect");
        deletionEffects.Remove(space);
        if (m.Type.EndsWith("_failed", StringComparison.Ordinal))
        {
            deletionFailures[space] = "profile_cleanup_failed";
            Result(m, "profile_cleanup_failed");
        }
        else if (effect.Type == "engine.delete_profile") deletedEngineProfiles.Add(space);
        else
        {
            workspace.CompleteSpaceDeletion(space, profile); deletedEngineProfiles.Remove(space);
            persistenceDirty = true; Result(m);
        }
        Snapshot(m);
    }
}
