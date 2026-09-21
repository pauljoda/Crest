namespace CrestCore.Domain;

public readonly record struct SpaceAccessAssignment(Guid Space, Guid Profile);

/// Process-local grants for exact Space/profile identities. The platform owns
/// authentication UI; only a matching, still-pending result can grant access.
/// Callers serialize access. Nothing in this authority is persisted or synced.
public sealed class SpaceAccessAuthority
{
    private readonly HashSet<SpaceAccessAssignment> unlocked = [];
    private (ulong Request, SpaceAccessAssignment Assignment)? pending;
    private ulong nextRequest;

    public bool IsLocked(SpaceAccessAssignment assignment, bool requiresAuthentication) =>
        requiresAuthentication && !unlocked.Contains(assignment);

    /// Zero means no authentication is needed. Nonzero request IDs never repeat
    /// within this authority, including after cancellation and retry.
    public ulong Begin(SpaceAccessAssignment assignment, bool requiresAuthentication)
    {
        if (!IsLocked(assignment, requiresAuthentication)) return 0;
        if (pending is not null) throw new BrowserRuleException("authentication_busy");
        var request = checked(nextRequest + 1);
        nextRequest = request;
        pending = (request, assignment);
        return request;
    }

    /// Null means stale or mismatched. A mismatched reply cannot consume a
    /// different pending request. A matching denial consumes it without a grant.
    public bool? Complete(ulong request, SpaceAccessAssignment assignment, bool succeeded)
    {
        if (pending is not { } current || request != current.Request || assignment != current.Assignment) return null;
        pending = null;
        if (succeeded) unlocked.Add(assignment);
        return succeeded;
    }

    public void Lock(Guid space)
    {
        unlocked.RemoveWhere(assignment => assignment.Space == space);
        if (pending?.Assignment.Space == space) pending = null;
    }

    public bool LockAll(bool inactiveScene)
    {
        // A system authentication prompt temporarily makes its scene inactive.
        if (inactiveScene && pending is not null) return false;
        pending = null;
        unlocked.Clear();
        return true;
    }
}
