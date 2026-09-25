using CrestCore.Contracts;

namespace CrestCore.Domain;

/// What one command touched in one Space.
public sealed record SitePermissionChange(Guid Space, SitePermissionScope Scope);
