using System.Text.Json.Nodes;
using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

public sealed partial class BrowserKernel
{
    private readonly Dictionary<SpaceId, Outgoing> contentBlockingEffects = [];
    private readonly Dictionary<SpaceId, string> contentBlockingFailures = [];

    private void ApplyContentBlocking(Envelope m, BrowserSpace space)
    {
        // One native update per profile at a time. Later commands change the
        // desired durable policy and are coalesced after this acknowledgement.
        if (contentBlockingEffects.ContainsKey(space.Id)) return;
        var effect = new Outgoing(engine.Id, "effect", "engine.apply_content_blocking", new()
        {
            ["spaceId"] = space.Id.Value.ToString(), ["profileId"] = space.ProfileId.Value.ToString(),
            ["policy"] = LegacySessionDocument.EnumName(space.ContentBlocking)
        }, ids.Next(), m.CorrelationId, m.Id);
        contentBlockingEffects.Add(space.Id, effect); output.Add(effect);
    }
    private void CompleteContentBlocking(Envelope m)
    {
        Protocol.Members(m.Payload, "spaceId", "profileId");
        var space = workspace.Space(new(Protocol.Id(m.Payload, "spaceId")));
        if (!contentBlockingEffects.TryGetValue(space.Id, out var effect) || effect.Id != m.CausationId
            || effect.CorrelationId != m.CorrelationId || space.ProfileId.Value != Protocol.Id(m.Payload, "profileId"))
            throw new BrowserRuleException("unknown_content_blocking_effect");
        contentBlockingEffects.Remove(space.Id);
        bool superseded = effect.Payload["policy"]!.GetValue<string>() != LegacySessionDocument.EnumName(space.ContentBlocking);
        if (!space.IsDeleting && !workspaceClosing)
        {
            if (superseded) ApplyContentBlocking(m, space);
            else if (m.Type == "engine.content_blocking_failed")
            { contentBlockingFailures[space.Id] = "content_blocking_failed"; Result(m, "content_blocking_failed"); }
        }
        Snapshot(m);
    }
}
