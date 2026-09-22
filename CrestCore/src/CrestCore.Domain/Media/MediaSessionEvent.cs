namespace CrestCore.Domain;

/// The ordering and lifecycle facts of one page media-session report. Engines
/// sequence reports per document; metadata and artwork stay native.
public sealed record MediaSessionEvent(ulong Sequence, bool IsInvalidated, bool HasActiveSession, MediaPlaybackState Playback);
