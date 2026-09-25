namespace CrestCore.Contracts;

/// A Space's site permission choices changed. `Records` are the choices it
/// keeps now, in the order the settings list them; `Touched` names what the
/// change covered, so a page can withdraw what it was already given.
public sealed record SitePermissionsChanged(Guid SpaceId, IReadOnlyList<SitePermissionRecordState> Records,
    IReadOnlyList<SitePermissionScope> Touched) : Change;
