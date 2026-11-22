using CrestCore.Contracts;

namespace CrestCore.Application;

/// One part of what the device store holds: the tables it lives in, whether
/// two records hold the same of it, and how it is written. Creating the
/// tables, writing the store and `DeviceRecords.Equals` all go through `All`,
/// so a part is spelled once, here.
internal sealed class DevicePart {
    #region Static Variables

    public static readonly DevicePart Windows = new(
        [
            "CREATE TABLE IF NOT EXISTS device_window (id TEXT PRIMARY KEY, shown_space TEXT NOT NULL, used INTEGER NOT NULL)",
            "CREATE TABLE IF NOT EXISTS device_window_tab (window TEXT NOT NULL, space TEXT NOT NULL, tab TEXT, "
                + "PRIMARY KEY (window, space))",
            "CREATE TABLE IF NOT EXISTS device_window_split (window TEXT NOT NULL, split_group TEXT NOT NULL, "
                + "position INTEGER NOT NULL, share REAL NOT NULL, PRIMARY KEY (window, split_group, position))"
        ],
        (records, other) => records.Windows.SequenceEqual(other.Windows),
        (store, records, _) => store.WriteWindows(records.Windows));

    public static readonly DevicePart Reopening = new(
        ["CREATE TABLE IF NOT EXISTS device_window_reopen (id TEXT PRIMARY KEY, position INTEGER NOT NULL)"],
        (records, other) => records.Reopening.SequenceEqual(other.Reopening),
        (store, records, _) => store.WriteReopening(records.Reopening));

    public static readonly DevicePart SitePermissions = new(
        [
            "CREATE TABLE IF NOT EXISTS device_site_permission (id TEXT PRIMARY KEY, space TEXT NOT NULL, scheme TEXT NOT NULL, "
                + "host TEXT NOT NULL, port INTEGER NOT NULL, permission TEXT NOT NULL, detail TEXT, decision TEXT NOT NULL, "
                + "modified_at REAL NOT NULL, position INTEGER NOT NULL)"
        ],
        (records, other) => records.SitePermissions.SequenceEqual(other.SitePermissions),
        (store, records, _) => store.WriteSitePermissions(records.SitePermissions));

    public static readonly DevicePart SiteEngines = new(
        [
            "CREATE TABLE IF NOT EXISTS device_site_engine (scheme TEXT NOT NULL, host TEXT NOT NULL, port INTEGER NOT NULL, "
                + "engine TEXT NOT NULL, position INTEGER NOT NULL, PRIMARY KEY (scheme, host, port))"
        ],
        (records, other) => records.SiteEngines.SequenceEqual(other.SiteEngines),
        (store, records, _) => store.WriteSiteEngines(records.SiteEngines));

    public static readonly DevicePart DefaultEngine = new(
        ["CREATE TABLE IF NOT EXISTS device_engine (id INTEGER PRIMARY KEY CHECK (id = 0), engine TEXT NOT NULL)"],
        (records, other) => records.DefaultEngine == other.DefaultEngine,
        (store, records, _) => store.WriteDefaultEngine(records.DefaultEngine));

    public static readonly DevicePart Shortcuts = new(
        [
            "CREATE TABLE IF NOT EXISTS device_shortcut (command TEXT PRIMARY KEY, key TEXT, special INTEGER NOT NULL, "
                + "modifiers INTEGER NOT NULL)",
            "CREATE TABLE IF NOT EXISTS device_shortcut_preference (command TEXT PRIMARY KEY, preference TEXT NOT NULL)"
        ],
        (records, other) => records.Shortcuts.SameAs(other.Shortcuts),
        (store, records, _) => store.WriteShortcuts(records.Shortcuts));

    public static readonly DevicePart Links = new(
        [
            "CREATE TABLE IF NOT EXISTS device_link (id INTEGER PRIMARY KEY CHECK (id = 0), destination TEXT NOT NULL, "
                + "destination_space TEXT, peek_modifier TEXT NOT NULL, archive_policy TEXT NOT NULL)",
            "CREATE TABLE IF NOT EXISTS device_link_behavior (name TEXT PRIMARY KEY, is_on INTEGER NOT NULL)",
            "CREATE TABLE IF NOT EXISTS device_link_route (id TEXT PRIMARY KEY, enabled INTEGER NOT NULL, match TEXT NOT NULL, "
                + "pattern TEXT NOT NULL, space TEXT NOT NULL, position INTEGER NOT NULL)",
            "CREATE TABLE IF NOT EXISTS device_link_site (site TEXT PRIMARY KEY, space TEXT NOT NULL, position INTEGER NOT NULL)"
        ],
        (records, other) => records.Links.Equals(other.Links),
        (store, records, _) => store.WriteLinks(records.Links));

