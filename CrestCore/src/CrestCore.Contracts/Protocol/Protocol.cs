using System.Globalization;
using System.Text;
using System.Text.Json;

namespace CrestCore.Contracts;

public static class Protocol {
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

    #endregion
}
