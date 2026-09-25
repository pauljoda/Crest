namespace CrestCore.Contracts;

/// The core keeps no session file, or its file holds no session yet, so a
/// workspace that keeps the file opens only once `AdoptLegacySession` has given
/// the file its first session, or from a seed. A `CloudSyncIntent` is refused
/// with it too while that session is not open.
public sealed record NoStoredSession : Rejection;
