using System.Text.Json;

using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

/// Wire spellings for the media-session policy operations. Playback states use
/// the native bridge's raw values.
internal static class MediaSessionCodes {
    #region Variables

    public const int MaximumIdLength = 256;

    #endregion

    #region Actions - Decoding

    public static MediaPlaybackState Playback(string? value) => value switch {
        "none" => MediaPlaybackState.None,
        "paused" => MediaPlaybackState.Paused,
        "playing" => MediaPlaybackState.Playing,
        _ => throw new ProtocolException(ProtocolErrorCodes.InvalidPlaybackState)
    };

    public static MediaSessionEvent Event(JsonElement value) {
        Protocol.Members(value, "sequence", "invalidated", "active", "playbackState");
        return new(DeviceCodes.Unsigned(value, "sequence"), value.GetProperty("invalidated").GetBoolean(),
            value.GetProperty("active").GetBoolean(), Playback(value.GetProperty("playbackState").GetString()));
    }

    public static MediaSessionIdentity Identity(JsonElement value) {
        Protocol.Members(value, "retired", "lastSequence", "ordinal", "dismissed", "previousPlaybackState");
        var previous = value.TryGetProperty("previousPlaybackState", out var state) && state.ValueKind != JsonValueKind.Null
            ? Playback(state.GetString()) : (MediaPlaybackState?)null;
        return new(value.GetProperty("retired").GetBoolean(), DeviceCodes.OptionalUnsigned(value, "lastSequence"),
            DeviceCodes.OptionalUnsigned(value, "ordinal"), value.GetProperty("dismissed").GetBoolean(), previous);
    }

    public static IReadOnlyList<MediaSessionEntry> Sessions(JsonElement request) {
        var value = request.GetProperty("sessions");
        if (value.ValueKind != JsonValueKind.Array || value.GetArrayLength() > MediaSessionPolicy.MaximumSessions)
            throw new BrowserRuleException(BrowserRuleCodes.MediaSessionLimit);
        return value.EnumerateArray().Select(entry => {
            Protocol.Members(entry, "id", "ordinal", "playbackState", "audible");
            return new MediaSessionEntry(Protocol.Text(entry, "id", MaximumIdLength), DeviceCodes.Unsigned(entry, "ordinal"),
                Playback(entry.GetProperty("playbackState").GetString()), entry.GetProperty("audible").GetBoolean());
        }).ToArray();
    }

    #endregion

    #region Actions - Encoding

    public static string Disposition(MediaSessionDisposition disposition) => disposition switch {
        MediaSessionDisposition.Retire => "retire",
        MediaSessionDisposition.Publish => "publish",
        _ => "clear"
    };

    #endregion
}
