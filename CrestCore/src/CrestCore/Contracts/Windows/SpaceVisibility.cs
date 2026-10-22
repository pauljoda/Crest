namespace CrestCore.Contracts;

/// The Spaces of the person's own session this device leaves out of its
/// windows: they keep syncing, but no window shows them, and no list a window
/// offers names them. The device store keeps the choice and never syncs it, so
/// a Space another device adds shows here until the person hides it. At least
/// one Space the session keeps always stays shown.
public sealed record SpaceVisibility(IReadOnlyList<Guid> HiddenSpaceIds) {
    #region Static Variables

    /// The visibility of a device that hides nothing, and of every workspace
    /// other than the person's own session.
    internal static SpaceVisibility ShowingAll { get; } = new([]);

    #endregion

    #region Actions - Rules

    /// Whether the device shows `spaceId`.
    public bool Shows(Guid spaceId) => !HiddenSpaceIds.Contains(spaceId);

    /// The ones of `spaces` the device shows, in their order.
    internal IReadOnlyList<SpaceState> Showable(IEnumerable<SpaceState> spaces) => [.. spaces.Where(space => Shows(space.Id))];

    #endregion

    #region Actions - Mutators

    /// Shows `spaceId` again. The other hidden Spaces keep their places.
    public SpaceVisibility Showing(Guid spaceId) =>
        this with { HiddenSpaceIds = [.. HiddenSpaceIds.Where(candidate => candidate != spaceId)] };

    /// Hides `spaceId` after the other hidden Spaces, or keeps its place when
    /// it is hidden already.
    public SpaceVisibility Hiding(Guid spaceId) =>
        HiddenSpaceIds.Contains(spaceId) ? this : this with { HiddenSpaceIds = [.. HiddenSpaceIds, spaceId] };

    /// Forgets every hidden Space `session` no longer holds, and shows every
    /// Space again once none it keeps would stay shown, as when another device
    /// deleted the only one this device showed. The person's own session never
    /// stands empty for a while, so an empty `session` is not a concern here.
    internal SpaceVisibility Reconciled(SessionState session) {
        var stayingSpaces = session.Spaces.Where(space => session.SpaceDeletions.All(deletion => deletion.SpaceId != space.Id));
        if (HiddenSpaceIds.Count > 0 && !stayingSpaces.Any(space => Shows(space.Id))) return ShowingAll;
        var heldSpaceIds = session.Spaces.Select(space => space.Id).ToHashSet();
        return HiddenSpaceIds.All(heldSpaceIds.Contains) ? this : this with { HiddenSpaceIds = [.. HiddenSpaceIds.Where(heldSpaceIds.Contains)] };
    }

    #endregion

    #region Actions - Equality

    public bool Equals(SpaceVisibility? other) => other is not null && HiddenSpaceIds.SequenceEqual(other.HiddenSpaceIds);

    public override int GetHashCode() => HiddenSpaceIds.Count;

    #endregion
}
