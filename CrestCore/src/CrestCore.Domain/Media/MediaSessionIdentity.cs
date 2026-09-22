namespace CrestCore.Domain;

/// What the store remembers about the reporting document: whether it was
/// retired, the last sequence it accepted, the ordinal it was given, whether the
/// person hid its card, and the playback state it last published.
public sealed record MediaSessionIdentity(bool IsRetired, ulong? LastSequence, ulong? Ordinal, bool IsDismissed,
    MediaPlaybackState? PreviousPlayback);
