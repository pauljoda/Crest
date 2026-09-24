namespace CrestCore.Contracts;

/// The Space no longer uses the profile the intent names.
public sealed record SpaceProfileChanged(Guid SpaceId) : Rejection;
