namespace CrestCore.Contracts;

/// <summary>A Space deletion under way on this device, identified by its operation.
/// The Space and its profile stay untouched until the device has erased the profile's
/// data and removed the Space. It never becomes a sync record.</summary>
public sealed record SpaceDeletionState(Guid Id, Guid SpaceId, Guid ProfileId);
