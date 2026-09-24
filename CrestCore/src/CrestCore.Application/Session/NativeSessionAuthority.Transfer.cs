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

    private NativeSessionCommand PrepareTabTransfer(JsonObject request) {
        var sourceId = Id(request["spaceId"]); var destinationId = Id(request["destinationSpaceId"]);
        if (sourceId == destinationId) throw new BrowserRuleException(BrowserRuleCodes.SameSpaceTransfer);
        var source = TransferSpace(sourceId, Id(request["profileId"]));
        var destination = TransferSpace(destinationId, Id(request["destinationProfileId"]));
        var args = request["arguments"]!.AsObject();
        var followUp = new WindowFollowUp(IssuingWindow(request));
        var arguments = NativeTabTransfer.Arguments.Decode(args);
        var result = NativeTabTransfer.Evaluate(source, followUp, destination, followUp, arguments, Now(request));
        var next = Replacing(session, result.Source, result.Destination);
        Validate(next);
        followUp.ShowTab(sourceId, result.SourceSelection).ShowTab(destinationId, result.DestinationSelection);
        if (arguments.Select) followUp.ShowSpace(destinationId);
        return new(this, session, next, Output(result.Encode()), followUp: followUp);
    }

    public static NativeSessionTransfer PrepareTransfer(NativeSessionAuthority source, NativeSessionAuthority destination,
        ReadOnlySpan<byte> bytes) {
        lock (Gate) {
            source.RequireWritable(); destination.RequireWritable();
            if (ReferenceEquals(source, destination)) throw new BrowserRuleException(BrowserRuleCodes.SameSessionTransfer);
            if (source.workspaceKind != WorkspaceKind.Borrowed && destination.workspaceKind != WorkspaceKind.Borrowed)
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
            // Each window follows its own side: the source shows the tab it
            // showed before the moved one, the destination the moved tab when
            // the move selects it.
            var sourceFollowUp = new WindowFollowUp(source.device?.Snapshot(source.workspaceId, OptionalId(request["sourceWindowId"])));
            var destinationFollowUp = new WindowFollowUp(
                destination.device?.Snapshot(destination.workspaceId, OptionalId(request["destinationWindowId"])));
            var result = NativeTabTransfer.Evaluate(a, sourceFollowUp, b, destinationFollowUp, args, Now(request));
            sourceFollowUp.ShowTab(spaceId, result.SourceSelection);
            destinationFollowUp.ShowTab(spaceId, result.DestinationSelection);
            if (args.Select) destinationFollowUp.ShowSpace(spaceId);
            var nextSource = Replacing(source.session, result.Source);
            var nextDestination = Replacing(destination.session, result.Destination);
            Validate(nextSource); Validate(nextDestination);
            return new(source, new(source, source.session, nextSource, [], followUp: sourceFollowUp), destination,
                new(destination, destination.session, nextDestination, [], followUp: destinationFollowUp), Output(result.Encode()));
        }
    }

    #endregion
}
