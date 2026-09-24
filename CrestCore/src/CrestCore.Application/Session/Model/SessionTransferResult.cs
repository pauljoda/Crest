using System.Text.Json.Nodes;

using CrestCore.Contracts;

namespace CrestCore.Application;

/// <summary>The edited source and destination Spaces of a tab transfer, and the
/// tab each side's window should show afterwards.</summary>
internal sealed record SessionTransferResult(SpaceState Source, SpaceState Destination,
    Guid? SourceSelection, Guid? DestinationSelection) {
    #region Actions - Encoding

    /// One window's answer, for a move between two Spaces it holds.
    public JsonObject Encode(SessionSelectionHint hint) => new() {
        ["source"] = Projection(Source),
        ["destination"] = Projection(Destination),
        [SessionSelectionHint.Key] = hint.Encode()
    };

    /// Two windows' answers, for a move between two workspaces.
    public JsonObject Encode(SessionSelectionHint source, SessionSelectionHint destination) => new() {
        ["source"] = Projection(Source),
        ["destination"] = Projection(Destination),
        ["sourceSelection"] = source.Encode(),
        ["destinationSelection"] = destination.Encode()
    };

    /// A transfer changes organization only, so its answer leaves out the
    /// Spaces' history and archive.
    private static JsonObject Projection(SpaceState space) =>
        StoredSessionCodec.Encode(space with { History = [], ArchivedTabs = [] });

    #endregion
}
