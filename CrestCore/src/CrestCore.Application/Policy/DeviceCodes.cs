using System.Text.Json;

using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

/// Wire spellings shared by policy operations whose rules differ by device.
internal static class DeviceCodes {
    #region Actions - Decoding

    public static DevicePlatform Platform(JsonElement request) =>
        DevicePlatform.Named(Protocol.Text(request, "platform", 16)) ?? throw new ProtocolException(ProtocolErrorCodes.InvalidPlatform);

    /// A non-negative JSON integer.
    public static ulong Unsigned(JsonElement value, string field) {
        var member = value.GetProperty(field);
        if (member.ValueKind != JsonValueKind.Number || !member.TryGetUInt64(out var number))
            throw new ProtocolException(ProtocolErrorCodes.InvalidInput);
        return number;
    }

    public static ulong? OptionalUnsigned(JsonElement value, string field) =>
        value.TryGetProperty(field, out var member) && member.ValueKind != JsonValueKind.Null ? Unsigned(value, field) : null;

    public static int Count(JsonElement value, string field) {
        var member = value.GetProperty(field);
        if (member.ValueKind != JsonValueKind.Number || !member.TryGetInt32(out var count))
            throw new ProtocolException(ProtocolErrorCodes.InvalidInput);
        return count;
    }

    #endregion
}
