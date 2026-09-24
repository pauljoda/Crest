namespace CrestCore.Contracts;

/// Another Space already uses the profile `ProfileId`, and a profile belongs
/// to one Space.
public sealed record ProfileInUse(Guid ProfileId) : Rejection;
