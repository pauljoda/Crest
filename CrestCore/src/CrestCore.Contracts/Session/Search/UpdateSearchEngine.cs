namespace CrestCore.Contracts;

/// Replaces one of a Space's custom search engines, which keeps its place and
/// may keep its own name.
public sealed record UpdateSearchEngine(Guid WorkspaceId, Guid SpaceId, CustomSearchEngine Engine) : SessionIntent(WorkspaceId);
