namespace CrestCore.Domain;

/// One published session as ordering and Now Playing ownership see it.
public sealed record MediaSessionEntry(string Id, ulong Ordinal, MediaPlaybackState Playback, bool IsAudible);
