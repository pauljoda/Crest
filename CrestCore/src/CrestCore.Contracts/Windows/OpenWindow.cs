namespace CrestCore.Contracts;

/// Opens a window over a workspace attached to this device. A saved window
/// keeps its record in the device store across launches, and only a window
/// over the persistent session may be saved. A saved window with a record
/// shows what the record shows, or only its Space when `RestoresTabs` is
/// false. A window without a record starts as `CopyingWindowId` shows, or on
/// the launch Space. `ShowingSpaceId` names the Space it opens on instead.
/// Opening a window that is already open answers what it shows.
public sealed record OpenWindow(Guid WindowId, Guid WorkspaceId, bool Saved, Guid? CopyingWindowId, Guid? ShowingSpaceId,
    bool RestoresTabs) : WindowIntent;
