namespace CrestCore.Contracts;

/// Makes a Space search with a built-in engine or with one of its custom
/// engines; exactly one of `BuiltIn` and `CustomEngineId` names it.
public sealed record SelectSearchEngine(Guid WorkspaceId, Guid SpaceId, BuiltInSearchEngine? BuiltIn, Guid? CustomEngineId)
    : SessionIntent(WorkspaceId);
