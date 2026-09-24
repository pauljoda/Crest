namespace CrestCore.Contracts;

/// Removes the history entry for one address from a Space. The address is
/// compared the way history records it, without its fragment, so an address
/// history never records removes nothing.
public sealed record RemoveHistoryAddress(Guid WorkspaceId, Guid SpaceId, string Address) : SessionIntent(WorkspaceId);
