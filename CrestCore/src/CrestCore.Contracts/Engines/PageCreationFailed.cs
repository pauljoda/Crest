namespace CrestCore.Contracts;

/// The engine could not create the page.
public sealed record PageCreationFailed(Guid PageId) : EngineEvent;
