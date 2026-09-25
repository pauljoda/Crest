using CrestCore.Domain;

namespace CrestCore.Application;

/// What the device store holds: every saved window's record, the persistent
/// session's site permission choices in storage order, and what it has
/// adopted from an installed release.
internal sealed record DeviceRecords(IReadOnlyList<SavedWindow> Windows, IReadOnlyList<SitePermissionRecord> SitePermissions,
    IReadOnlySet<DeviceAdoption> Adopted) {
    #region Static Variables

    public static readonly DeviceRecords Empty = new([], [], new HashSet<DeviceAdoption>());

    #endregion

    #region Actions - Adoption

    /// These records, having adopted `adoption` too.
    public DeviceRecords Adopting(DeviceAdoption adoption) => this with { Adopted = new HashSet<DeviceAdoption>(Adopted) { adoption } };

    #endregion

    #region Actions - Equality

    public bool Equals(DeviceRecords? other) => other is not null
        && Windows.SequenceEqual(other.Windows)
        && SitePermissions.SequenceEqual(other.SitePermissions)
        && Adopted.SetEquals(other.Adopted);

    public override int GetHashCode() => HashCode.Combine(Windows.Count, SitePermissions.Count, Adopted.Count);

    #endregion
}
