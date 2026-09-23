using System.Text.Json.Nodes;

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
                : Enum.Parse<TabPlacement>(value.GetValue<string>(), true);
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
            SpaceDocument? destination = null;
            if (action.Kind == TabBatchKind.MoveToSpace) {
                var requested = Id(args["destinationSpaceId"]);
                if (requested == sourceId) throw new BrowserRuleException(BrowserRuleCodes.InvalidDestination);
                destination = TransferSpace(requested, Id(args["destinationProfileId"]));
            }
            var spaces = new JsonArray(TransferProjection(source));
            if (destination is not null) spaces.Add((JsonNode)TransferProjection(destination));
            var legacy = new LegacySessionDocument(new JsonObject {
                ["session"] = new JsonObject { ["spaces"] = spaces }
            });
            var state = legacy.Read(new SystemIdSource());
            var a = BrowserTabCollection.Restore(state.Spaces[0]);
            var b = destination is null ? null : BrowserTabCollection.Restore(state.Spaces[1]);
            var now = new DateTimeOffset(2001, 1, 1, 0, 0, 0, TimeSpan.Zero).AddSeconds(request["now"]!.GetValue<double>());
            Guid? destinationId = destination is null ? null : Id(destination.Metadata["id"]);
            var result = a.ApplyBatch(captured, action, view.Tab(sourceId), Tab(args["fallbackTabId"]),
                b, destinationId is { } target ? view.Tab(target) : null, new SystemIdSource(), now);
            foreach (var pair in result.Copies) {
                legacy.CopyTabMetadata(pair.Source, pair.Copy);
                var observation = (args["copyObservations"] as JsonArray)?.FirstOrDefault(o => Id(o!["tabId"]) == pair.Source);
                if (a.Tab(pair.Copy).Content.IsWebPage && observation is not null)
                    a.Tab(pair.Copy).Observe(observation["url"]?.GetValue<string>(), observation["title"]!.GetValue<string>(),
                        false, false, false, null);
            }
            if (result.CreatedFolder is { } created && args["folderColor"] is { } color)
                legacy.SetFolderMetadata(created, "color", color.DeepClone());
            var capturedSpaces = new List<SpaceState> { a.Capture(state.Spaces[0]) };
            if (b is not null) capturedSpaces.Add(b.Capture(state.Spaces[1]));
            var edited = legacy.Write(state with { Spaces = capturedSpaces.ToArray() })["session"]!["spaces"]!.AsArray();
            var outputSource = edited[0]!;
            foreach (var pair in result.GroupCopies) {
                var metadata = (spaces[0]!["splitGroups"] as JsonArray)?.FirstOrDefault(g => Id(g!["id"]) == pair.Source);
                if (metadata is null) continue;
                var copy = metadata.DeepClone(); copy["id"] = new JsonObject { ["rawValue"] = pair.Copy.ToString() };
                foreach (var field in new[] { "titleModifiedAt", "iconModifiedAt", "tintModifiedAt" }) copy[field] = NativeEditTimestamp.Encode(now);
                if (outputSource["splitGroups"] is not JsonArray) outputSource["splitGroups"] = new JsonArray();
                outputSource["splitGroups"]!.AsArray().Add(copy);
            }
            var changes = new JsonArray();
            foreach (var space in edited) {
                var groups = space!["tabs"]!.AsArray().Where(t => t!["splitGroupID"] is not null)
                    .Select(t => Id(t!["splitGroupID"])).ToHashSet();
                if (space["splitGroups"] is JsonArray metadata)
                    for (int i = metadata.Count - 1; i >= 0; i--) if (!groups.Contains(Id(metadata[i]!["id"]))) metadata.RemoveAt(i);
                changes.Add((JsonNode)new JsonObject {
                    ["space"] = space.DeepClone(),
                    ["tabId"] = null,
                    ["changed"] = true,
                    ["copies"] = new JsonArray(result.Copies.Select(p => (JsonNode)new JsonObject { ["source"] = p.Source.ToString(), ["copy"] = p.Copy.ToString() }).ToArray())
                });
            }
            var hint = new SessionSelectionHint().SelectTab(view, sourceId, result.Selection);
            if (destinationId is { } moved) {
                hint.SelectTab(view, moved, result.DestinationSelection);
                if (action.Follow) hint.SelectSpace(moved);
            }
            var next = ApplyTransfer(document, edited.Select(s => s!.AsObject()).ToArray());
            var output = TransferOutput(new JsonObject {
                ["changes"] = changes,
                [SessionSelectionHint.Key] = hint.Encode()
            });
            return new(this, expected, next, output);
        } catch (BrowserRuleException error) {
            return new(this, expected, document, TransferOutput(new JsonObject { ["error"] = error.Code }), error.Code);
        }
    }

    #endregion
}
