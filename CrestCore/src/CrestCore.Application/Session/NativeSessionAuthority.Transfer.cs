using System.Text;
using System.Text.Json.Nodes;

using CrestCore.Domain;

namespace CrestCore.Application;

public sealed partial class NativeSessionAuthority {
    #region Actions - Transfer

    private SpaceDocument TransferSpace(Guid spaceId, Guid profileId) {
        if (PendingDeletion(document.Metadata, spaceId) is not null) throw new BrowserRuleException("space_deletion_in_progress");
        var space = document.Spaces.SingleOrDefault(s => Id(s.Metadata["id"]) == spaceId)
            ?? throw new BrowserRuleException("unknown_space");
        if (Id(space.Metadata["profile"]!["id"]) != profileId) throw new BrowserRuleException("wrong_profile_identity");
        return space;
    }

    private static JsonObject TransferProjection(SpaceDocument space, JsonNode window) {
        var value = space.Metadata.DeepClone().AsObject();
        value["selectedTabID"] = window["selectedTabs"]!.AsArray()
            .FirstOrDefault(n => Id(n!["spaceID"]) == Id(value["id"]))?["tabID"]?.DeepClone();
        foreach (var section in Sections) value[section] = new JsonArray(section is "history" or "archivedTabs" ? [] :
            space.Sections[section].Select(n => n.DeepClone()).ToArray());
        return value;
    }

    private static SessionDocument ApplyTransfer(SessionDocument document, JsonNode window, params JsonObject[] edits) {
        var metadata = document.Metadata.DeepClone().AsObject();
        metadata["selectedSpaceID"] = window["selectedSpaceID"]!.DeepClone();
        var selections = window["selectedTabs"]!.AsArray().ToDictionary(n => Id(n!["spaceID"]), n => n!["tabID"]);
        var spaces = document.Spaces.Select(space => {
            var value = space.Metadata.DeepClone().AsObject();
            value["selectedTabID"] = selections.GetValueOrDefault(Id(value["id"]))?.DeepClone();
            var edited = edits.FirstOrDefault(n => Id(n["id"]) == Id(value["id"]));
            if (edited is null) return new SpaceDocument(value, space.Sections);
            var sections = space.Sections.ToDictionary(p => p.Key, p => p.Value);
            foreach (var section in new[] { "tabs", "folders" }) sections[section] = edited[section]!.AsArray().Select(n => n!.DeepClone()).ToArray();
            if (edited["archivedTabs"] is JsonArray archive && archive.Count > 0)
                sections["archivedTabs"] = space.ArchivedTabs.Concat(archive.Select(n => n!.DeepClone())).ToArray();
            return new SpaceDocument(Fields(edited, Sections), sections);
        }).ToArray();
        var next = new SessionDocument(metadata, spaces); Validate(next); return next;
    }

    private static byte[] TransferOutput(JsonObject result) {
        var bytes = Encoding.UTF8.GetBytes(result.ToJsonString());
        if (bytes.Length > NativeSessionEditor.MaximumBytes) throw new BrowserRuleException("session_edit_limit");
        return bytes;
    }

    private NativeSessionCommand PrepareTabTransfer(ulong expected, JsonObject request) {
        var sourceId = Id(request["spaceId"]); var destinationId = Id(request["destinationSpaceId"]);
        if (sourceId == destinationId) throw new BrowserRuleException("same_space_transfer");
        var source = TransferSpace(sourceId, Id(request["profileId"]));
        var destination = TransferSpace(destinationId, Id(request["destinationProfileId"]));
        var args = request["arguments"]!.AsObject(); var window = request["window"]!.DeepClone();
        var result = NativeTabTransfer.Evaluate(TransferProjection(source, window), TransferProjection(destination, window),
            args, request["now"]!.GetValue<double>());
        if (args["select"]?.GetValue<bool>() == true) window["selectedSpaceID"] = destination.Metadata["id"]!.DeepClone();
        var next = ApplyTransfer(document, window, result["source"]!.AsObject(), result["destination"]!.AsObject());
        return new(this, expected, next, TransferOutput(result));
    }

    public static NativeSessionTransfer PrepareTransfer(NativeSessionAuthority source, ulong sourceRevision,
        NativeSessionAuthority destination, ulong destinationRevision, ReadOnlySpan<byte> bytes) {
        lock (Gate) {
            source.RequireWritable(); destination.RequireWritable();
            if (ReferenceEquals(source, destination)) throw new BrowserRuleException("same_session_transfer");
            if (sourceRevision != source.Revision || destinationRevision != destination.Revision)
                throw new BrowserRuleException("stale_session_revision");
            if (source.workspaceKind != BrowserWorkspaceKind.Temporary && destination.workspaceKind != BrowserWorkspaceKind.Temporary)
                throw new BrowserRuleException("temporary_workspace_required");
            if (source.privateBrowsing != destination.privateBrowsing) throw new BrowserRuleException("private_workspace_boundary");
            if (!ReferenceEquals(source.borrowedSource ?? source, destination.borrowedSource ?? destination))
                throw new BrowserRuleException("different_profile_owner");
            var request = Parse(bytes);
            if (request["version"]!.GetValue<int>() != 1) throw new BrowserRuleException("version_mismatch");
            var spaceId = Id(request["spaceId"]); var profileId = Id(request["profileId"]);
            source.RequireAccessible(spaceId); destination.RequireAccessible(spaceId);
            var a = source.TransferSpace(spaceId, profileId); var b = destination.TransferSpace(spaceId, profileId);
            var args = request["arguments"]!.DeepClone().AsObject();
            var tabId = Id(args["tabId"]);
            if (destination.document.Spaces.Any(s => s.Tabs.Any(t => Id(t["id"]) == tabId)
                || s.ArchivedTabs.Any(t => Id(t["tab"]!["id"]) == tabId)))
                throw new BrowserRuleException("duplicate_tab");
            // A window transfer keeps the exact profile and makes a current tab.
            args["placement"] = "current"; args["folderId"] = null; args["before"] = null; args["afterSelection"] = true;
            var result = NativeTabTransfer.Evaluate(TransferProjection(a, request["sourceWindow"]!),
                TransferProjection(b, request["destinationWindow"]!), args, request["now"]!.GetValue<double>());
            var destinationWindow = request["destinationWindow"]!.DeepClone();
            if (args["select"]?.GetValue<bool>() == true) destinationWindow["selectedSpaceID"] = b.Metadata["id"]!.DeepClone();
            var nextSource = ApplyTransfer(source.document, request["sourceWindow"]!, result["source"]!.AsObject());
            var nextDestination = ApplyTransfer(destination.document, destinationWindow, result["destination"]!.AsObject());
            return new(source, new(source, sourceRevision, nextSource, []), destination,
                new(destination, destinationRevision, nextDestination, []), TransferOutput(result));
        }
    }

    internal static byte[] TransferSelection(SessionDocument value) => Encoding.UTF8.GetBytes(new JsonObject {
        ["selectedSpaceID"] = value.Metadata["selectedSpaceID"]!.DeepClone(),
        ["selectedTabs"] = new JsonArray(value.Spaces.Select(s => (JsonNode)new JsonObject { ["spaceID"] = s.Metadata["id"]!.DeepClone(), ["tabID"] = s.Metadata["selectedTabID"]?.DeepClone() }).ToArray())
    }.ToJsonString());

    #endregion
}
