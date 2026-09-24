namespace CrestCore.Contracts;

/// <summary>Which revision of the persistent session the core has accepted and not yet
/// saved, so a caller can wait until it is on disk.</summary>
public sealed record PendingSave : Query<PendingSaveRevision>;
