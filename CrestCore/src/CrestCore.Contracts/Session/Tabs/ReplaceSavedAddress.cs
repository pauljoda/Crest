namespace CrestCore.Contracts;

/// Makes the page a saved or pinned tab shows the one it belongs to. A tab at
/// its saved address changes nothing. Refused with `NoSavedAddress` for a tab
/// that belongs nowhere.
public sealed record ReplaceSavedAddress(Guid WorkspaceId, Guid SpaceId, Guid TabId) : SessionIntent(WorkspaceId);
