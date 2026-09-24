namespace CrestCore.Contracts;

/// The Space already pins `Capacity` tabs, so it pins no more.
public sealed record PinnedTabsFull(int Capacity) : Rejection;
