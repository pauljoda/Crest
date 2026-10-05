using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

#region Types

/// An engine tab group an extension made in a Space of the persistent
/// session, which the folder of the same identity shows, as the device store
/// keeps it so the folder follows the group after the next launch: the
/// engine whose pages it groups, and the group's own title and color, which
/// may differ from its folder's.
internal sealed record TabGroupRecord(Guid Id, Guid SpaceId, EngineKind Engine, string Title, TabGroupColor Color);

#endregion

/// What the device store holds: every saved window's record, the saved
/// windows the next launch reopens, back to front, the persistent session's
/// site permission choices in storage order and its site engine choices least
/// recent first, the person's shortcut choices and link preferences, the
/// unfinished manual setup it keeps for the next launch, whether this device
/// has completed setup, what it has adopted from an installed release, and the
/// tab groups whose folders follow them.
internal sealed record DeviceRecords(IReadOnlyList<SavedWindow> Windows, IReadOnlyList<Guid> Reopening,
    IReadOnlyList<SitePermissionRecord> SitePermissions, IReadOnlyList<SiteEngineChoice> SiteEngines, ShortcutOverrides Shortcuts,
    LinkPreferences Links, KeptSetupDraft? SetupDraft, bool SetupCompleted, IReadOnlySet<DeviceAdoption> Adopted,
    IReadOnlyList<TabGroupRecord> TabGroups, EngineKind? DefaultEngine = null) {
    #region Static Variables

    public static readonly DeviceRecords Empty = new([], [], [], [], ShortcutOverrides.None, LinkPreferencePolicy.Default,
        SetupDraft: null, SetupCompleted: false, new HashSet<DeviceAdoption>(), TabGroups: []);

    #endregion

    #region Actions - Adoption

    /// These records, having adopted `adoption` too.
    public DeviceRecords Adopting(DeviceAdoption adoption) => this with { Adopted = new HashSet<DeviceAdoption>(Adopted) { adoption } };

    #endregion

    #region Actions - Equality

    public bool Equals(DeviceRecords? other) => other is not null
        && Windows.SequenceEqual(other.Windows)
        && Reopening.SequenceEqual(other.Reopening)
        && SitePermissions.SequenceEqual(other.SitePermissions)
        && SiteEngines.SequenceEqual(other.SiteEngines)
        && DefaultEngine == other.DefaultEngine
        && Shortcuts.SameAs(other.Shortcuts)
        && Links.Equals(other.Links)
        && KeptSetupDraft.Same(SetupDraft, other.SetupDraft)
        && SetupCompleted == other.SetupCompleted
        && Adopted.SetEquals(other.Adopted)
        && TabGroups.SequenceEqual(other.TabGroups);

    public override int GetHashCode() => HashCode.Combine(Windows.Count, SitePermissions.Count, Adopted.Count);

    #endregion
}
