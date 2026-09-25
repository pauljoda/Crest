namespace CrestCore.Contracts;

/// Which choices in a Space one change covered. A null member covers every
/// value, so a Space reset names none. `RevokesAuthorization` tells live pages
/// to withdraw what they were already given.
public sealed record SitePermissionScope(SiteOrigin? Origin, SitePermission? Permission, string? Detail,
    bool RevokesAuthorization);
