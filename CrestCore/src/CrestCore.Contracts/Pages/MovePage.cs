namespace CrestCore.Contracts;

/// Gives a page a new owner without recreating it: a tab in another
/// workspace or window, or a tab that adopts a transient request's page. The
/// engine page stays in its profile, so the destination Space must keep the
/// same one. Refused like `OpenPage`, and when the destination keeps another
/// profile.
public sealed record MovePage(Guid PageId, Guid WorkspaceId, Guid SpaceId, Guid? TabId, Guid WindowId) : PageIntent;
