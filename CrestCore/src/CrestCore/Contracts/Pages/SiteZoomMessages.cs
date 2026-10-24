namespace CrestCore.Contracts;

/// The normalized HTTP(S) hostname and its saved zoom, or null when it follows
/// the global default. Schemes and ports share a hostname's preference.
public sealed record SiteZoomPreference(string? Host, double? Factor);

/// A profile's hostname now follows a different zoom preference. Live pages
/// showing that host resolve the new value against their global default.
public sealed record SiteZoomChanged(Guid ProfileId, string Host) : Change;

/// A saved page zoom must be finite and between 25% and 500%.
public sealed record InvalidSiteZoom(double Factor) : Rejection;

/// Only HTTP(S) hosts keep a zoom preference.
public sealed record InvalidSiteZoomAddress(string Url) : Rejection;
