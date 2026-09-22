using System.Text.Json.Nodes;

using CrestCore.Domain;

namespace CrestCore.Application;

/// Compact projections for transfer previews and authority commands. Native
/// image bytes, archive, and history remain with their existing owners.
public static class NativeTabTransfer {
    #region Variables

    private static readonly DateTimeOffset Epoch = new(2001, 1, 1, 0, 0, 0, TimeSpan.Zero);

    #endregion

    #region Actions - Tab transfer

    public static JsonObject Evaluate(JsonObject source, JsonObject destination, JsonObject arguments, double now) {
        LegacySessionDocument Document(JsonObject space) => new(new() {
            ["session"] = new JsonObject { ["spaces"] = new JsonArray(space.DeepClone()), ["selectedSpaceID"] = space["id"]!.DeepClone() }
        });
        var sourceDocument = Document(source); var destinationDocument = Document(destination);
        var sourceState = sourceDocument.Read(new SystemIdSource()); var destinationState = destinationDocument.Read(new SystemIdSource());
        var a = BrowserTabCollection.Restore(sourceState.Spaces.Single());
        var b = BrowserTabCollection.Restore(destinationState.Spaces.Single());
        var tab = NativeSessionAuthority.Id(arguments["tabId"]);
        Guid? Optional(string key) => arguments[key] is { } value ? NativeSessionAuthority.Id(value) : null;
        var selected = a.TransferTo(b, tab, sourceState.Spaces[0].SelectedTabId, Optional("fallbackTabId"),
            arguments["placement"] is { } p ? Enum.Parse<TabPlacement>(p.GetValue<string>(), true) : null,
            arguments["folderId"] is { } f ? NativeSessionAuthority.Id(f) : null,
            Optional("before"), arguments["afterSelection"]?.GetValue<bool>() == true,
            destinationState.Spaces[0].SelectedTabId, Epoch.AddSeconds(now));
        sourceDocument.TransferTabMetadata(tab, destinationDocument);
        var targetSelection = destinationState.Spaces[0].SelectedTabId;
        if (arguments["select"]?.GetValue<bool>() == true) { b.Tab(tab).Activate(Epoch.AddSeconds(now)); targetSelection = tab; }
        JsonNode Write(LegacySessionDocument document, WorkspaceState state, BrowserTabCollection collection, Guid? selection) {
            var result = document.Write(state with { Spaces = [collection.Capture(state.Spaces[0], selection)] })["session"]!["spaces"]![0]!.DeepClone();
            if (result["splitGroups"] is JsonArray groups) {
                var retained = collection.Tabs.Where(t => t.SplitGroupId is not null).Select(t => t.SplitGroupId!.Value).ToHashSet();
                for (int i = groups.Count - 1; i >= 0; i--)
                    if (!retained.Contains(NativeSessionAuthority.Id(groups[i]!["id"]))) groups.RemoveAt(i);
            }
            return result;
        }
        return new() {
            ["source"] = Write(sourceDocument, sourceState, a, selected),
            ["destination"] = Write(destinationDocument, destinationState, b, targetSelection)
        };
    }

    #endregion
}
