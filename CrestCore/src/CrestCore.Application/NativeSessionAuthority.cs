using System.Text.Json;
using System.Text.Json.Nodes;
using CrestCore.Domain;

namespace CrestCore.Application;

/// Owns the native app's durable session during the command-by-command migration.
/// Native views propose value deltas; only an accepted revision becomes visible.
/// Published documents are immutable, so storage can serialize an older checkpoint
/// on its worker while the UI continues editing the current revision.
public sealed partial class NativeSessionAuthority
{
    public const int MaximumBytes = 64 * 1024 * 1024;
    internal static readonly object Gate = new();
    private SessionDocument document;
    internal sealed record SessionDocument(JsonObject Metadata, IReadOnlyList<SpaceDocument> Spaces);
    internal sealed record SpaceDocument(JsonObject Metadata, IReadOnlyDictionary<string, IReadOnlyList<JsonNode>> Sections);
    public ulong Revision { get; private set; } = 1;

    public NativeSessionAuthority(ReadOnlySpan<byte> bytes)
    {
        var input = Parse(bytes);
        document = new(Fields(input, ["spaces"]), input["spaces"]!.AsArray().Select(node =>
            new SpaceDocument(Fields(node!.AsObject(), Sections), Sections.ToDictionary(section => section,
                section => (IReadOnlyList<JsonNode>)node[section]!.AsArray().Select(item => item!.DeepClone()).ToArray()))).ToArray());
        Validate(document);
    }

    private static JsonObject Parse(ReadOnlySpan<byte> bytes)
    {
        if (bytes.Length == 0 || bytes.Length > MaximumBytes) throw new BrowserRuleException("session_size_limit");
        return JsonNode.Parse(bytes, documentOptions: new() { MaxDepth = 64 })!.AsObject();
    }
    internal static Guid Id(JsonNode? value)
    {
        if (value is JsonObject obj) value = obj["rawValue"];
        var id = Guid.Parse(value!.GetValue<string>());
        if (id == Guid.Empty) throw new BrowserRuleException("invalid_identity");
        return id;
    }
    private static Guid RecordId(JsonNode value, string section) => Id(section == "archivedTabs" ? value["tab"]!["id"] : value["id"]);
    private static readonly string[] Sections = ["tabs", "folders", "history", "archivedTabs"];

    private static JsonObject Fields(JsonObject input, IReadOnlyCollection<string> excluded)
        => new(input.Where(f => !excluded.Contains(f.Key)).Select(f => new KeyValuePair<string, JsonNode?>(f.Key, f.Value?.DeepClone())));
    private static void Validate(SessionDocument value)
    {
        var spaces = value.Spaces;
        var ids = new HashSet<Guid>(); var tabs = new HashSet<Guid>();
        foreach (var space in spaces)
        {
            if (!ids.Add(Id(space.Metadata["id"]))) throw new BrowserRuleException("duplicate_space");
            _ = Id(space.Metadata["profile"]!["id"]);
            foreach (var tab in space.Sections["tabs"])
                if (!tabs.Add(Id(tab!["id"]))) throw new BrowserRuleException("duplicate_tab");
        }
        // An empty temporary workspace and a briefly stale window selection are
        // valid native states. Window reconciliation handles their presentation.
    }

