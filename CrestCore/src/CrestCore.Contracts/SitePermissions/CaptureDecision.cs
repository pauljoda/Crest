namespace CrestCore.Contracts;

/// The choice that answers a request to capture `Media` at `Origin` in a
/// Space. Combined capture respects a block on any of its devices, and a
/// combined grant still answers a request for one of them; a capability that
/// stands alone answers as `SiteDecision` does. A locked Space, and an origin
/// the rules cannot read, answer Ask.
public sealed record CaptureDecision(Guid SpaceId, SiteOrigin Origin, SitePermission Media) : Query<SitePermissionAnswer>;
