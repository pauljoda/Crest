using CrestCore.Application;

namespace CrestCore.Contracts;

#region Models

/// The Space `SpaceId` of the workspace `WorkspaceId`, whose extensions a
/// private workspace runs.
public sealed record ExtensionLender(Guid WorkspaceId, Guid SpaceId);

#endregion

/// Runs, in the private workspace `PrivateWorkspaceId`, the extensions the
/// Space `Lender` names allows in private browsing: each private profile the
/// workspace's pages create afterwards derives from that Space's profile and
/// shares its extensions, but none of its cookies, storage or history.
/// Without a lender, private profiles derive from the engine's own profile and
/// run no extensions. A private profile already made keeps what it derived
/// from until private browsing starts over, and one whose lender is being
/// deleted by then derives from the engine's own.
///
/// Refused with `UnknownWorkspace`, `NotPrivateWorkspace` when
/// `PrivateWorkspaceId` is not private, `PersistentWorkspaceRequired` when the
/// lender's workspace is not the persistent one, `UnknownSpace`,
/// `SpaceBeingDeleted` and `SpaceLocked`.
public sealed record LendPrivateExtensions(Guid PrivateWorkspaceId, ExtensionLender? Lender) : WorkspaceIntent {
    #region Actions - App

    internal override void Apply(CrestApp app) {
        var receiving = app.Device.Workspace(PrivateWorkspaceId);
        if (Lender is { } lender) receiving.LendExtensions(app.Device.Workspace(lender.WorkspaceId), lender.SpaceId);
        else receiving.ForgetExtensionLender();
    }

    #endregion
}
