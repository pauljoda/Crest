using CrestCore.Contracts;

namespace CrestCore.Application;

public sealed partial class NativeSessionAuthority {
    #region Variables

    /// The workspace and Space whose extensions this private workspace runs,
    /// or null for none.
    private (NativeSessionAuthority Owner, Guid SpaceId)? extensionLender;

    /// The regular profile a private page this workspace opens derives from,
    /// which runs the extensions it allows in private browsing: the lending
    /// Space's, while its workspace still holds it and is not deleting it.
    /// Null for none, and always for a workspace that is not private.
    internal Guid? ExtensionProfileId {
        get {
            (NativeSessionAuthority Owner, Guid SpaceId)? lender;
            lock (Gate) lender = extensionLender;
            if (lender is not var (owner, spaceId) || owner.IsDeleting(spaceId)) return null;
            return owner.Current.Spaces.FirstOrDefault(space => space.Id == spaceId)?.ProfileId;
        }
    }

    #endregion

    #region Actions - Private extensions

    /// Runs, in this private workspace's pages from now on, the extensions the
    /// Space `spaceId` of `owner` allows in private browsing. Refused with
    /// `NotPrivateWorkspace` here, and for the Space with
    /// `PersistentWorkspaceRequired`, `UnknownSpace`, `SpaceBeingDeleted` and
    /// `SpaceLocked`.
    internal void LendExtensions(NativeSessionAuthority owner, Guid spaceId) {
        if (!Kind.IsPrivate) throw new Rejected(new NotPrivateWorkspace(WorkspaceId));
        if (owner.Kind != WorkspaceKind.Persistent) throw new Rejected(new PersistentWorkspaceRequired(owner.WorkspaceId));
        var space = owner.Current.Spaces.FirstOrDefault(candidate => candidate.Id == spaceId)
            ?? throw new Rejected(new UnknownSpace(spaceId));
        if (owner.IsDeleting(spaceId)) throw new Rejected(new SpaceBeingDeleted(spaceId));
        if (owner.IsLocked(space)) throw new Rejected(new SpaceLocked(spaceId));
        lock (Gate) extensionLender = (owner, spaceId);
    }

    /// This private workspace's pages run no extensions from now on. Refused
    /// with `NotPrivateWorkspace` here.
    internal void ForgetExtensionLender() {
        if (!Kind.IsPrivate) throw new Rejected(new NotPrivateWorkspace(WorkspaceId));
        lock (Gate) extensionLender = null;
    }

    #endregion
}
