namespace CrestCore.Contracts;

/// What a site permission decision says about a request: let it through, stop
/// it, or ask the person.
public enum SitePermissionVerdict { Ask, Grant, Deny }
