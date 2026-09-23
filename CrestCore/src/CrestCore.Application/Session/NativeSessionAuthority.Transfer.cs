using System.Text;
using System.Text.Json.Nodes;

using CrestCore.Domain;

namespace CrestCore.Application;

public sealed partial class NativeSessionAuthority {
    #region Actions - Transfer

    private SpaceDocument TransferSpace(Guid spaceId, Guid profileId) {
        if (PendingDeletion(document.Metadata, spaceId) is not null) throw new BrowserRuleException(BrowserRuleCodes.SpaceDeletionInProgress);
        var space = document.Spaces.SingleOrDefault(s => Id(s.Metadata["id"]) == spaceId)
            ?? throw new BrowserRuleException(BrowserRuleCodes.UnknownSpace);
        if (Id(space.Metadata["profile"]!["id"]) != profileId) throw new BrowserRuleException(BrowserRuleCodes.WrongProfileIdentity);
        return space;
    }

    private static JsonObject TransferProjection(SpaceDocument space) {
        var value = space.Metadata.DeepClone().AsObject();
        foreach (var section in Sections) value[section] = new JsonArray(section is SpaceSections.HistorySection or SpaceSections.ArchivedTabsSection ? [] :
            space.Sections[section].Select(n => n.DeepClone()).ToArray());
        return value;
    }

    private static SessionDocument ApplyTransfer(SessionDocument document, params JsonObject[] edits) {
        var spaces = document.Spaces.Select(space => {
            var edited = edits.FirstOrDefault(n => Id(n["id"]) == Id(space.Metadata["id"]));
            if (edited is null) return space;
            var sections = space.Sections.ToDictionary(p => p.Key, p => p.Value);
            foreach (var section in new[] { SpaceSections.TabsSection, SpaceSections.FoldersSection }) sections[section] = edited[section]!.AsArray().Select(n => n!.DeepClone()).ToArray();
            if (edited[SpaceSections.ArchivedTabsSection] is JsonArray archive && archive.Count > 0)
                sections[SpaceSections.ArchivedTabsSection] = space.ArchivedTabs.Concat(archive.Select(n => n!.DeepClone())).ToArray();
            return new SpaceDocument(SpaceFields(edited), sections);
        }).ToArray();
        var next = new SessionDocument(document.Metadata, spaces); Validate(next); return next;
    }

    private static byte[] TransferOutput(JsonObject result) {
        var bytes = Encoding.UTF8.GetBytes(result.ToJsonString());
        if (bytes.Length > NativeSessionEditor.MaximumBytes) throw new BrowserRuleException(BrowserRuleCodes.SessionEditLimit);
        return bytes;
    }

    private NativeSessionCommand PrepareTabTransfer(ulong expected, JsonObject request) {
        var sourceId = Id(request["spaceId"]); var destinationId = Id(request["destinationSpaceId"]);
        if (sourceId == destinationId) throw new BrowserRuleException(BrowserRuleCodes.SameSpaceTransfer);
        var source = TransferSpace(sourceId, Id(request["profileId"]));
        var destination = TransferSpace(destinationId, Id(request["destinationProfileId"]));
        var args = request["arguments"]!.AsObject(); var view = SessionView.Decode(request[SessionView.Key]);
        var result = NativeTabTransfer.Evaluate(TransferProjection(source), view, TransferProjection(destination), view,
            args, request["now"]!.GetValue<double>());
        var next = ApplyTransfer(document, result.Source, result.Destination);
        var hint = new SessionSelectionHint().SelectTab(view, sourceId, result.SourceSelection)
            .SelectTab(view, destinationId, result.DestinationSelection);
        if (args["select"]?.GetValue<bool>() == true) hint.SelectSpace(destinationId);
        return new(this, expected, next, TransferOutput(result.Encode(hint)));
    }

    public static NativeSessionTransfer PrepareTransfer(NativeSessionAuthority source, ulong sourceRevision,
        NativeSessionAuthority destination, ulong destinationRevision, ReadOnlySpan<byte> bytes) {
        lock (Gate) {
            source.RequireWritable(); destination.RequireWritable();
            if (ReferenceEquals(source, destination)) throw new BrowserRuleException(BrowserRuleCodes.SameSessionTransfer);
            if (sourceRevision != source.Revision || destinationRevision != destination.Revision)
                throw new BrowserRuleException(BrowserRuleCodes.StaleSessionRevision);
            if (source.workspaceKind != BrowserWorkspaceKind.Temporary && destination.workspaceKind != BrowserWorkspaceKind.Temporary)
                throw new BrowserRuleException(BrowserRuleCodes.TemporaryWorkspaceRequired);
            if (source.privateBrowsing != destination.privateBrowsing) throw new BrowserRuleException(BrowserRuleCodes.PrivateWorkspaceBoundary);
            if (!ReferenceEquals(source.borrowedSource ?? source, destination.borrowedSource ?? destination))
                throw new BrowserRuleException(BrowserRuleCodes.DifferentProfileOwner);
            var request = Parse(bytes);
            if (request["version"]!.GetValue<int>() != 1) throw new BrowserRuleException(BrowserRuleCodes.VersionMismatch);
            var spaceId = Id(request["spaceId"]); var profileId = Id(request["profileId"]);
            source.RequireAccessible(spaceId); destination.RequireAccessible(spaceId);
            var a = source.TransferSpace(spaceId, profileId); var b = destination.TransferSpace(spaceId, profileId);
            var args = request["arguments"]!.DeepClone().AsObject();
            var tabId = Id(args["tabId"]);
            if (destination.document.Spaces.Any(s => s.Tabs.Any(t => Id(t["id"]) == tabId)
                || s.ArchivedTabs.Any(t => Id(t["tab"]!["id"]) == tabId)))
                throw new BrowserRuleException(BrowserRuleCodes.DuplicateTab);
            // A window transfer keeps the exact profile and makes a current tab.
            args["placement"] = TabPlacementCodes.Current; args["folderId"] = null; args["before"] = null; args["afterSelection"] = true;
            var sourceView = SessionView.Decode(request["sourceView"]);
            var destinationView = SessionView.Decode(request["destinationView"]);
            var result = NativeTabTransfer.Evaluate(TransferProjection(a), sourceView,
                TransferProjection(b), destinationView, args, request["now"]!.GetValue<double>());
            // Each window gets its own hint: the source shows its fallback, the
            // destination the moved tab when the move selects it.
            var sourceHint = new SessionSelectionHint().SelectTab(sourceView, spaceId, result.SourceSelection);
            var destinationHint = new SessionSelectionHint().SelectTab(destinationView, spaceId, result.DestinationSelection);
            if (args["select"]?.GetValue<bool>() == true) destinationHint.SelectSpace(spaceId);
            var nextSource = ApplyTransfer(source.document, result.Source);
            var nextDestination = ApplyTransfer(destination.document, result.Destination);
            return new(source, new(source, sourceRevision, nextSource, []), destination,
                new(destination, destinationRevision, nextDestination, []), TransferOutput(result.Encode(sourceHint, destinationHint)));
        }
    }

    #endregion
}
