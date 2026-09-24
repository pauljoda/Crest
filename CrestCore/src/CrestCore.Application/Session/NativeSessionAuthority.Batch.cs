using System.Text.Json.Nodes;

using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

public sealed partial class NativeSessionAuthority {
    #region Actions - Batch

    private NativeSessionCommand PrepareTabBatch(ulong expected, JsonObject request) {
        try {
            // A batch acts on the tabs the person multi-selected in the Space
            // their window shows; any other Space means the selection is stale.
            var view = SessionView.Decode(request[SessionView.Key]);
            var sourceId = Id(request["spaceId"]);
            if (view.SpaceId != sourceId) throw new BrowserRuleException(BrowserRuleCodes.StaleSelection);
            var source = TransferSpace(sourceId, Id(request["profileId"]));
            var args = request["arguments"]!.AsObject();
            var selection = args["selection"]!;
            Guid? Tab(JsonNode? value) => value is null ? null : Id(value);
            Guid? Folder(JsonNode? value) => value is null ? null : Id(value);
            TabPlacement Placement(JsonNode? value) => value is null ? TabPlacement.Current
                : TabPlacementCodes.Parse(value.GetValue<string>()) ?? throw new ProtocolException(ProtocolErrorCodes.InvalidPlacement);
            var captured = new TabBatchSelection(
                selection["roots"]!.AsArray().Select(r => new BatchItem(Id(r!["id"]), r["folder"]!.GetValue<bool>())).ToArray(),
                selection["tabs"]!.AsArray().Select(t => new BatchTab(Id(t!["id"]), Placement(t["placement"]),
                    Folder(t["folderId"]), t["splitGroupId"] is { } group ? Id(group) : null)).ToArray(),
                selection["folders"]!.AsArray().Select(f => new BatchFolder(Id(f!["id"]), Folder(f["parentId"]),
                    Placement(f["location"]))).ToArray());
            var action = new TabBatchAction(Enum.Parse<TabBatchKind>(args["kind"]!.GetValue<string>()),
                Placement(args["placement"]), Folder(args["folderId"]), Tab(args["before"]), Folder(args["beforeFolderId"]),
                Tab(args["targetId"]), args["index"]?.GetValue<int>(), args["keep"]?.GetValue<bool>() == true,
                args["follow"]?.GetValue<bool>() == true);
            SpaceState? destination = null;
            if (action.Kind == TabBatchKind.MoveToSpace) {
                var requested = Id(args["destinationSpaceId"]);
                if (requested == sourceId) throw new BrowserRuleException(BrowserRuleCodes.InvalidDestination);
                destination = TransferSpace(requested, Id(args["destinationProfileId"]));
            }
            var a = BrowserTabCollection.Restore(source);
            var b = destination is null ? null : BrowserTabCollection.Restore(destination);
            var now = Now(request);
            var result = a.ApplyBatch(captured, action, view.Tab(sourceId), Tab(args["fallbackTabId"]),
                b, destination is null ? null : view.Tab(destination.Id), new SystemIdSource(), now);
            var observations = (args["copyObservations"] as JsonArray ?? []).Select(node => SessionTabObservation.Decode(node!)).ToArray();
            foreach (var pair in result.Copies) {
                var observation = observations.FirstOrDefault(item => item.TabId == pair.Source);
                if (a.Tab(pair.Copy).Content.IsWebPage && observation is not null)
                    a.Tab(pair.Copy).AdoptObservation(observation.Url, observation.Title ?? throw new ProtocolException(ProtocolErrorCodes.InvalidInput));
            }
            if (result.CreatedFolder is { } created && args["folderColor"] is JsonObject color)
                a.SetFolderColor(created, StoredSessionCodec.DecodeColor(color));
            foreach (var pair in result.GroupCopies) a.CopySplitMetadata(pair.Source, pair.Copy, now);
            a.PruneSplitMetadata(); b?.PruneSplitMetadata();
            var organized = new List<(SpaceState Space, BrowserTabCollection Edited)> { (a.Capture(source), a) };
            if (destination is not null && b is not null) organized.Add((b.Capture(destination), b));
            var changes = new JsonArray();
            foreach (var (space, collection) in organized)
                changes.Add((JsonNode)new JsonObject {
                    ["space"] = StoredSessionCodec.Encode(space with { History = [], ArchivedTabs = collection.Archive }),
                    ["tabId"] = null,
                    ["changed"] = true,
                    ["copies"] = new JsonArray(result.Copies.Select(p => (JsonNode)new JsonObject { ["source"] = p.Source.ToString(), ["copy"] = p.Copy.ToString() }).ToArray())
                });
            var hint = new SessionSelectionHint().SelectTab(view, sourceId, result.Selection);
            if (destination is not null) {
                hint.SelectTab(view, destination.Id, result.DestinationSelection);
                if (action.Follow) hint.SelectSpace(destination.Id);
            }
            var next = Replacing(session, [.. organized.Select(pair => pair.Space)]);
            Validate(next);
            var output = Output(new JsonObject {
                ["changes"] = changes,
                [SessionSelectionHint.Key] = hint.Encode()
            });
            return new(this, expected, next, output);
        } catch (BrowserRuleException error) {
            return new(this, expected, session, Output(new JsonObject { ["error"] = error.Code }), error.Code);
        }
    }

    #endregion
}
