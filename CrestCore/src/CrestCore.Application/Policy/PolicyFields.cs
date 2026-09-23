using System.Text.Json;

using CrestCore.Contracts;

namespace CrestCore.Application;

/// Field readers the policy request models decode with. Each one keeps the
/// failure a direct `JsonElement` read has: a missing member or a value of the
/// wrong JSON kind is rejected, and an optional member may be absent or null.
internal static class PolicyFields {
    #region Variables

    public const string Version = "version";
    public const string Operation = "operation";

    #endregion

    #region Actions - Validation

    /// Rejects any member outside `version`, `operation` and the named fields.
    public static void Members(JsonElement request, params string[] fields) =>
        Protocol.Members(request, [Version, Operation, .. fields]);

    #endregion

    #region Actions - Decoding

    public static JsonElement Element(JsonElement value, string field) => value.GetProperty(field);

    public static JsonElement? Optional(JsonElement value, string field) =>
        value.TryGetProperty(field, out var member) && member.ValueKind != JsonValueKind.Null ? member : null;

    public static bool Flag(JsonElement value, string field) => value.GetProperty(field).GetBoolean();

    public static bool? OptionalFlag(JsonElement value, string field) => Optional(value, field)?.GetBoolean();

    public static int Integer(JsonElement value, string field) => value.GetProperty(field).GetInt32();

    public static int? OptionalInteger(JsonElement value, string field) =>
        Optional(value, field) is { } member ? member.GetInt32() : null;

    public static long Long(JsonElement value, string field) => value.GetProperty(field).GetInt64();

    public static long? OptionalLong(JsonElement value, string field) => Optional(value, field)?.GetInt64();

    public static double Number(JsonElement value, string field) => value.GetProperty(field).GetDouble();

    public static double? OptionalNumber(JsonElement value, string field) =>
        Optional(value, field) is { } member ? member.GetDouble() : null;

    /// A string that may be empty, such as a filename an engine could not name.
    public static string AnyText(JsonElement value, string field, int maximumLength) {
        var member = value.GetProperty(field);
        if (member.ValueKind != JsonValueKind.String || member.GetString() is not { } text || text.Length > maximumLength)
            throw new ProtocolException(ProtocolErrorCodes.InvalidString);
        return text;
    }

    #endregion
}
