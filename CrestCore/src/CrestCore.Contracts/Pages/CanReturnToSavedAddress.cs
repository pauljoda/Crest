namespace CrestCore.Contracts;

/// Whether returning a saved or pinned tab to the address it belongs to would
/// change anything: the tab is away from that page, or its page in `WindowId`
/// is heading to another. Not for a tab that belongs nowhere or is not there.
public sealed record CanReturnToSavedAddress(Guid WorkspaceId, Guid WindowId, Guid SpaceId, Guid TabId)
    : Query<SavedAddressReturn>;
