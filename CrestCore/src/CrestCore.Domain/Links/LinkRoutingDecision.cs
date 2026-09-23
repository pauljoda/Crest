namespace CrestCore.Domain;

/// A Space for the link, and whether it opens as a Quick Window there.
/// <paramref name="SubstitutesForLockedSpace"/> is true when the routed Space was
/// locked and this Space stands in for it.
public readonly record struct LinkRoutingDecision(bool OpensQuickWindow, Guid SpaceId, bool SubstitutesForLockedSpace = false);
