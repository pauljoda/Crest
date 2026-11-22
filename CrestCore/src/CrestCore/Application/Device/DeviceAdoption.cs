namespace CrestCore.Application;

/// Something the device store carried once from what an installed release
/// kept in its defaults. The store records each one it has done by `Marker`,
/// so a later launch never carries the same thing again.
internal sealed class DeviceAdoption {
    #region Static Variables

    public static readonly DeviceAdoption WindowRecords = new(marker: "window-records", olderBuildsRead: true);
    public static readonly DeviceAdoption SitePermissions = new(marker: "site-permissions", olderBuildsRead: false);
    public static readonly DeviceAdoption Shortcuts = new(marker: "shortcuts", olderBuildsRead: false);
    public static readonly DeviceAdoption LinkPreferences = new(marker: "link-preferences", olderBuildsRead: false);
    /// The cloud transport's state, which the transport kept in a file of its own.
    public static readonly DeviceAdoption CloudTransport = new(marker: "cloud-transport", olderBuildsRead: false);
    public static readonly DeviceAdoption SetupDraft = new(marker: "setup-draft", olderBuildsRead: false);
    public static readonly DeviceAdoption SetupCompletion = new(marker: "setup-completion", olderBuildsRead: false);
    /// The windows the Chromium composition kept open for its next launch,
    /// which it listed in its defaults.
    public static readonly DeviceAdoption OpenWindows = new(marker: "open-windows", olderBuildsRead: false);
    /// The shortcuts earlier releases saved naming a digit key by the symbol
    /// Shift types on it, which now name the digit.
    public static readonly DeviceAdoption ShiftedDigitShortcuts = new(marker: "shifted-digit-shortcuts", olderBuildsRead: false);
    /// The zoom pages start at, which earlier releases kept in their defaults.
    public static readonly DeviceAdoption PageZoom = new(marker: "page-zoom", olderBuildsRead: false);
    /// What a page out of sight keeps doing, which the Mac kept in its defaults.
    public static readonly DeviceAdoption BackgroundPageActivity = new(marker: "background-page-activity", olderBuildsRead: false);
    /// Whether pages may draw faster than 60 frames a second, which the Mac
    /// kept among its WebKit flags.
    public static readonly DeviceAdoption HighFrameRate = new(marker: "high-frame-rate", olderBuildsRead: false);
    /// Whether the device syncs with iCloud, which earlier releases kept in
    /// their defaults.
    public static readonly DeviceAdoption CloudSyncEnabled = new(marker: "cloud-sync-enabled", olderBuildsRead: false);
    /// Where each Space's downloads went, which the Mac kept in its defaults.
    public static readonly DeviceAdoption SpaceDownloads = new(marker: "space-downloads", olderBuildsRead: false);

    public static IReadOnlyList<DeviceAdoption> All { get; } =
        [WindowRecords, SitePermissions, Shortcuts, LinkPreferences, CloudTransport, SetupDraft, SetupCompletion, OpenWindows,
            ShiftedDigitShortcuts, PageZoom, BackgroundPageActivity, HighFrameRate, CloudSyncEnabled, SpaceDownloads];

    #endregion

    #region Variables

    /// The name the store records.
    public string Marker { get; }

    /// A build from before the other adoptions reads this one's marker, and
    /// rewrites that build's marker table without any it does not know.
    public bool OlderBuildsRead { get; }

    #endregion

    #region Constructors

    private DeviceAdoption(string marker, bool olderBuildsRead) {
        Marker = marker;
        OlderBuildsRead = olderBuildsRead;
    }

    #endregion

    #region Actions - Lookup

    public static DeviceAdoption? Marked(string? marker) => All.FirstOrDefault(adoption => adoption.Marker == marker);

    #endregion
}
