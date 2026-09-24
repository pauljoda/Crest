using System.Globalization;
using System.Text;
using System.Text.Json;

namespace CrestCore.Contracts;

public static class Protocol {
    #region Variables

    public const int Version = 1;

    #endregion

    #region Actions - Parsing

    public static JsonElement Parse(ReadOnlySpan<byte> utf8) {
        // GetString with a throwing decoder rejects malformed UTF-8 before System.Text.Json replacement behavior.
        _ = new UTF8Encoding(false, true).GetString(utf8);
        using var doc = JsonDocument.Parse(utf8.ToArray(), new() { MaxDepth = 24 });
        ValidateMembers(doc.RootElement);
        return doc.RootElement.Clone();
    }

    private static void ValidateMembers(JsonElement e) {
        if (e.ValueKind == JsonValueKind.Object) {
            var seen = new HashSet<string>(StringComparer.Ordinal);
            foreach (var p in e.EnumerateObject()) {
                if (!seen.Add(p.Name)) throw new ProtocolException(ProtocolErrorCodes.DuplicateMember);
                ValidateMembers(p.Value);
            }
        } else if (e.ValueKind == JsonValueKind.Array) foreach (var item in e.EnumerateArray()) ValidateMembers(item);
        else if (e.ValueKind == JsonValueKind.String) {
            // GetString also validates escaped surrogate pairs.
            _ = new UTF8Encoding(false, true).GetBytes(e.GetString()!);
        }
    }

    public static void Members(JsonElement e, params string[] names) {
        if (e.ValueKind != JsonValueKind.Object || e.EnumerateObject().Any(p => !names.Contains(p.Name)))
            throw new ProtocolException(ProtocolErrorCodes.UnexpectedMember);
    }

    public static string Text(JsonElement e, string key, int max = 16384) {
        var p = e.GetProperty(key);
        if (p.ValueKind != JsonValueKind.String || p.GetString() is not { } s || s.Length == 0 || s.Length > max)
            throw new ProtocolException(ProtocolErrorCodes.InvalidString);
        return s;
    }

    public static string? OptionalText(JsonElement e, string key, int max = 16384)
        => !e.TryGetProperty(key, out var p) || p.ValueKind == JsonValueKind.Null ? null : Text(e, key, max);

    public static Guid Id(JsonElement e, string key) {
        _ = Text(e, key, 36);
        return Id(e.GetProperty(key));
    }

    public static Guid Id(JsonElement value) {
        if (value.ValueKind != JsonValueKind.String) throw new ProtocolException(ProtocolErrorCodes.InvalidUuid);
        string s = value.GetString()!;
        if (!Guid.TryParseExact(s, "D", out var id) || s != id.ToString("D") || id == Guid.Empty)
            throw new ProtocolException(ProtocolErrorCodes.InvalidUuid);
        return id;
    }

    public static Guid? OptionalId(JsonElement e, string key)
        => !e.TryGetProperty(key, out var p) || p.ValueKind == JsonValueKind.Null ? null : Id(e, key);

    public static ulong Counter(JsonElement e, string key) {
        string s = Text(e, key, 20);
        if (!ulong.TryParse(s, NumberStyles.None, CultureInfo.InvariantCulture, out var value)
            || value == 0 || s != value.ToString(CultureInfo.InvariantCulture)) throw new ProtocolException(ProtocolErrorCodes.InvalidCounter);
        return value;
    }

    public static string Endpoint(JsonElement e, string key) {
        string s = Text(e, key, 96);
        if (s[0] is < 'a' or > 'z' || s.Any(c => !(char.IsAsciiLetterLower(c) || char.IsAsciiDigit(c) || c is '.' or '-' or '_')))
            throw new ProtocolException(ProtocolErrorCodes.InvalidEndpoint);
        return s;
    }

    #endregion

    #region Actions - Descriptors

    public static Adapter Descriptor(ReadOnlySpan<byte> bytes) {
        var e = Parse(bytes);
        Members(e, "adapterId", "role", "implementationId", "implementationVersion", "protocolVersion", "capabilities");
        if (e.GetProperty("protocolVersion").GetInt32() != Version) throw new ProtocolException(ProtocolErrorCodes.VersionMismatch);
        string id = Endpoint(e, "adapterId");
        var role = AdapterRole.Named(Text(e, "role"));
        if (id == "core" || role is null) throw new ProtocolException(ProtocolErrorCodes.InvalidAdapter);
        var capabilities = new Dictionary<string, Capability>();
        foreach (var p in e.GetProperty("capabilities").EnumerateObject()) {
            if (capabilities.Count >= 128 || p.Name.Length > 128) throw new ProtocolException(ProtocolErrorCodes.CapabilityLimit);
            var c = p.Value;
            Members(c, "status", "contractVersion", "scope", "limitations", "evidence");
            var status = CapabilityStatus.Named(Text(c, "status")) ?? throw new ProtocolException(ProtocolErrorCodes.InvalidStatus);
            int version = c.GetProperty("contractVersion").GetInt32();
            if (version < 1) throw new ProtocolException(ProtocolErrorCodes.InvalidVersion);
            var limits = c.GetProperty("limitations").EnumerateArray().Select(l => l.GetString() ?? throw new ProtocolException(ProtocolErrorCodes.InvalidLimit)).ToArray();
            if (limits.Length > 32 || limits.Any(l => l.Length > 512)) throw new ProtocolException(ProtocolErrorCodes.InvalidLimit);
            capabilities.Add(p.Name, new(status, version, Text(c, "scope", 256), limits, Text(c, "evidence", 512)));
        }
        return new(id, role, Text(e, "implementationId", 128), Text(e, "implementationVersion", 128), capabilities);
    }

    #endregion
}
