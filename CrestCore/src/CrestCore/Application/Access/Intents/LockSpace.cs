using CrestCore.Application;
using CrestCore.Domain;

namespace CrestCore.Contracts;

/// Locks a Space again, and every Space of its group: every grant for them is
/// revoked, and a request waiting to unlock one is cancelled.
public sealed record LockSpace(Guid SpaceId) : SpaceAccessIntent {
    #region Actions - Access

    internal override void Apply(SpaceAccess access, ChangeFeed changes) {
        var group = access.Device.GroupMembersOf(SpaceId);
        access.Changing(changes, authority => authority.Lock(group));
    }

    #endregion
}
