namespace CrestCore.Contracts;

/// The engine's page is gone: the core asked the engine to close it, or the
/// page closed itself, as `window.close()` does.
public sealed record PageClosed(Guid PageId) : EngineEvent;
