using System.Text.Json;

namespace CrestCore.Application;

/// An immutable, encodable revision of the session: the `core` part holds the
/// Spaces and their records without history, and each Space's history is its
/// own part. Selection is window state, so no part carries it.
public sealed class NativeSessionCheckpoint {
    #region Variables

    private readonly SessionDocument document;
    private readonly System.Collections.Concurrent.ConcurrentDictionary<string, byte[]> parts = new();

    #endregion

    #region Constructors

    internal NativeSessionCheckpoint(SessionDocument document) => this.document = document;

    #endregion

    #region Actions - Checkpoint

    public byte[] Read(string part) => parts.GetOrAdd(part, Encode);

    private byte[] Encode(string part) {
        if (part != "core") {
            var id = Guid.Parse(part);
            var history = document.Spaces.Single(s => NativeSessionAuthority.Id(s.Metadata["id"]) == id).History;
            using var historyStream = new MemoryStream();
            using (var writer = new Utf8JsonWriter(historyStream)) { writer.WriteStartArray(); foreach (var entry in history) entry.WriteTo(writer); writer.WriteEndArray(); }
            return historyStream.ToArray();
        }
        using var stream = new MemoryStream();
        using (var writer = new Utf8JsonWriter(stream)) {
            writer.WriteStartObject();
            foreach (var field in document.Metadata.Where(f => f.Key != LegacySelectionFields.SelectedSpace)) { writer.WritePropertyName(field.Key); if (field.Value is { } value) value.WriteTo(writer); else writer.WriteNullValue(); }
            writer.WriteStartArray("spaces");
            foreach (var space in document.Spaces) {
                writer.WriteStartObject();
                foreach (var field in space.Metadata.Where(f => f.Key != LegacySelectionFields.SelectedTab)) { writer.WritePropertyName(field.Key); if (field.Value is { } value) value.WriteTo(writer); else writer.WriteNullValue(); }
                foreach (var section in space.Sections) {
                    writer.WriteStartArray(section.Key);
                    if (section.Key != "history") foreach (var record in section.Value) record.WriteTo(writer);
                    writer.WriteEndArray();
                }
                writer.WriteEndObject();
            }
            writer.WriteEndArray(); writer.WriteEndObject();
        }
        return stream.ToArray();
    }

    #endregion
}
