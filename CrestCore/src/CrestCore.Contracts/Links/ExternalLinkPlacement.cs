namespace CrestCore.Contracts;

/// The Space an external link opens in and whether it opens as a Quick Window
/// there. `SubstitutesForLockedSpace` says the routed Space was locked and this
/// one stands in for it. `SpaceId` is null when no Space may take the link.
public sealed record ExternalLinkPlacement(Guid? SpaceId, bool OpensQuickWindow, bool SubstitutesForLockedSpace);
