using CrestCore.Contracts;

namespace CrestCore.Domain;

/// Process-local grants for exact Space and profile identities. The platform
/// owns the authentication prompt; only the result of the request still
/// pending can grant access, and it grants every Space it was made for, as
/// one unlock opens every Space of a group. Callers serialize access. Nothing
/// in this authority is saved or synced.
public sealed class SpaceAccessAuthority {
    #region Variables

    private readonly HashSet<SpaceAccessAssignment> unlocked = [];
    private (Guid Request, IReadOnlyList<SpaceAccessAssignment> Assignments)? pending;

    #endregion

    #region Actions - Space access

    public bool IsLocked(SpaceAccessAssignment assignment, bool requiresAuthentication) =>
        requiresAuthentication && !unlocked.Contains(assignment);

    /// Whether this process holds the grant for `assignment`.
    public bool IsUnlocked(SpaceAccessAssignment assignment) => unlocked.Contains(assignment);

    /// Whether a request to unlock `assignment` is waiting.
    public bool IsAuthenticating(SpaceAccessAssignment assignment) => pending?.Assignments.Contains(assignment) == true;

    /// Makes `request` the one waiting to unlock `assignments`, the Spaces of
    /// one group, and answers the assignments whose access changed: none when
    /// they need no authentication. Throws `Rejected` with
    /// `AuthenticationBusy` while another request is waiting.
    public IReadOnlyList<SpaceAccessAssignment> Begin(IReadOnlyList<SpaceAccessAssignment> assignments, bool requiresAuthentication,
        Guid request) {
        if (!assignments.Any(assignment => IsLocked(assignment, requiresAuthentication))) return [];
        if (pending is not null) throw new Rejected(new AuthenticationBusy());
        pending = (request, [.. assignments]);
        return [.. assignments];
    }

    /// Ends the waiting request `request` made for `space`, granting every
    /// Space it was made for when the device owner authenticated. Throws
    /// `Rejected` with `StaleUnlockRequest` for any other request, which
    /// cannot consume the one waiting.
    public IReadOnlyList<SpaceAccessAssignment> Finish(Guid space, Guid request, bool authenticated) {
        if (pending is not { } current || current.Request != request || current.Assignments.All(assignment => assignment.Space != space))
            throw new Rejected(new StaleUnlockRequest(request));
        pending = null;
        if (authenticated) unlocked.UnionWith(current.Assignments);
        return current.Assignments;
    }

    /// Grants `joining` while this process holds the grant for `member`, a
    /// Space of the group it joins, so a Space added to or joining an unlocked
    /// group opens with it. Answers the assignment it granted.
    public IReadOnlyList<SpaceAccessAssignment> Extend(SpaceAccessAssignment member, SpaceAccessAssignment joining) =>
        unlocked.Contains(member) && unlocked.Add(joining) ? [joining] : [];

    /// Explicit locking always revokes: every grant for `spaces`, the Spaces
    /// of one group, and a request waiting for any of them.
    public IReadOnlyList<SpaceAccessAssignment> Lock(IReadOnlySet<Guid> spaces) {
        var revoked = unlocked.Where(assignment => spaces.Contains(assignment.Space)).ToList();
        unlocked.ExceptWith(revoked);
        if (pending?.Assignments is { } waiting && waiting.Any(assignment => spaces.Contains(assignment.Space))) {
            pending = null;
            revoked.AddRange(waiting.Where(assignment => !revoked.Contains(assignment)));
        }
        return revoked;
    }

    /// Revokes every grant and cancels the waiting request. A scene the
    /// system's authentication prompt made inactive locks nothing while that
    /// request waits.
    public IReadOnlyList<SpaceAccessAssignment> LockAll(bool sceneWentInactive) {
        if (sceneWentInactive && pending is not null) return [];
        var revoked = unlocked.ToList();
        if (pending?.Assignments is { } waiting) revoked.AddRange(waiting.Where(assignment => !revoked.Contains(assignment)));
        pending = null;
        unlocked.Clear();
        return revoked;
    }

    #endregion
}
