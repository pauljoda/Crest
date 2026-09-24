namespace CrestCore.Contracts;

/// The Space keeps another profile than the one the page's engine page lives
/// in, so the page cannot move there.
public sealed record PageProfileMismatch(Guid PageId, Guid SpaceId) : Rejection;
