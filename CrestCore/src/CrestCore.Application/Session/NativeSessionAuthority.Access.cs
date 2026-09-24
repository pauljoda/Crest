using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

public sealed partial class NativeSessionAuthority {
    #region Variables

    private SpaceAccessAuthority? access;

    /// Sync materialization consults the same grants the command gate uses, so
    /// an incoming record cannot remove protection this device never unlocked.
    internal SpaceAccessAuthority? Access { get { lock (Gate) return access; } }

    #endregion

    #region Actions - Access

    /// Locking is process-local, so the grants and the session records that name
    /// the policy have to meet in the same process: the device attaches its
    /// grants to every session it shows. A borrowed workspace inherits its
    /// source's authority; nothing else can substitute one.
    internal void AttachAccess(SpaceAccessAuthority authority) {
        ArgumentNullException.ThrowIfNull(authority);
        lock (Gate) {
            if (access is not null && !ReferenceEquals(access, authority))
                throw new BrowserRuleException(BrowserRuleCodes.AccessAlreadyAttached);
            access = authority;
        }
    }

    /// The Space profile a request to unlock `spaceId` names, and whether its
    /// policy asks for authentication. Throws `Rejected` with `UnknownSpace`
    /// for a Space the session does not hold, and `SpaceBeingDeleted` for one
    /// that is going away.
    internal (SpaceAccessAssignment Assignment, bool RequiresAuthentication) Unlockable(Guid spaceId) {
        lock (Gate) {
            var space = session.Spaces.FirstOrDefault(candidate => candidate.Id == spaceId) ?? throw new Rejected(new UnknownSpace(spaceId));
            if (PendingDeletion(session, spaceId) is not null || borrowedSource?.IsDeleting(spaceId) == true)
                throw new Rejected(new SpaceBeingDeleted(spaceId));
            return (new(space.Id, space.ProfileId), RequiresAuthentication(space));
        }
    }

    /// A policy this build cannot name reads as guarded (see `StoredSessionCodec`),
    /// so only an open Space skips authentication.
    private static bool RequiresAuthentication(SpaceState space) => space.Settings.AccessPolicy != SpaceAccessPolicy.Open;

    /// The command gate answers for semantic commands. A native value edit
    /// proposes whole records instead, so it is gated on what it actually
    /// touches: every Space whose metadata, tabs, folders, history, archive,
    /// splits or selection this delta would change, plus one it would remove.
    /// Sync materialization does not come through here — it commits as a
    /// journal-bound replacement — so background convergence stays unaffected.
    private void RequireAccessibleValueEdit(SessionState next, IEnumerable<Guid> proposed) {
        if (access is null) return;
        var retained = next.Spaces.Select(s => s.Id).ToHashSet();
        var candidates = new HashSet<Guid>(proposed);
        // Dropping a Space's records is a change even when the delta never
        // named it, so removal is derived rather than declared.
        foreach (var space in session.Spaces)
            if (!retained.Contains(space.Id)) candidates.Add(space.Id);
        foreach (var id in candidates) {
            if (session.Spaces.FirstOrDefault(s => s.Id == id) is not { } original) continue;
            var updated = next.Spaces.FirstOrDefault(s => s.Id == id);
            if (updated is not null && (original == updated || OnlyRaisesProtection(original, updated))) continue;
            RequireAccessible(id);
        }
    }

    /// Raising protection is always allowed, exactly as it is for the command
    /// gate. Nothing else may ride along with it.
    private static bool OnlyRaisesProtection(SpaceState original, SpaceState updated) =>
        updated.Settings.AccessPolicy != SpaceAccessPolicy.Open
        && original with { Settings = original.Settings with { AccessPolicy = updated.Settings.AccessPolicy } } == updated;

    private void RequireAccessible(Guid spaceId) {
        if (access is null) return;
        // An unknown identity is rejected by the command itself, with the error
        // that names the real problem.
        if (session.Spaces.FirstOrDefault(s => s.Id == spaceId) is not { } space) return;
        var assignment = new SpaceAccessAssignment(spaceId, space.ProfileId);
        lock (access) access.RequireAccessible(assignment, RequiresAuthentication(space));
    }

    #endregion
}
