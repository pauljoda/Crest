using System.Text.Json.Nodes;

using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

/// Moves one tab between two Spaces' organizations. Native image bytes, archive
/// and history remain with their existing owners.
internal static class NativeTabTransfer {
    #region Variables

    /// What a transfer asks for: the tab, where it lands and whether the
    /// destination window then shows it.
    internal sealed record Arguments(Guid TabId, Guid? FallbackTabId, TabPlacement? Placement, Guid? FolderId, Guid? Before,
        bool AfterSelection, bool Select) {
        #region Actions - Decoding

        public static Arguments Decode(JsonObject value) {
            Guid? Optional(string key) => value[key] is { } id ? NativeSessionAuthority.Id(id) : null;
            return new(NativeSessionAuthority.Id(value["tabId"]), Optional("fallbackTabId"),
                value["placement"] is { } placement
                    ? TabPlacementCodes.Parse(placement.GetValue<string>()) ?? throw new ProtocolException(ProtocolErrorCodes.InvalidPlacement)
                    : null,
                Optional("folderId"), Optional("before"), value["afterSelection"]?.GetValue<bool>() == true,
                value["select"]?.GetValue<bool>() == true);
        }

        #endregion
    }

    #endregion

    #region Actions - Tab transfer

    internal static SessionTransferResult Evaluate(SpaceState source, SessionView sourceView, SpaceState destination,
        SessionView destinationView, Arguments arguments, DateTimeOffset now) {
        var a = BrowserTabCollection.Restore(source);
        var b = BrowserTabCollection.Restore(destination);
        var viewedDestination = destinationView.Tab(destination.Id);
        var selected = a.TransferTo(b, arguments.TabId, sourceView.Tab(source.Id), arguments.FallbackTabId, arguments.Placement,
            arguments.FolderId, arguments.Before, arguments.AfterSelection, viewedDestination, now);
        var targetSelection = viewedDestination;
        if (arguments.Select) { b.Tab(arguments.TabId).Activate(now); targetSelection = arguments.TabId; }
        a.PruneSplitMetadata(); b.PruneSplitMetadata();
        return new(a.Capture(source), b.Capture(destination), selected, targetSelection);
    }

    #endregion
}
