namespace CrestCore.Domain;

/// A Space for the link, and whether it opens as a Quick Window there.
public readonly record struct LinkRoutingDecision(bool OpensQuickWindow, Guid SpaceId);