    public static readonly DevicePart SetupDraft = new(
        ["CREATE TABLE IF NOT EXISTS device_setup_draft (id INTEGER PRIMARY KEY CHECK (id = 0), document TEXT NOT NULL)"],
        (records, other) => KeptSetupDraft.Same(records.SetupDraft, other.SetupDraft),
        (store, records, _) => store.WriteSetupDraft(records.SetupDraft));

    public static readonly DevicePart SetupCompleted = new(
        ["CREATE TABLE IF NOT EXISTS device_setup (id INTEGER PRIMARY KEY CHECK (id = 0), completed INTEGER NOT NULL)"],
        (records, other) => records.SetupCompleted == other.SetupCompleted,
        (store, records, _) => store.WriteSetupCompleted(records.SetupCompleted));

    /// `device_marker` holds the adoptions an older build knows, which it
    /// rewrites; `device_adoption` holds every adoption, and no older build
    /// touches it.
    public static readonly DevicePart Adoptions = new(
        [
            "CREATE TABLE IF NOT EXISTS device_marker (name TEXT PRIMARY KEY)",
            "CREATE TABLE IF NOT EXISTS device_adoption (name TEXT PRIMARY KEY)"
        ],
        (records, other) => records.Adopted.SetEquals(other.Adopted),
        (store, records, _) => store.WriteAdoptions(records.Adopted));

    public static readonly DevicePart TabGroups = new(
        [
            "CREATE TABLE IF NOT EXISTS device_tab_group (id TEXT PRIMARY KEY, space TEXT NOT NULL, engine TEXT NOT NULL, "
                + "title TEXT NOT NULL, color TEXT NOT NULL, position INTEGER NOT NULL)"
        ],
        (records, other) => records.TabGroups.SequenceEqual(other.TabGroups),
        (store, records, _) => store.WriteTabGroups(records.TabGroups));

    /// Each Space's palette memory, kept until it is replaced, so a memory is
    /// the same only when it is the one written; only the Spaces whose memory
    /// changed are rewritten.
    public static readonly DevicePart PaletteMemories = new(
        ["CREATE TABLE IF NOT EXISTS device_palette (space TEXT PRIMARY KEY, document TEXT NOT NULL)"],
        (records, other) => records.PaletteMemories.Count == other.PaletteMemories.Count
            && records.PaletteMemories.All(entry =>
                other.PaletteMemories.TryGetValue(entry.Key, out var memory) && ReferenceEquals(memory, entry.Value)),
        (store, records, written) => store.WritePaletteMemories(records.PaletteMemories, written?.PaletteMemories));

    public static readonly DevicePart SearchCatalog = new(
        ["CREATE TABLE IF NOT EXISTS device_search_catalog (id INTEGER PRIMARY KEY CHECK (id = 0), document TEXT NOT NULL)"],
        (records, other) => Equals(records.SearchCatalog, other.SearchCatalog),
        (store, records, _) => store.WriteSearchCatalog(records.SearchCatalog));

    public static readonly DevicePart Agents = new(
        [
            "CREATE TABLE IF NOT EXISTS device_agents (id INTEGER PRIMARY KEY CHECK (id = 0), is_on INTEGER NOT NULL, "
                + "runs_scripts INTEGER NOT NULL)",
            "CREATE TABLE IF NOT EXISTS device_agent_space (space TEXT PRIMARY KEY, position INTEGER NOT NULL)",
            "CREATE TABLE IF NOT EXISTS device_agent (position INTEGER PRIMARY KEY, team TEXT, signing TEXT, path TEXT, "
                + "client TEXT, name TEXT NOT NULL)"
        ],
        (records, other) => records.Agents.Equals(other.Agents),
        (store, records, _) => store.WriteAgents(records.Agents));

    public static readonly DevicePart ReopeningPages = new(
        ["CREATE TABLE IF NOT EXISTS device_launch (id INTEGER PRIMARY KEY CHECK (id = 0), reopening_pages INTEGER NOT NULL)"],
        (records, other) => records.ReopeningPages == other.ReopeningPages,
        (store, records, _) => store.WriteReopeningPages(records.ReopeningPages));

    public static readonly DevicePart LaunchedRelease = new(
        ["CREATE TABLE IF NOT EXISTS device_release (id INTEGER PRIMARY KEY CHECK (id = 0), version TEXT NOT NULL)"],
        (records, other) => records.LaunchedRelease == other.LaunchedRelease,
        (store, records, _) => store.WriteLaunchedRelease(records.LaunchedRelease));

    public static readonly DevicePart ContentBlockingLevel = new(
        ["CREATE TABLE IF NOT EXISTS device_content_blocking (id INTEGER PRIMARY KEY CHECK (id = 0), level TEXT NOT NULL)"],
        (records, other) => records.ContentBlockingLevel == other.ContentBlockingLevel,
        (store, records, _) => store.WriteContentBlockingLevel(records.ContentBlockingLevel));

