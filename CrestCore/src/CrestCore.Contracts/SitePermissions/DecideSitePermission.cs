namespace CrestCore.Contracts;

/// Records the person's answer for `Permission` at `Origin` in a Space.
/// `Detail` narrows a capability a site can ask for more than one way, such as
/// the URL scheme behind one external-app hand-off; null is the site-wide rule.
/// Ask clears both the session and the saved choice; a session answer
/// overrides the saved choice until the process ends without replacing it; a
/// persistent answer replaces both and keeps an existing record's identity.
public sealed record DecideSitePermission(Guid SpaceId, SiteOrigin Origin, SitePermission Permission, string? Detail,
    SitePermissionDecision Decision) : SitePermissionIntent;
