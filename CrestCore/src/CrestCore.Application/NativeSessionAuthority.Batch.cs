using System.Text.Json.Nodes;
using CrestCore.Domain;

namespace CrestCore.Application;

public sealed partial class NativeSessionAuthority
{
    private NativeSessionCommand PrepareTabBatch(ulong expected, JsonObject request)
    {
        try
        {
            var window = request["window"]!;
            var sourceId = Id(request["spaceId"]);
            if (Id(window["selectedSpaceID"]) != sourceId) throw new BrowserRuleException("stale_selection");
            var source = TransferSpace(sourceId, Id(request["profileId"]));
            var args = request["arguments"]!.AsObject();
            var selection = args["selection"]!;
            TabId? Tab(JsonNode? value) => value is null ? null : new(Id(value));
            FolderId? Folder(JsonNode? value) => value is null ? null : new(Id(value));
            TabPlacement Placement(JsonNode? value) => value is null ? TabPlacement.Current
                : Enum.Parse<TabPlacement>(value.GetValue<string>(), true);
            var captured = new TabBatchSelection(
                selection["roots"]!.AsArray().Select(r => new BatchItem(Id(r!["id"]), r["folder"]!.GetValue<bool>())).ToArray(),
                selection["tabs"]!.AsArray().Select(t => new BatchTab(new(Id(t!["id"])), Placement(t["placement"]),
                    Folder(t["folderId"]), t["splitGroupId"] is { } group ? Id(group) : null)).ToArray(),
                selection["folders"]!.AsArray().Select(f => new BatchFolder(new(Id(f!["id"])), Folder(f["parentId"]),
                    Placement(f["location"]))).ToArray());
            var action = new TabBatchAction(Enum.Parse<TabBatchKind>(args["kind"]!.GetValue<string>()),
                Placement(args["placement"]), Folder(args["folderId"]), Tab(args["before"]), Folder(args["beforeFolderId"]),
                Tab(args["targetId"]), args["index"]?.GetValue<int>(), args["keep"]?.GetValue<bool>() == true,
                args["follow"]?.GetValue<bool>() == true);
            SpaceDocument? destination = null;
            if (action.Kind == TabBatchKind.MoveToSpace)
            {
                var destinationId = Id(args["destinationSpaceId"]);
                if (destinationId == sourceId) throw new BrowserRuleException("invalid_destination");
                destination = TransferSpace(destinationId, Id(args["destinationProfileId"]));
            }
            var spaces = new JsonArray(TransferProjection(source, window));
            if (destination is not null) spaces.Add((JsonNode)TransferProjection(destination, window));
            var legacy = new LegacySessionDocument(new JsonObject { ["session"] = new JsonObject
                { ["selectedSpaceID"] = source.Metadata["id"]!.DeepClone(), ["spaces"] = spaces } });
            var state = legacy.Read(new SystemIdSource());
            var a = BrowserTabCollection.Restore(state.Spaces[0]);
            var b = destination is null ? null : BrowserTabCollection.Restore(state.Spaces[1]);
            var now = new DateTimeOffset(2001, 1, 1, 0, 0, 0, TimeSpan.Zero).AddSeconds(request["now"]!.GetValue<double>());
            var result = a.ApplyBatch(captured, action, state.Spaces[0].SelectedTabId, Tab(args["fallbackTabId"]),
                b, destination is null ? null : state.Spaces[1].SelectedTabId, new SystemIdSource(), now);
            foreach (var pair in result.Copies)
            {
                legacy.CopyTabMetadata(pair.Source, pair.Copy);
                var observation = (args["copyObservations"] as JsonArray)?.FirstOrDefault(o => Id(o!["tabId"]) == pair.Source.Value);
                if (a.Tab(pair.Copy).Kind == TabKind.Web && observation is not null)
                    a.Tab(pair.Copy).Observe(observation["url"]?.GetValue<string>(), observation["title"]!.GetValue<string>(),
                        false, false, false, null);
            }
            if (result.CreatedFolder is { } created && args["folderColor"] is { } color)
                legacy.SetFolderMetadata(created, "color", color.DeepClone());
            var capturedSpaces = new List<SpaceState> { a.Capture(state.Spaces[0], result.Selection) };
            if (b is not null) capturedSpaces.Add(b.Capture(state.Spaces[1], result.DestinationSelection));
            var edited = legacy.Write(state with { Spaces = capturedSpaces.ToArray() })["session"]!["spaces"]!.AsArray();
            var outputSource = edited[0]!;
            foreach (var pair in result.GroupCopies)
            {
                var metadata = (spaces[0]!["splitGroups"] as JsonArray)?.FirstOrDefault(g => Id(g!["id"]) == pair.Source);
                if (metadata is null) continue;
                var copy = metadata.DeepClone(); copy["id"] = new JsonObject { ["rawValue"] = pair.Copy.ToString() };
                foreach (var field in new[] { "titleModifiedAt", "iconModifiedAt", "tintModifiedAt" }) copy[field] = NativeEditTimestamp.Encode(now);
                if (outputSource["splitGroups"] is not JsonArray) outputSource["splitGroups"] = new JsonArray();
                outputSource["splitGroups"]!.AsArray().Add(copy);
            }
            var changes = new JsonArray();
            foreach (var space in edited)
            {
                var groups = space!["tabs"]!.AsArray().Where(t => t!["splitGroupID"] is not null)
                    .Select(t => Id(t!["splitGroupID"])).ToHashSet();
                if (space["splitGroups"] is JsonArray metadata)
                    for (int i = metadata.Count - 1; i >= 0; i--) if (!groups.Contains(Id(metadata[i]!["id"]))) metadata.RemoveAt(i);
                changes.Add((JsonNode)new JsonObject { ["space"] = space.DeepClone(), ["tabId"] = null, ["selectSpace"] = false,
                    ["changed"] = true, ["copies"] = new JsonArray(result.Copies.Select(p => (JsonNode)new JsonObject
                        { ["source"] = p.Source.Value.ToString(), ["copy"] = p.Copy.Value.ToString() }).ToArray()) });
            }
            var selectedWindow = window.DeepClone();
            if (destination is not null && action.Follow) selectedWindow["selectedSpaceID"] = destination.Metadata["id"]!.DeepClone();
            var next = ApplyTransfer(document, selectedWindow, edited.Select(s => s!.AsObject()).ToArray());
            var output = TransferOutput(new JsonObject { ["changes"] = changes,
                ["selectedSpaceID"] = selectedWindow["selectedSpaceID"]!.DeepClone() });
            return new(this, expected, next, output);
        }
        catch (BrowserRuleException error)
        {
            return new(this, expected, document, TransferOutput(new JsonObject { ["error"] = error.Code }), error.Code);
        }
    }
}
