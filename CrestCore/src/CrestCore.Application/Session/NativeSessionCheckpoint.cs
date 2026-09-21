using System.Text.Json;
using System.Text.Json.Nodes;

namespace CrestCore.Application;

public sealed class NativeSessionCheckpoint {
    #region Variables

    private readonly SessionDocument document;
    private readonly JsonObject selection;
    private readonly System.Collections.Concurrent.ConcurrentDictionary<string, byte[]> parts = new();

    #endregion

    #region Constructors

    internal NativeSessionCheckpoint(SessionDocument document, JsonObject selection) { this.document = document; this.selection = selection; }

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
            foreach (var field in document.Metadata.Where(f => f.Key != "selectedSpaceID")) { writer.WritePropertyName(field.Key); if (field.Value is { } value) value.WriteTo(writer); else writer.WriteNullValue(); }
            writer.WritePropertyName("selectedSpaceID"); selection["selectedSpaceID"]!.WriteTo(writer);
            writer.WriteStartArray("spaces");
            var tabs = selection["selectedTabs"]!.AsArray().ToDictionary(v => NativeSessionAuthority.Id(v!["spaceID"]), v => v!["tabID"]);
            foreach (var space in document.Spaces) {
                writer.WriteStartObject();
                foreach (var field in space.Metadata.Where(f => f.Key != "selectedTabID")) { writer.WritePropertyName(field.Key); if (field.Value is { } value) value.WriteTo(writer); else writer.WriteNullValue(); }
                foreach (var section in space.Sections) {
                    writer.WriteStartArray(section.Key);
                    if (section.Key != "history") foreach (var record in section.Value) record.WriteTo(writer);
                    writer.WriteEndArray();
                }
                writer.WritePropertyName("selectedTabID");
                if (tabs.GetValueOrDefault(NativeSessionAuthority.Id(space.Metadata["id"])) is { } selected) selected.WriteTo(writer);
                else writer.WriteNullValue();
                writer.WriteEndObject();
            }
            writer.WriteEndArray(); writer.WriteEndObject();
        }
        return stream.ToArray();
    }

    #endregion
}
