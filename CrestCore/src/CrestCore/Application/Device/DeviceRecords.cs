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
/// has completed setup, what it has adopted from an installed release, the
/// tab groups whose folders follow them, the site searches, what each
/// persistent Space's palette remembers, the agent preferences, whether a
/// launch is reopening its windows' pages, the release launched last, and the
/// actions on top of Site Controls.
internal sealed record DeviceRecords(IReadOnlyList<SavedWindow> Windows, IReadOnlyList<Guid> Reopening,
    IReadOnlyList<SitePermissionRecord> SitePermissions, IReadOnlyList<SiteEngineChoice> SiteEngines, ShortcutOverrides Shortcuts,
    LinkPreferences Links, KeptSetupDraft? SetupDraft, bool SetupCompleted, IReadOnlySet<DeviceAdoption> Adopted,
    IReadOnlyList<TabGroupRecord> TabGroups, EngineKind? DefaultEngine = null) {
    #region Static Variables

    public static readonly DeviceRecords Empty = new([], [], [], [], ShortcutOverrides.None, LinkPreferences.Default,
        SetupDraft: null, SetupCompleted: false, new HashSet<DeviceAdoption>(), TabGroups: []);

    #endregion

    #region Variables

    /// What each persistent Space's palette remembers, by Space.
    public IReadOnlyDictionary<Guid, PaletteMemory> PaletteMemories { get; init; } = new Dictionary<Guid, PaletteMemory>();

    /// The device's search catalog, or null before the platform first restored it.
    public SearchCatalog? SearchCatalog { get; init; }

    /// Whether agents may use Crest, and what the person allowed them.
    public AgentPreferences Agents { get; init; } = AgentPreferences.Off;

    /// A launch is reopening its windows' pages, which it does until they
    /// settle or the person agrees to quit.
    public bool ReopeningPages { get; init; }

    /// The release this device launched last, or null before a release that
    /// keeps it launched here.
    public string? LaunchedRelease { get; init; }

    /// The level ad blocking blocks at, or null before one was chosen or first
    /// answered.
    public ContentBlockingLevel? ContentBlockingLevel { get; init; }

    /// The filter lists the person turned on or off.
    public IReadOnlyDictionary<FilterList, bool> FilterListChoices { get; init; } = new Dictionary<FilterList, bool>();

    /// The persistent session's Spaces' sites where they block no ads or
    /// trackers, in the order they were added.
    public IReadOnlyList<SiteContentBlocking> BlockingSites { get; init; } = [];

    /// The filter lists the person added, in the order added.
    public IReadOnlyList<CustomFilterList> CustomFilterLists { get; init; } = [];

    /// The person's own filters.
    public string CustomFilters { get; init; } = "";

    /// How this device shows pages.
    public PagePreferences Pages { get; init; } = PagePreferences.Default;

    /// Where each Space's downloads go, for the Spaces that do not keep the
    /// device's Downloads folder.
    public IReadOnlyList<SpaceDownloadPreferences> Downloads { get; init; } = [];

    /// Whether this device syncs with iCloud.
    public bool SyncsWithICloud { get; init; } = true;

    /// The four actions the person keeps on top of Site Controls, or none
    /// while they keep the defaults.
    public IReadOnlyList<SiteControlAction> SiteControlTopActions { get; init; } = [];

    /// The zoom each profile the persistent session browses with keeps for
    /// its hosts, least recent first.
    public IReadOnlyList<SiteZoomChoice> SiteZoom { get; init; } = [];

    #endregion

    #region Actions - Adoption

    /// These records, having adopted `adoption` too.
    public DeviceRecords Adopting(DeviceAdoption adoption) => this with { Adopted = new HashSet<DeviceAdoption>(Adopted) { adoption } };

    #endregion

    #region Actions - Equality

    public bool Equals(DeviceRecords? other) => other is not null && DevicePart.All.All(part => part.Same(this, other));

    public override int GetHashCode() => HashCode.Combine(Windows.Count, SitePermissions.Count, Adopted.Count);

    #endregion
}
