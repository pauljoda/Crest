namespace CrestCore.Contracts;

/// What a page's engine shows changed. A binding reports a page's latest
/// snapshot at most once per turn, and only when it differs from the last one
/// it reported.
public sealed record PageStateChanged(Guid PageId, PageSnapshot Snapshot) : EngineEvent;
