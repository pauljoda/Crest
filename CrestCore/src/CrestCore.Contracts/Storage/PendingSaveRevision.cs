namespace CrestCore.Contracts;

/// <summary>The newest accepted revision not yet on disk, which a later <c>Saved</c>
/// names; null when everything accepted is saved or the core keeps nothing.</summary>
public sealed record PendingSaveRevision(long? Revision);
