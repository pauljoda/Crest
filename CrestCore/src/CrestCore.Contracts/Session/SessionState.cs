namespace CrestCore.Contracts;

/// <summary>
/// The browsing session: its Spaces in order, the Space a launch opens, the marker of
/// a disposable first-install seed, Space deletions under way on this device and the
/// app-wide preferences. What each window shows is window state and never part of it.
/// <see cref="AppPreferences"/> is null until the settings kept before the core owned
/// them are imported.
/// </summary>
public sealed record SessionState(
    IReadOnlyList<SpaceState> Spaces,
    Guid? DefaultSpaceId,
    Guid? DisposableSeedMarker,
    IReadOnlyList<SpaceDeletionState> SpaceDeletions,
    AppPreferences? AppPreferences) {
    #region Actions - Equality

    public bool Equals(SessionState? other) => ReferenceEquals(this, other) || other is not null
        && Spaces.SequenceEqual(other.Spaces)
        && DefaultSpaceId == other.DefaultSpaceId
        && DisposableSeedMarker == other.DisposableSeedMarker
        && SpaceDeletions.SequenceEqual(other.SpaceDeletions)
        && AppPreferences == other.AppPreferences;

    public override int GetHashCode() => HashCode.Combine(Spaces.Count, DefaultSpaceId, DisposableSeedMarker, SpaceDeletions.Count);

    #endregion
}