    public static readonly DevicePart FilterListChoices = new(
        ["CREATE TABLE IF NOT EXISTS device_filter_list (name TEXT PRIMARY KEY, is_on INTEGER NOT NULL)"],
        (records, other) => records.FilterListChoices.Count == other.FilterListChoices.Count
            && records.FilterListChoices.All(entry =>
                other.FilterListChoices.TryGetValue(entry.Key, out bool isOn) && isOn == entry.Value),
        (store, records, _) => store.WriteFilterListChoices(records.FilterListChoices));

    public static readonly DevicePart BlockingSites = new(
        [
            "CREATE TABLE IF NOT EXISTS device_blocking_site (space TEXT NOT NULL, scheme TEXT NOT NULL, host TEXT NOT NULL, "
                + "port INTEGER NOT NULL, position INTEGER NOT NULL, PRIMARY KEY (space, scheme, host, port))"
        ],
        (records, other) => records.BlockingSites.SequenceEqual(other.BlockingSites),
        (store, records, _) => store.WriteBlockingSites(records.BlockingSites));

    public static readonly DevicePart CustomFilterLists = new(
        [
            "CREATE TABLE IF NOT EXISTS device_custom_filter_list (id TEXT PRIMARY KEY, url TEXT NOT NULL, is_on INTEGER NOT NULL, "
                + "position INTEGER NOT NULL)"
        ],
        (records, other) => records.CustomFilterLists.SequenceEqual(other.CustomFilterLists),
        (store, records, _) => store.WriteCustomFilterLists(records.CustomFilterLists));

    public static readonly DevicePart CustomFilters = new(
        ["CREATE TABLE IF NOT EXISTS device_custom_filters (id INTEGER PRIMARY KEY CHECK (id = 0), text TEXT NOT NULL)"],
        (records, other) => records.CustomFilters == other.CustomFilters,
        (store, records, _) => store.WriteCustomFilters(records.CustomFilters));

    public static readonly DevicePart Pages = new(
        [
            "CREATE TABLE IF NOT EXISTS device_pages (id INTEGER PRIMARY KEY CHECK (id = 0), default_zoom REAL NOT NULL, "
                + "background_activity TEXT NOT NULL, high_frame_rate INTEGER NOT NULL)"
        ],
        (records, other) => records.Pages.Equals(other.Pages),
        (store, records, _) => store.WritePages(records.Pages));

    public static readonly DevicePart Downloads = new(
        [
            "CREATE TABLE IF NOT EXISTS device_space_download (space TEXT PRIMARY KEY, asks INTEGER NOT NULL, folder_name TEXT, "
                + "folder_token BLOB, position INTEGER NOT NULL)"
        ],
        (records, other) => records.Downloads.SequenceEqual(other.Downloads),
        (store, records, _) => store.WriteDownloads(records.Downloads));

    public static readonly DevicePart SyncsWithICloud = new(
        ["CREATE TABLE IF NOT EXISTS device_cloud_sync (id INTEGER PRIMARY KEY CHECK (id = 0), enabled INTEGER NOT NULL)"],
        (records, other) => records.SyncsWithICloud == other.SyncsWithICloud,
        (store, records, _) => store.WriteSyncsWithICloud(records.SyncsWithICloud));

    public static IReadOnlyList<DevicePart> All { get; } = [
        Windows, Reopening, SitePermissions, SiteEngines, DefaultEngine, Shortcuts, Links, SetupDraft, SetupCompleted, Adoptions,
        TabGroups, PaletteMemories, SearchCatalog, Agents, ReopeningPages, LaunchedRelease, ContentBlockingLevel, FilterListChoices,
        BlockingSites, CustomFilterLists, CustomFilters, Pages, Downloads, SyncsWithICloud
    ];

    #endregion

    #region Variables

    /// The statements that create the part's tables, which are additive: a
    /// build that predates one reads the file as before.
    public IReadOnlyList<string> Tables { get; }

    private readonly Func<DeviceRecords, DeviceRecords, bool> same;
    private readonly Action<SqliteConnection, DeviceRecords, DeviceRecords?> write;

    #endregion

    #region Constructors

    private DevicePart(IReadOnlyList<string> tables, Func<DeviceRecords, DeviceRecords, bool> same,
        Action<SqliteConnection, DeviceRecords, DeviceRecords?> write) {
        Tables = tables;
        this.same = same;
        this.write = write;
    }

    #endregion

    #region Actions - Records

    /// Whether `records` and `other` hold the same of this part.
    public bool Same(DeviceRecords records, DeviceRecords other) => same(records, other);

    /// Writes this part of `records` to `store` unless `written`, which the
    /// store holds now, already holds the same; with null, always.
    public void Write(SqliteConnection store, DeviceRecords records, DeviceRecords? written) {
        if (written is null || !same(records, written)) write(store, records, written);
    }

    #endregion
}
