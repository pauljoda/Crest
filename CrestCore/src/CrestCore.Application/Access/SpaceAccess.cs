using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

/// The access area: which Spaces this process may show. It keeps the one
/// grant authority the device attaches to every session it shows, so a
/// borrowed workspace and the one it borrows from unlock and lock together.
/// Each intent publishes the access of every Space profile it changed.
internal sealed class SpaceAccess(Device device, SpaceAccessAuthority authority) {
    #region Actions - Intents

    public void Handle(SpaceAccessIntent intent, ChangeFeed changes) {
        ArgumentNullException.ThrowIfNull(intent);
        ArgumentNullException.ThrowIfNull(changes);
        // The Space is read before the grants are locked, so the session's gate
        // is never taken inside the authority's.
        var unlocking = intent is BeginUnlockingSpace asked ? device.Workspace(asked.WorkspaceId).Unlockable(asked.SpaceId) : default;
        lock (authority) {
            var changed = intent switch {
                BeginUnlockingSpace begin => authority.Begin(unlocking.Assignment, unlocking.RequiresAuthentication, begin.RequestId),
                FinishUnlockingSpace finish => authority.Finish(finish.SpaceId, finish.RequestId, finish.Authenticated),
                LockSpace locking => authority.Lock(locking.SpaceId),
                LockAllSpaces locking => authority.LockAll(locking.SceneWentInactive),
                _ => throw new ArgumentOutOfRangeException(nameof(intent), intent.GetType().Name, "Space access does not handle this intent.")
            };
            foreach (var assignment in changed)
                changes.Publish(new SpaceLockChanged(assignment.Space, assignment.Profile, authority.IsUnlocked(assignment),
                    authority.IsAuthenticating(assignment)));
        }
    }

    #endregion
}
