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

    internal static SessionTransferResult Evaluate(JsonObject source, SessionView sourceView, JsonObject destination, SessionView destinationView,
        JsonObject arguments, double now) {
        LegacySessionDocument Document(JsonObject space) => new(new() {
            ["session"] = new JsonObject { ["spaces"] = new JsonArray(space.DeepClone()) }
        });
        var sourceDocument = Document(source); var destinationDocument = Document(destination);
        var sourceState = sourceDocument.Read(new SystemIdSource()); var destinationState = destinationDocument.Read(new SystemIdSource());
        var a = BrowserTabCollection.Restore(sourceState.Spaces.Single());
        var b = BrowserTabCollection.Restore(destinationState.Spaces.Single());
        var tab = NativeSessionAuthority.Id(arguments["tabId"]);
        Guid? Optional(string key) => arguments[key] is { } value ? NativeSessionAuthority.Id(value) : null;
        var viewedDestination = destinationView.Tab(destinationState.Spaces[0].Id);
        var selected = a.TransferTo(b, tab, sourceView.Tab(sourceState.Spaces[0].Id), Optional("fallbackTabId"),
            arguments["placement"] is { } p ? Enum.Parse<TabPlacement>(p.GetValue<string>(), true) : null,
            arguments["folderId"] is { } f ? NativeSessionAuthority.Id(f) : null,
            Optional("before"), arguments["afterSelection"]?.GetValue<bool>() == true,
            viewedDestination, Epoch.AddSeconds(now));
        sourceDocument.TransferTabMetadata(tab, destinationDocument);
        var targetSelection = viewedDestination;
        if (arguments["select"]?.GetValue<bool>() == true) { b.Tab(tab).Activate(Epoch.AddSeconds(now)); targetSelection = tab; }
        JsonObject Write(LegacySessionDocument document, WorkspaceState state, BrowserTabCollection collection) {
            var result = document.Write(state with { Spaces = [collection.Capture(state.Spaces[0])] })["session"]!["spaces"]![0]!.DeepClone().AsObject();
            if (result["splitGroups"] is JsonArray groups) {
                var retained = collection.Tabs.Where(t => t.SplitGroupId is not null).Select(t => t.SplitGroupId!.Value).ToHashSet();
                for (int i = groups.Count - 1; i >= 0; i--)
                    if (!retained.Contains(NativeSessionAuthority.Id(groups[i]!["id"]))) groups.RemoveAt(i);
            }
            return result;
        }
        return new(Write(sourceDocument, sourceState, a), Write(destinationDocument, destinationState, b), selected, targetSelection);
    }

    #endregion
}
