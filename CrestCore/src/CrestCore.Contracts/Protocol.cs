using System.Globalization;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace CrestCore.Contracts;

public sealed class ProtocolException(string code) : Exception(code);
public sealed record Envelope(Guid SessionId, Guid Id, Guid CorrelationId, Guid? CausationId,
    string Sender, string Recipient, ulong Sequence, string Kind, string Type, JsonElement Payload);
public sealed record Capability(string Status, int Version, string Scope, string[] Limitations, string Evidence);
public sealed record Adapter(string Id, string Role, string Implementation, string Version,
    IReadOnlyDictionary<string, Capability> Capabilities)
{
    public bool Supports(string name) => Capabilities.TryGetValue(name, out var c)
        && c.Status == "supported" && c.Version == 1;
}
public sealed record CoreOptions(Guid SessionId, int QueueByteLimit, int MessageByteLimit,
    bool PersistSession = false, JsonObject? InitialState = null);

public static class Protocol
{
    public const int Version = 1;
    public static readonly IReadOnlyDictionary<string, string> Incoming = new Dictionary<string, string>
    {
        ["core.release_inactive_pages"] = "ui", ["platform.memory_pressure"] = "platform",
        ["engine.page_unloaded"] = "engine", ["engine.unload_canceled"] = "engine",
        ["core.open_records"] = "ui", ["core.query_records"] = "ui", ["core.open_history_entry"] = "ui",
        ["core.delete_history_entry"] = "ui", ["core.clear_history"] = "ui",
        ["core.delete_archived_tab"] = "ui", ["core.clear_archive"] = "ui",
        ["core.set_content_blocking"] = "ui", ["core.retry_content_blocking"] = "ui",
        ["engine.content_blocking_applied"] = "engine", ["engine.content_blocking_failed"] = "engine",
        ["core.create_workspace"] = "ui", ["engine.workspace_released"] = "engine",
        ["core.transfer_tab"] = "ui", ["engine.page_reassigned"] = "engine", ["engine.page_reassignment_failed"] = "engine",
        ["core.delete_space"] = "ui", ["core.retry_space_deletion"] = "ui",
        ["engine.profile_deleted"] = "engine", ["engine.profile_deletion_failed"] = "engine",
        ["services.space_data_deleted"] = "services", ["services.space_data_deletion_failed"] = "services",
        ["core.open_window"] = "ui", ["core.close_window"] = "ui", ["core.new_tab"] = "ui", ["core.open_tab"] = "ui", ["core.open_settings"] = "ui",
        ["core.select_tab"] = "ui", ["core.switch_space"] = "ui", ["core.create_space"] = "ui",
        ["core.rename_space"] = "ui", ["core.close_tab"] = "ui", ["core.navigate"] = "ui",
        ["core.back"] = "ui", ["core.forward"] = "ui", ["core.reload"] = "ui", ["core.stop"] = "ui",
        ["core.unlock_space"] = "ui", ["core.lock_space"] = "ui", ["core.lock_all"] = "ui", ["core.set_space_access"] = "ui",
        ["platform.authentication_completed"] = "platform",
        ["core.snapshot"] = "ui", ["core.create_folder"] = "ui", ["core.place_tab"] = "ui",
        ["core.rename_tab"] = "ui", ["core.set_tab_residency"] = "ui", ["core.retry_save"] = "ui",
        ["core.restore_tab"] = "ui", ["core.set_retention"] = "ui", ["core.maintain_session"] = "ui",
        ["core.bind_window_scene"] = "ui",
        ["core.rename_folder"] = "ui", ["core.collapse_folder"] = "ui", ["core.delete_folder"] = "ui",
        ["core.move_folder"] = "ui", ["core.file_tabs"] = "ui",
        ["core.duplicate_tab"] = "ui", ["core.join_split"] = "ui", ["core.leave_split"] = "ui",
        ["core.navigate_input"] = "ui", ["core.select_search_provider"] = "ui",
        ["core.upsert_search_provider"] = "ui", ["core.remove_search_provider"] = "ui",
        ["engine.page_created"] = "engine", ["engine.page_changed"] = "engine", ["engine.open_requested"] = "engine",
        ["engine.page_closed"] = "engine", ["engine.close_canceled"] = "engine",
        ["engine.failed"] = "engine", ["engine.stopped"] = "engine",
        ["platform.surface_attached"] = "platform", ["platform.failed"] = "platform",
        ["services.session_saved"] = "services", ["services.save_failed"] = "services",
        ["engine.adoption_requested"] = "engine", ["engine.page_destroyed"] = "engine", ["engine.reveal_requested"] = "engine"
    };

