using System.Collections.Concurrent;
using System.Text;
using System.Text.Json.Nodes;

namespace CrestCore.Application;

/// An immutable, encodable revision of the session: the `core` part holds the
/// Spaces and their records without history, and each Space's history is its
/// own part, named by the Space's identity. Selection is window state, so no
/// part carries it.
public sealed class NativeSessionCheckpoint {
    #region Variables

    internal const string CorePart = "core";

    private readonly SessionDocument document;
    private readonly ConcurrentDictionary<string, byte[]> parts = new();

    #endregion

    #region Constructors

    internal NativeSessionCheckpoint(SessionDocument document) => this.document = document;

    #endregion

    #region Actions - Checkpoint

    public byte[] Read(string part) => parts.GetOrAdd(part, Encode);

    private byte[] Encode(string part) {
        JsonNode value = part == CorePart
            ? StoredSessionCodec.Encode(document with { Spaces = document.Spaces.Select(space => space with { History = [] }).ToArray() })
            : StoredSessionCodec.EncodeHistory(document.Spaces.Single(space => space.Id == Guid.Parse(part)).History);
        return Encoding.UTF8.GetBytes(value.ToJsonString());
    }

    #endregion
}
