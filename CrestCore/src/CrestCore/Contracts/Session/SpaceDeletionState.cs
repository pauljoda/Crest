namespace CrestCore.Contracts;

/// <summary>
/// A Space deletion under way on this device, identified by its operation. It names the
/// Space with its own profile, <see cref="ProfileId"/>, and the profiles whose data it
/// erases, <see cref="Erasing"/>. The Space and its profiles stay untouched until the
/// device has erased that data and removed the Space, except that a primary hands its
/// group to <see cref="SuccessorId"/>, the Sub-Space that leads it from then on, as the
/// deletion begins; the device hands that Space the group's passwords before it erases
/// the deleted Space's. It never becomes a sync record.
/// </summary>
public sealed record SpaceDeletionState(Guid Id, Guid SpaceId, Guid ProfileId, IReadOnlyList<Guid>? ErasedProfileIds = null,
    Guid? SuccessorId = null) {
    #region Variables

    /// Collections are owned when constructed or replaced on a copy.
    public IReadOnlyList<Guid>? ErasedProfileIds {
        get;
        init => field = value is null ? null : [.. value];
    } = ErasedProfileIds is null ? null : [.. ErasedProfileIds];

    /// <summary>The profiles whose data the deletion erases: the Space's own and the
    /// one it browses with, but none a Space that stays browses with. A deletion stored
    /// before Spaces could share a session erases the Space's one profile.</summary>
    [Resolved]
    public IReadOnlyList<Guid> Erasing => ErasedProfileIds ?? [ProfileId];

    #endregion

    #region Actions - Equality

    public bool Equals(SpaceDeletionState? other) => ReferenceEquals(this, other) || other is not null
        && Id == other.Id
        && SpaceId == other.SpaceId
        && ProfileId == other.ProfileId
        && SuccessorId == other.SuccessorId
        && Erasing.SequenceEqual(other.Erasing);

    public override int GetHashCode() => HashCode.Combine(Id, SpaceId, ProfileId);

    #endregion
}
