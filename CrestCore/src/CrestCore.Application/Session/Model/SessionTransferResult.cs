using System.Text.Json.Nodes;

namespace CrestCore.Application;

/// <summary>The edited source and destination Spaces of a tab transfer, and the
/// tab each side's window should show afterwards.</summary>
internal sealed record SessionTransferResult(JsonObject Source, JsonObject Destination,
    Guid? SourceSelection, Guid? DestinationSelection) {
    #region Actions - Encoding

    /// One window's answer, for a move between two Spaces it holds.
    public JsonObject Encode(SessionSelectionHint hint) => new() {
        ["source"] = Source.DeepClone(),
        ["destination"] = Destination.DeepClone(),
        [SessionSelectionHint.Key] = hint.Encode()
    };

    /// Two windows' answers, for a move between two workspaces.
    public JsonObject Encode(SessionSelectionHint source, SessionSelectionHint destination) => new() {
        ["source"] = Source.DeepClone(),
        ["destination"] = Destination.DeepClone(),
        ["sourceSelection"] = source.Encode(),
        ["destinationSelection"] = destination.Encode()
    };

    #endregion
}
