using CrestCore.Contracts;

namespace CrestCore.Domain;

/// One saved, persistent choice. `Detail` narrows a capability a site can ask
/// for more than one way, such as the URL scheme behind one external-app
/// hand-off; null is the site-wide rule. `ModifiedAt` is seconds in the
/// caller's epoch and is stored exactly as given.
public sealed record SitePermissionRecord(Guid Id, Guid Space, SiteOrigin Origin, SitePermission Permission,
    string? Detail, SitePermissionDecision Decision, double ModifiedAt);
