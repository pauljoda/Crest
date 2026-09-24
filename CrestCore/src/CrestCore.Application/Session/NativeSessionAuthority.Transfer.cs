using System.Text.Json.Nodes;

using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

public sealed partial class NativeSessionAuthority {
    #region Actions - Transfer

    private SpaceState TransferSpace(Guid spaceId, Guid profileId) {
        if (PendingDeletion(session, spaceId) is not null) throw new BrowserRuleException(BrowserRuleCodes.SpaceDeletionInProgress);
        var space = session.Spaces.SingleOrDefault(s => s.Id == spaceId)
            ?? throw new BrowserRuleException(BrowserRuleCodes.UnknownSpace);
        if (space.ProfileId != profileId) throw new BrowserRuleException(BrowserRuleCodes.WrongProfileIdentity);
        return space;
    }

    private NativeSessionCommand PrepareTabTransfer(ulong expected, JsonObject request) {
        var sourceId = Id(request["spaceId"]); var destinationId = Id(request["destinationSpaceId"]);
        if (sourceId == destinationId) throw new BrowserRuleException(BrowserRuleCodes.SameSpaceTransfer);
        var source = TransferSpace(sourceId, Id(request["profileId"]));
        var destination = TransferSpace(destinationId, Id(request["destinationProfileId"]));
        var args = request["arguments"]!.AsObject(); var view = SessionView.Decode(request[SessionView.Key]);
        var result = NativeTabTransfer.Evaluate(source, view, destination, view, NativeTabTransfer.Arguments.Decode(args), Now(request));
        var next = Replacing(session, result.Source, result.Destination);
        Validate(next);
        var hint = new SessionSelectionHint().SelectTab(view, sourceId, result.SourceSelection)
            .SelectTab(view, destinationId, result.DestinationSelection);
        if (args["select"]?.GetValue<bool>() == true) hint.SelectSpace(destinationId);
        return new(this, expected, next, Output(result.Encode(hint)));
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
            var args = NativeTabTransfer.Arguments.Decode(request["arguments"]!.AsObject());
            if (destination.session.Spaces.Any(s => s.Tabs.Any(t => t.Id == args.TabId)
                || s.ArchivedTabs.Any(archived => archived.Tab.Id == args.TabId)))
                throw new BrowserRuleException(BrowserRuleCodes.DuplicateTab);
            // A window transfer keeps the exact profile and makes a current tab.
            args = args with { Placement = TabPlacement.Current, FolderId = null, Before = null, AfterSelection = true };
            var sourceView = SessionView.Decode(request["sourceView"]);
            var destinationView = SessionView.Decode(request["destinationView"]);
            var result = NativeTabTransfer.Evaluate(a, sourceView, b, destinationView, args, Now(request));
            // Each window gets its own hint: the source shows its fallback, the
            // destination the moved tab when the move selects it.
            var sourceHint = new SessionSelectionHint().SelectTab(sourceView, spaceId, result.SourceSelection);
            var destinationHint = new SessionSelectionHint().SelectTab(destinationView, spaceId, result.DestinationSelection);
            if (args.Select) destinationHint.SelectSpace(spaceId);
            var nextSource = Replacing(source.session, result.Source);
            var nextDestination = Replacing(destination.session, result.Destination);
            Validate(nextSource); Validate(nextDestination);
            return new(source, new(source, sourceRevision, nextSource, []), destination,
                new(destination, destinationRevision, nextDestination, []), Output(result.Encode(sourceHint, destinationHint)));
        }
    }

    #endregion
}
