namespace CrestCore.Contracts;

/// Whether a tab's page stays loaded when memory runs low. Unloading it on
/// purpose still does, so this is a preference, not a promise.
public sealed record KeepPageLoaded(Guid WorkspaceId, Guid SpaceId, Guid TabId, bool Keeps) : SessionIntent(WorkspaceId);
