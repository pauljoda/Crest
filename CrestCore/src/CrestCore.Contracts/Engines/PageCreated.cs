namespace CrestCore.Contracts;

/// The engine created the page, which is now live.
public sealed record PageCreated(Guid PageId) : EngineEvent;
