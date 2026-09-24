using CrestCore.Contracts;

namespace CrestCore.Domain;

/// Which choices one command touched. A null member covers every value, so a
/// Space reset names only `Space`. `RevokesAuthorization` tells live pages to
/// withdraw what they were already given.
public sealed record SitePermissionChange(Guid? Space, SiteOrigin? Origin, SitePermission? Permission, string? Detail,
    bool RevokesAuthorization);
