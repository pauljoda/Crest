namespace CrestCore.Contracts;

/// Adds a custom search engine to a Space, trimmed and validated, after the
/// others, and searches with it when `Selects`.
public sealed record AddSearchEngine(Guid WorkspaceId, Guid SpaceId, CustomSearchEngine Engine, bool Selects)
    : SessionIntent(WorkspaceId);
