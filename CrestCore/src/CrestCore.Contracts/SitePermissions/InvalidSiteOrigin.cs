namespace CrestCore.Contracts;

/// A site permission's origin has an empty or overlong scheme or host, or a
/// port that is not one.
public sealed record InvalidSiteOrigin(SiteOrigin Origin) : Rejection;
