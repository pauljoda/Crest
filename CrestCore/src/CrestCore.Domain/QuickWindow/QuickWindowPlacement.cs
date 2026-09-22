namespace CrestCore.Domain;

/// A Quick Window's address and the Space and profile it browses in.
public readonly record struct QuickWindowPlacement(string Url, Guid SpaceId, Guid ProfileId);
