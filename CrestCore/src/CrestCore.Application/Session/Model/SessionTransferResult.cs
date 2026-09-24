using System.Text.Json.Nodes;

using CrestCore.Contracts;

namespace CrestCore.Application;

/// <summary>The edited source and destination Spaces of a tab transfer, and the
/// tab each side's window shows afterwards.</summary>
internal sealed record SessionTransferResult(SpaceState Source, SpaceState Destination,
    Guid? SourceSelection, Guid? DestinationSelection) {
    #region Actions - Encoding

    /// The answer the native caller reads: both edited Spaces.
    public JsonObject Encode() => new() {
        ["source"] = Projection(Source),
        ["destination"] = Projection(Destination)
    };

    /// A transfer changes organization only, so its answer leaves out the
    /// Spaces' history and archive.
    private static JsonObject Projection(SpaceState space) =>
        StoredSessionCodec.Encode(space with { History = [], ArchivedTabs = [] });

    #endregion
}
