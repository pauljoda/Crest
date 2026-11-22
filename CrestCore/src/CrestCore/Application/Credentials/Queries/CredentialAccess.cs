using CrestCore.Application;
using CrestCore.Domain;

namespace CrestCore.Contracts;

/// Whether the passwords of the Space `SpaceId` serve `Use`, for a page of
/// `Origin` when it names one, and the Spaces whose vaults hold them: the
/// group's primary, which keeps its new passwords, then its Sub-Spaces, or the
/// Space alone. A private window refuses a save, an off password manager a
/// fill or a save, and a page without HTTPS either, in that order. Refused
/// with `UnknownSpace` for a Space that is not there.
public sealed record CredentialAccess(Guid WorkspaceId, Guid SpaceId, CredentialUse Use, CredentialOrigin? Origin = null)
    : Query<CredentialAccessAnswer> {
    #region Actions - Answering

    internal override CredentialAccessAnswer Answer(CrestApp app) {
        var authority = app.Device.Workspace(WorkspaceId);
        var session = authority.Current;
        var space = session.KnownSpace(SpaceId);
        IReadOnlyList<Guid> vaults = session.GroupOf(space.Id) is { } group ? [.. group.Members.Select(member => member.Id)] : [space.Id];
        return new(Refusal(space, authority.IsPrivateBrowsing), vaults);
    }

    /// Why `space` refuses the use, or null when it allows it.
    private CredentialRefusal? Refusal(SpaceState space, bool isPrivate) {
        if (Use.RefusedInPrivate && isPrivate) return CredentialRefusal.PrivateBrowsing;
        if (!Use.NeedsManager) return null;
        if (!space.Settings.CredentialPreferences.IsEnabled) return CredentialRefusal.ManagerOff;
        return Origin is { IsSecure: false } ? CredentialRefusal.InsecureOrigin : null;
    }

    #endregion
}
