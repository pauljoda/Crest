using CrestCore.Contracts;

namespace CrestCore.Application;

/// The Spaces of the person's own session this device hides, which the device
/// store keeps and never syncs. Every other workspace shows all its Spaces.
internal sealed partial class Device {
    #region Variables

    private SpaceVisibility spaceVisibility = SpaceVisibility.ShowingAll;

    internal SpaceVisibility SpaceVisibility {
        get {
            lock (gate) return spaceVisibility;
        }
    }

    #endregion

    #region Actions - Reading

    /// The Space visibility the windows over `workspaceId` follow: the
    /// device's own over the person's own session, and every Space shown over
    /// any other.
    internal SpaceVisibility SpaceVisibilityOf(Guid workspaceId) {
        lock (gate) return Persistent() is (var persistent, _) && persistent == workspaceId ? spaceVisibility : SpaceVisibility.ShowingAll;
    }

    /// The Spaces a window over `workspaceId` may show, in `session`'s order.
    internal IReadOnlyList<SpaceState> ShowableSpaces(Guid workspaceId, SessionState session) =>
        Window.Showable(session, SpaceVisibilityOf(workspaceId));

    /// The Space a window over `workspaceId` may show: one `session` holds
    /// that is not being deleted and that the device shows.
    internal SpaceState? ShowableSpace(Guid workspaceId, SessionState session, Guid spaceId) =>
        ShowableSpaces(workspaceId, session).FirstOrDefault(space => space.Id == spaceId);

    #endregion

    #region Actions - Mutators

    /// Shows or hides a Space of the person's own session on this device, and
    /// moves each window that showed a Space now hidden to the first one
    /// shown. Refused with `UnknownSpace` for a Space that session does not
    /// hold or is deleting, and with `CannotHideLastSpace` when no Space would
    /// stay shown.
    internal void ShowSpaceOnDevice(ChangeFeed changes, Guid spaceId, bool shown) {
        // The session is read before the device lock is taken.
        if (Persistent() is not (var workspaceId, var authority) || Available(authority.Current, spaceId) is null)
            throw new Rejected(new UnknownSpace(spaceId));
        var session = authority.Current;
        lock (gate) {
            var revisedSpaceVisibility = shown ? spaceVisibility.Showing(spaceId) : spaceVisibility.Hiding(spaceId);
            if (revisedSpaceVisibility.Equals(spaceVisibility)) return;
            if (Window.Showable(session, revisedSpaceVisibility).Count == 0) throw new Rejected(new CannotHideLastSpace());
            spaceVisibility = revisedSpaceVisibility;
            storage?.EnqueueDevice(Records());
            changes.Publish(new SpaceVisibilityChanged(revisedSpaceVisibility));
            Publish(Changing(open.Values.Where(window => window.WorkspaceId == workspaceId),
                window => window.Repair(session, revisedSpaceVisibility), session), changes);
        }
    }

    /// Reconciles the Space visibility with the person's own session after
    /// it accepted `next`, answering the change when it forgot any hidden
    /// Space. The caller holds the device lock.
    private SpaceVisibilityChanged? ReconcileSpaceVisibility(Guid workspaceId, SessionState next) {
        if (Persistent() is not (var persistent, _) || persistent != workspaceId) return null;
        var reconciledSpaceVisibility = spaceVisibility.Reconciled(next);
        if (ReferenceEquals(reconciledSpaceVisibility, spaceVisibility)) return null;
        spaceVisibility = reconciledSpaceVisibility;
        storage?.EnqueueDevice(Records());
        return new(reconciledSpaceVisibility);
    }

    #endregion
}
