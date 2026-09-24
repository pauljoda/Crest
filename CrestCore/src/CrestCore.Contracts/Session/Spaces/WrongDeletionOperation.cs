namespace CrestCore.Contracts;

/// The Space's deletion is not the one the intent names: another operation
/// began it, or none did.
public sealed record WrongDeletionOperation(Guid SpaceId) : Rejection;