    public static JsonElement Parse(ReadOnlySpan<byte> utf8)
    {
        // GetString with a throwing decoder rejects malformed UTF-8 before System.Text.Json replacement behavior.
        _ = new UTF8Encoding(false, true).GetString(utf8);
        using var doc = JsonDocument.Parse(utf8.ToArray(), new() { MaxDepth = 24 });
        ValidateMembers(doc.RootElement);
        return doc.RootElement.Clone();
    }
    private static void ValidateMembers(JsonElement e)
    {
        if (e.ValueKind == JsonValueKind.Object)
        {
            var seen = new HashSet<string>(StringComparer.Ordinal);
            foreach (var p in e.EnumerateObject())
            {
                if (!seen.Add(p.Name)) throw new ProtocolException("duplicate_member");
                ValidateMembers(p.Value);
            }
        }
        else if (e.ValueKind == JsonValueKind.Array) foreach (var item in e.EnumerateArray()) ValidateMembers(item);
        else if (e.ValueKind == JsonValueKind.String)
        {
            // GetString also validates escaped surrogate pairs.
            _ = new UTF8Encoding(false, true).GetBytes(e.GetString()!);
        }
    }
    public static void Members(JsonElement e, params string[] names)
    {
        if (e.ValueKind != JsonValueKind.Object || e.EnumerateObject().Any(p => !names.Contains(p.Name)))
            throw new ProtocolException("unexpected_member");
    }
    public static string Text(JsonElement e, string key, int max = 16384)
    {
        var p = e.GetProperty(key);
        if (p.ValueKind != JsonValueKind.String || p.GetString() is not { } s || s.Length == 0 || s.Length > max)
            throw new ProtocolException("invalid_string");
        return s;
    }
    public static string? OptionalText(JsonElement e, string key, int max = 16384)
        => !e.TryGetProperty(key, out var p) || p.ValueKind == JsonValueKind.Null ? null : Text(e, key, max);
    public static Guid Id(JsonElement e, string key)
    {
        _ = Text(e, key, 36);
        return Id(e.GetProperty(key));
    }
    public static Guid Id(JsonElement value)
    {
        if (value.ValueKind != JsonValueKind.String) throw new ProtocolException("invalid_uuid");
        string s = value.GetString()!;
        if (!Guid.TryParseExact(s, "D", out var id) || s != id.ToString("D") || id == Guid.Empty)
            throw new ProtocolException("invalid_uuid");
        return id;
    }
    public static Guid? OptionalId(JsonElement e, string key)
        => !e.TryGetProperty(key, out var p) || p.ValueKind == JsonValueKind.Null ? null : Id(e, key);
    public static ulong Counter(JsonElement e, string key)
    {
        string s = Text(e, key, 20);
        if (!ulong.TryParse(s, NumberStyles.None, CultureInfo.InvariantCulture, out var value)
            || value == 0 || s != value.ToString(CultureInfo.InvariantCulture)) throw new ProtocolException("invalid_counter");
        return value;
    }
    public static string Endpoint(JsonElement e, string key)
    {
        string s = Text(e, key, 96);
        if (s[0] is < 'a' or > 'z' || s.Any(c => !(char.IsAsciiLetterLower(c) || char.IsAsciiDigit(c) || c is '.' or '-' or '_')))
            throw new ProtocolException("invalid_endpoint");
        return s;
    }
    public static Envelope Decode(ReadOnlySpan<byte> bytes)
    {
        var e = Parse(bytes);
        Members(e, "protocolVersion", "sessionId", "id", "correlationId", "causationId", "sender", "recipient", "sequence", "kind", "type", "payload");
        if (e.GetProperty("protocolVersion").GetInt32() != Version) throw new ProtocolException("version_mismatch");
        var payload = e.GetProperty("payload");
        if (payload.ValueKind != JsonValueKind.Object) throw new ProtocolException("invalid_payload");
        return new(Id(e, "sessionId"), Id(e, "id"), Id(e, "correlationId"), OptionalId(e, "causationId"),
            Endpoint(e, "sender"), Endpoint(e, "recipient"), Counter(e, "sequence"), Text(e, "kind", 32), Text(e, "type", 96), payload);
    }
    public static CoreOptions Options(ReadOnlySpan<byte> bytes)
    {
        var e = Parse(bytes);
        Members(e, "sessionId", "protocolVersion", "isolationMode", "queueByteLimit", "messageByteLimit", "persistSession", "initialState");
        if (e.GetProperty("protocolVersion").GetInt32() != Version) throw new ProtocolException("version_mismatch");
        if (Text(e, "isolationMode") is not ("ephemeral" or "isolated")) throw new ProtocolException("isolation_required");
        int queue = e.GetProperty("queueByteLimit").GetInt32(), message = e.GetProperty("messageByteLimit").GetInt32();
        if (message is < 4096 or > 1048576 || queue < message * 2 || queue > 8388608)
            throw new ProtocolException("invalid_limits");
        bool persist = e.TryGetProperty("persistSession", out var p) && p.GetBoolean();
        JsonObject? initial = e.TryGetProperty("initialState", out var state) && state.ValueKind != JsonValueKind.Null
            ? JsonNode.Parse(state.GetRawText()) as JsonObject ?? throw new ProtocolException("invalid_saved_state") : null;
        return new(Id(e, "sessionId"), queue, message, persist, initial);
    }
    public static Adapter Descriptor(ReadOnlySpan<byte> bytes)
    {
        var e = Parse(bytes);
        Members(e, "adapterId", "role", "implementationId", "implementationVersion", "protocolVersion", "capabilities");
        if (e.GetProperty("protocolVersion").GetInt32() != Version) throw new ProtocolException("version_mismatch");
        string id = Endpoint(e, "adapterId"), role = Text(e, "role");
        if (id == "core" || role is not ("ui" or "engine" or "platform" or "services")) throw new ProtocolException("invalid_adapter");
        var capabilities = new Dictionary<string, Capability>();
        foreach (var p in e.GetProperty("capabilities").EnumerateObject())
        {
            if (capabilities.Count >= 128 || p.Name.Length > 128) throw new ProtocolException("capability_limit");
            var c = p.Value;
            Members(c, "status", "contractVersion", "scope", "limitations", "evidence");
            string status = Text(c, "status");
            if (status is not ("supported" or "partial" or "unavailable" or "unverified")) throw new ProtocolException("invalid_status");
            int version = c.GetProperty("contractVersion").GetInt32();
            if (version < 1) throw new ProtocolException("invalid_version");
            var limits = c.GetProperty("limitations").EnumerateArray().Select(l => l.GetString() ?? throw new ProtocolException("invalid_limit")).ToArray();
            if (limits.Length > 32 || limits.Any(l => l.Length > 512)) throw new ProtocolException("invalid_limit");
            capabilities.Add(p.Name, new(status, version, Text(c, "scope", 256), limits, Text(c, "evidence", 512)));
        }
        return new(id, role, Text(e, "implementationId", 128), Text(e, "implementationVersion", 128), capabilities);
    }
    public static byte[] Encode(Guid session, Guid id, Guid correlation, Guid? causation, string recipient,
        ulong sequence, string kind, string type, JsonObject payload)
    {
        var e = new JsonObject
        {
            ["protocolVersion"] = Version, ["sessionId"] = session.ToString(), ["id"] = id.ToString(),
            ["correlationId"] = correlation.ToString(), ["causationId"] = causation?.ToString(),
            ["sender"] = "core", ["recipient"] = recipient, ["sequence"] = sequence.ToString(CultureInfo.InvariantCulture),
            ["kind"] = kind, ["type"] = type, ["payload"] = payload
        };
        return Encoding.UTF8.GetBytes(e.ToJsonString());
    }
}
