namespace CrestCore.Contracts;

/// Removes one of a Space's custom search engines. A Space that searched with
/// it searches with Google.
public sealed record RemoveSearchEngine(Guid WorkspaceId, Guid SpaceId, Guid EngineId) : SessionIntent(WorkspaceId);
