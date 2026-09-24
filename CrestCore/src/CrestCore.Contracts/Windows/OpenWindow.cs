namespace CrestCore.Contracts;

/// Opens a window over a workspace attached to this device. A saved window
/// keeps its record in the device store across launches, and only a window
/// over the persistent session may be saved. A saved window with a record
/// shows what the record shows. A window without a record starts as
/// `CopyingWindowId` shows, or on the launch Space. When `RestoresTabs` is
/// false it keeps only that Space and shows no tab until one is chosen.
/// `ShowingTabs` then name the tab it shows in those Spaces, and
/// `ShowingSpaceId` the Space it opens on, keeping what it shows there.
/// Opening a window that is already open answers what it shows.
public sealed record OpenWindow(Guid WindowId, Guid WorkspaceId, bool Saved, Guid? CopyingWindowId, Guid? ShowingSpaceId,
    IReadOnlyList<ShownTab> ShowingTabs, bool RestoresTabs) : WindowIntent;