    private SessionDocument Prepare(ulong expected, ReadOnlySpan<byte> bytes)
    {
        if (expected != Revision) throw new BrowserRuleException("stale_session_revision");
        var delta = Parse(bytes);
        if (delta["version"]!.GetValue<int>() != 1) throw new BrowserRuleException("version_mismatch");
        var metadata = delta["metadata"] is JsonObject suppliedMetadata ? Fields(suppliedMetadata, ["spaces"]) : document.Metadata;
        var byId = document.Spaces.ToDictionary(s => Id(s.Metadata["id"]));
        foreach (var node in delta["spaces"]!.AsArray())
        {
            var change = node!.AsObject(); var id = Id(change["id"]);
            byId.TryGetValue(id, out var original);
            var fields = change["metadata"] is JsonObject supplied ? Fields(supplied, Sections) : original?.Metadata;
            if (fields is null || Id(fields["id"]) != id) throw new BrowserRuleException("wrong_space_identity");
            var sections = Sections.ToDictionary(section => section,
                section => original?.Sections[section] ?? (IReadOnlyList<JsonNode>)System.Array.Empty<JsonNode>());
            foreach (var section in Sections)
            {
                if (change[section] is not JsonObject edits) continue;
                if (edits["replace"] is JsonArray replacement) { sections[section] = replacement.Select(item => item!.DeepClone()).ToArray(); continue; }
                var previous = sections[section];
                var records = previous.ToDictionary(v => RecordId(v!, section), v => v!);
                foreach (var removed in edits["remove"]!.AsArray()) records.Remove(Id(removed));
                foreach (var item in edits["upsert"]!.AsArray()) records[RecordId(item!, section)] = item!.DeepClone();
                var order = edits["order"] is JsonArray suppliedRecords
                    ? suppliedRecords.Select(Id).ToArray() : previous.Select(v => RecordId(v!, section)).ToArray();
                if (order.Length != records.Count || order.Distinct().Count() != order.Length || order.Any(id => !records.ContainsKey(id)))
                    throw new BrowserRuleException("invalid_record_order");
                sections[section] = order.Select(key => records[key]).ToArray();
            }
            byId[id] = new(fields, sections);
        }
        var spaceOrder = delta["spaceOrder"] is JsonArray suppliedOrder
            ? suppliedOrder.Select(Id).ToArray() : document.Spaces.Select(s => Id(s.Metadata["id"])).ToArray();
        if (spaceOrder.Distinct().Count() != spaceOrder.Length || spaceOrder.Any(id => !byId.ContainsKey(id)))
            throw new BrowserRuleException("invalid_space_order");
        var next = new SessionDocument(metadata, spaceOrder.Select(id => byId[id]).ToArray());
        Validate(next);
        return next;
    }
    public ulong Commit(ulong expected, ReadOnlySpan<byte> delta)
    {
        lock (Gate)
        {
            var next = Prepare(expected, delta);
            var revision = checked(Revision + 1);
            document = next; Revision = revision; return revision;
        }
    }
    public static (ulong Source, ulong Destination) CommitPair(
        NativeSessionAuthority source, ulong sourceRevision, ReadOnlySpan<byte> sourceDelta,
        NativeSessionAuthority destination, ulong destinationRevision, ReadOnlySpan<byte> destinationDelta)
    {
        if (ReferenceEquals(source, destination)) throw new BrowserRuleException("same_session_transfer");
        lock (Gate)
        {
            var a = source.Prepare(sourceRevision, sourceDelta);
            var b = destination.Prepare(destinationRevision, destinationDelta);
            var ar = checked(source.Revision + 1); var br = checked(destination.Revision + 1);
            source.document = a; destination.document = b;
            source.Revision = ar; destination.Revision = br;
            return (ar, br);
        }
    }
    public NativeSessionCheckpoint Checkpoint(ulong expected, ReadOnlySpan<byte> selection)
    {
        lock (Gate)
        {
            if (expected != Revision) throw new BrowserRuleException("stale_session_revision");
            return new(document, Parse(selection));
        }
    }
}

public sealed class NativeSessionCheckpoint
{
    private readonly NativeSessionAuthority.SessionDocument document;
    private readonly JsonObject selection;
    private readonly System.Collections.Concurrent.ConcurrentDictionary<string, byte[]> parts = new();
    internal NativeSessionCheckpoint(NativeSessionAuthority.SessionDocument document, JsonObject selection)
    { this.document = document; this.selection = selection; }

    public byte[] Read(string part) => parts.GetOrAdd(part, Encode);
    private byte[] Encode(string part)
    {
        if (part != "core")
        {
            var id = Guid.Parse(part);
            var history = document.Spaces.Single(s => NativeSessionAuthority.Id(s.Metadata["id"]) == id).Sections["history"];
            using var historyStream = new MemoryStream();
            using (var writer = new Utf8JsonWriter(historyStream))
            { writer.WriteStartArray(); foreach (var entry in history) entry.WriteTo(writer); writer.WriteEndArray(); }
            return historyStream.ToArray();
        }
        using var stream = new MemoryStream();
        using (var writer = new Utf8JsonWriter(stream))
        {
            writer.WriteStartObject();
            foreach (var field in document.Metadata.Where(f => f.Key != "selectedSpaceID"))
            { writer.WritePropertyName(field.Key); if (field.Value is { } value) value.WriteTo(writer); else writer.WriteNullValue(); }
            writer.WritePropertyName("selectedSpaceID"); selection["selectedSpaceID"]!.WriteTo(writer);
            writer.WriteStartArray("spaces");
            var tabs = selection["selectedTabs"]!.AsArray().ToDictionary(v => NativeSessionAuthority.Id(v!["spaceID"]), v => v!["tabID"]);
            foreach (var space in document.Spaces)
            {
                writer.WriteStartObject();
                foreach (var field in space.Metadata.Where(f => f.Key != "selectedTabID"))
                { writer.WritePropertyName(field.Key); if (field.Value is { } value) value.WriteTo(writer); else writer.WriteNullValue(); }
                foreach (var section in space.Sections)
                {
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
}
