namespace CrestCore.Application;

/// What the device store holds: every saved window's record, and whether it
/// has adopted the window records an installed release kept.
internal sealed record DeviceRecords(IReadOnlyList<SavedWindow> Windows, bool AdoptedWindowRecords) {
    #region Variables

    public static readonly DeviceRecords Empty = new([], AdoptedWindowRecords: false);

    #endregion

    #region Actions - Equality

    public bool Equals(DeviceRecords? other) =>
        other is not null && AdoptedWindowRecords == other.AdoptedWindowRecords && Windows.SequenceEqual(other.Windows);

    public override int GetHashCode() => HashCode.Combine(Windows.Count, AdoptedWindowRecords);

    #endregion
}
