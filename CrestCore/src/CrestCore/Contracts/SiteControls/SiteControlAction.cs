namespace CrestCore.Contracts;

/// An action Site Controls offers for the page it shows: one of the four a
/// person keeps on top, or a row of More Actions. Most run a Crest command,
/// which gives them their keys and where they are offered; the rest are
/// controls with no command, such as the developer toolbar's panels.
///
/// The device store keeps the four by `Name`, so a name never changes. `All`
/// is append-only, and its order is the order More Actions lists the actions
/// within their group.
public sealed class SiteControlAction {
    #region Static Variables

    public static readonly SiteControlAction CopyLink = new(name: "copyLink", SiteControlActionGroup.Copy, title: "Copy Link",
        shortTitle: "Copy Link", symbol: "link", command: ShortcutCommand.CopyPageLink, keepsSiteControlsOpen: true);
    public static readonly SiteControlAction CopyLinkAsMarkdown = new(name: "copyLinkAsMarkdown", SiteControlActionGroup.Copy,
        title: "Copy Link as Markdown", shortTitle: "Markdown", symbol: "doc.on.clipboard",
        command: ShortcutCommand.CopyPageLinkAsMarkdown, keepsSiteControlsOpen: true);
    public static readonly SiteControlAction CopyTitle = new(name: "copyTitle", SiteControlActionGroup.Copy, title: "Copy Title",
        shortTitle: "Copy Title", symbol: "textformat", command: ShortcutCommand.CopyPageTitle, keepsSiteControlsOpen: true);
    public static readonly SiteControlAction ShowQRCode = new(name: "showQRCode", SiteControlActionGroup.Copy,
        title: "Show QR Code", shortTitle: "QR Code", symbol: "qrcode", command: ShortcutCommand.ShowPageQRCode,
        keepsSiteControlsOpen: true);
    public static readonly SiteControlAction Share = new(name: "share", SiteControlActionGroup.ShareAndExport, title: "Share…",
        shortTitle: "Share", symbol: "square.and.arrow.up", command: ShortcutCommand.SharePage);
    public static readonly SiteControlAction CapturePage = new(name: "capturePage", SiteControlActionGroup.ShareAndExport,
        title: "Capture Page", shortTitle: "Capture", symbol: "camera", command: ShortcutCommand.CapturePage,
        platforms: [DevicePlatform.Desktop]);
    public static readonly SiteControlAction Print = new(name: "print", SiteControlActionGroup.ShareAndExport, title: "Print…",
        shortTitle: "Print", symbol: "printer", command: ShortcutCommand.PrintPage);
    public static readonly SiteControlAction ExportPDF = new(name: "exportPDF", SiteControlActionGroup.ShareAndExport,
        title: "Export as PDF…", shortTitle: "PDF", symbol: "doc.richtext", command: ShortcutCommand.ExportPDF);
    public static readonly SiteControlAction SaveWebArchive = new(name: "saveWebArchive", SiteControlActionGroup.ShareAndExport,
        title: "Save Web Archive…", shortTitle: "Web Archive", symbol: "square.and.arrow.down",
        command: ShortcutCommand.SaveWebArchive);
    public static readonly SiteControlAction PinTab = new(name: "pinTab", SiteControlActionGroup.Tab, title: "Pin Tab",
        shortTitle: "Pin", symbol: "pin", command: ShortcutCommand.ToggleSelectedTabPinned, onTitle: "Unpin Tab",
        onShortTitle: "Pinned", onSymbol: "pin.fill", onWhileTabIs: TabPlacement.Pinned, keepsSiteControlsOpen: true);
    public static readonly SiteControlAction SaveTab = new(name: "saveTab", SiteControlActionGroup.Tab, title: "Save Tab",
        shortTitle: "Save", symbol: "bookmark", command: ShortcutCommand.ToggleSelectedTabSaved, onTitle: "Unsave Tab",
        onShortTitle: "Saved", onSymbol: "bookmark.fill", onWhileTabIs: TabPlacement.Saved, keepsSiteControlsOpen: true);
    public static readonly SiteControlAction DuplicateTab = new(name: "duplicateTab", SiteControlActionGroup.Tab,
        title: "Duplicate Tab", shortTitle: "Duplicate", symbol: "plus.square.on.square", command: ShortcutCommand.DuplicateTab);
    public static readonly SiteControlAction SplitWithNextTab = new(name: "splitWithNextTab", SiteControlActionGroup.Tab,
        title: "Split With Next Tab", shortTitle: "Split", symbol: "rectangle.split.2x1",
        command: ShortcutCommand.SplitWithNextTab, platforms: [DevicePlatform.Desktop]);
    public static readonly SiteControlAction OpenInPrivateWindow = new(name: "openInPrivateWindow", SiteControlActionGroup.Tab,
        title: "Open in Private Window", shortTitle: "Private", symbol: "eyeglasses",
        command: ShortcutCommand.OpenPageInPrivateWindow);
    public static readonly SiteControlAction ArchiveTab = new(name: "archiveTab", SiteControlActionGroup.Tab,
        title: "Archive Tab", shortTitle: "Archive", symbol: "archivebox", command: ShortcutCommand.ArchiveTab);
    public static readonly SiteControlAction FindInPage = new(name: "findInPage", SiteControlActionGroup.Page,
        title: "Find in Page", shortTitle: "Find", symbol: "text.magnifyingglass", command: ShortcutCommand.FindInPage);
    public static readonly SiteControlAction ReloadPage = new(name: "reloadPage", SiteControlActionGroup.Page,
        title: "Reload Page", shortTitle: "Reload", symbol: "arrow.clockwise", command: ShortcutCommand.ReloadPage,
        keepsSiteControlsOpen: true);
    public static readonly SiteControlAction ReloadIgnoringCache = new(name: "reloadIgnoringCache", SiteControlActionGroup.Page,
        title: "Reload (Ignore Cache)", shortTitle: "Hard Reload", symbol: "arrow.trianglehead.2.clockwise.rotate.90",
        command: ShortcutCommand.ReloadFromOrigin, platforms: [DevicePlatform.Desktop], keepsSiteControlsOpen: true);
    // Each platform names the engine the page would move to.
    public static readonly SiteControlAction OpenInOtherEngine = new(name: "openInOtherEngine", SiteControlActionGroup.Page,
        title: "Open Page in Other Engine", shortTitle: "Other Engine", symbol: "arrow.triangle.swap",
        platforms: [DevicePlatform.Desktop]);
    public static readonly SiteControlAction ShowTranslationControls = new(name: "showTranslationControls",
        SiteControlActionGroup.Page, title: "Show Translation Controls", shortTitle: "Translate Bar", symbol: "translate",
        command: ShortcutCommand.ToggleTranslationToolbar, onTitle: "Hide Translation Controls", keepsSiteControlsOpen: true);
    public static readonly SiteControlAction Downloads = new(name: "downloads", SiteControlActionGroup.Browser,
        title: "Downloads", shortTitle: "Downloads", symbol: "arrow.down.circle", command: ShortcutCommand.ShowDownloads);
    public static readonly SiteControlAction ShowHistory = new(name: "showHistory", SiteControlActionGroup.Browser,
        title: "Show History", shortTitle: "History", symbol: "clock", command: ShortcutCommand.ShowHistory);
    public static readonly SiteControlAction BlockElement = new(name: "blockElement", SiteControlActionGroup.Privacy,
        title: "Block Element", shortTitle: "Block", symbol: "eye.slash", command: ShortcutCommand.BlockElement);
    public static readonly SiteControlAction ShowBlockedElements = new(name: "showBlockedElements",
        SiteControlActionGroup.Privacy, title: "Show Blocked Elements", shortTitle: "Blocked", symbol: "eye",
        command: ShortcutCommand.ShowBlockedElements, keepsSiteControlsOpen: true);
    public static readonly SiteControlAction ClearCookies = new(name: "clearCookies", SiteControlActionGroup.Privacy,
        title: "Clear Cookies", shortTitle: "Cookies", symbol: "person.crop.circle.badge.xmark",
        command: ShortcutCommand.ClearSiteCookies, keepsSiteControlsOpen: true);
    public static readonly SiteControlAction ClearCache = new(name: "clearCache", SiteControlActionGroup.Privacy,
        title: "Clear Cache", shortTitle: "Cache", symbol: "trash", command: ShortcutCommand.ClearSiteCache,
        keepsSiteControlsOpen: true);
    public static readonly SiteControlAction ShowDeveloperToolbar = new(name: "showDeveloperToolbar",
        SiteControlActionGroup.Developer, title: "Show Developer Toolbar", shortTitle: "Dev Toolbar",
        symbol: "macbook.and.iphone", command: ShortcutCommand.ToggleDeveloperToolbar, onTitle: "Hide Developer Toolbar",
        platforms: [DevicePlatform.Desktop], keepsSiteControlsOpen: true);
    public static readonly SiteControlAction InspectElement = new(name: "inspectElement", SiteControlActionGroup.Developer,
        title: "Inspect Element", shortTitle: "Inspect", symbol: "scope", requiredCapability: EngineCapability.Inspector,
        platforms: [DevicePlatform.Desktop]);
    public static readonly SiteControlAction ToggleConsole = new(name: "toggleConsole", SiteControlActionGroup.Developer,
        title: "Toggle Console", shortTitle: "Console", symbol: "terminal", requiredCapability: EngineCapability.Inspector,
        platforms: [DevicePlatform.Desktop]);
    public static readonly SiteControlAction ToggleNetworkPanel = new(name: "toggleNetworkPanel",
        SiteControlActionGroup.Developer, title: "Toggle Network Panel", shortTitle: "Network", symbol: "network",
        requiredCapability: EngineCapability.Inspector, platforms: [DevicePlatform.Desktop]);
    // Developer Mode's reload menu offers it, so More Actions does only then.
    public static readonly SiteControlAction ClearCookiesAndReload = new(name: "clearCookiesAndReload",
        SiteControlActionGroup.Developer, title: "Clear Cookies and Reload", shortTitle: "Clear + Reload",
        symbol: "arrow.clockwise.circle", platforms: [DevicePlatform.Desktop], showsOnlyWhenAvailable: true,
        keepsSiteControlsOpen: true);

    public static IReadOnlyList<SiteControlAction> All { get; } = [
        CopyLink, CopyLinkAsMarkdown, CopyTitle, ShowQRCode, Share, CapturePage, Print, ExportPDF, SaveWebArchive, PinTab,
        SaveTab, DuplicateTab, SplitWithNextTab, OpenInPrivateWindow, ArchiveTab, FindInPage, ReloadPage, ReloadIgnoringCache,
        OpenInOtherEngine, ShowTranslationControls, Downloads, ShowHistory, BlockElement, ShowBlockedElements, ClearCookies, ClearCache,
        ShowDeveloperToolbar, InspectElement, ToggleConsole, ToggleNetworkPanel, ClearCookiesAndReload
    ];

    #endregion

    #region Variables

    /// The spelling the device store keeps the action under.
    public string Name { get; }

    public SiteControlActionGroup Group { get; }

    /// What More Actions, the editor and a tile's help call the action.
    [Localized]
    public string Title { get; }

    /// What a tile among the four says under its symbol.
    [Localized]
    public string ShortTitle { get; }

    /// What the action is called while what it turns on is on, such as Unpin
    /// Tab for a pinned tab, or null when it keeps its title.
    [Localized]
    public string? OnTitle { get; }

    /// What a tile says while the action's state is on, such as Pinned, or
    /// null when it keeps its short title.
    [Localized]
    public string? OnShortTitle { get; }

    /// The SF Symbol beside the action.
    public string Symbol { get; }

    /// The symbol while the action's state is on, or null when it keeps its
    /// symbol.
    public string? OnSymbol { get; }

    /// The place the page's tab is in while the action's state is on, as Pin
    /// Tab is on while the tab is pinned, or null for an action whose state
    /// the platform reads or that has none.
    public TabPlacement? OnWhileTabIs { get; }

    /// The command the action runs, whose keys it shows and whose rules say
    /// where it is offered; null for a control with no command.
    public ShortcutCommand? Command { get; }

    /// The engine capability an action with no command needs, as a command's
    /// does.
    public EngineCapability? RequiredCapability { get; }

    /// The devices that offer the action, which are the ones that can run it.
    public IReadOnlyList<DevicePlatform> Platforms { get; }

    /// Whether Site Controls stay open once the action runs: it changes the
    /// page or its tab in place, or opens a page of Site Controls, and shows
    /// what it did there or in a notice. Any other action leads elsewhere, so
    /// they close first.
    public bool KeepsSiteControlsOpen { get; }

    /// Whether More Actions lists the action only while it can run, as
    /// Developer Mode's reload choices; any other action it lists dimmed. The
    /// editor lists it either way, since the person picks it for later.
    public bool ShowsOnlyWhenAvailable { get; }

    #endregion

    #region Constructors

    private SiteControlAction(string name, SiteControlActionGroup group, string title, string shortTitle, string symbol,
        ShortcutCommand? command = null, string? onTitle = null, string? onShortTitle = null, string? onSymbol = null,
        TabPlacement? onWhileTabIs = null, EngineCapability? requiredCapability = null,
        IReadOnlyList<DevicePlatform>? platforms = null, bool keepsSiteControlsOpen = false, bool showsOnlyWhenAvailable = false) {
        Name = name;
        Group = group;
        Title = title;
        ShortTitle = shortTitle;
        OnTitle = onTitle;
        OnShortTitle = onShortTitle;
        Symbol = symbol;
        OnSymbol = onSymbol;
        OnWhileTabIs = onWhileTabIs;
        Command = command;
        RequiredCapability = requiredCapability;
        Platforms = platforms ?? DevicePlatform.All;
        KeepsSiteControlsOpen = keepsSiteControlsOpen;
        ShowsOnlyWhenAvailable = showsOnlyWhenAvailable;
    }

    #endregion

    #region Actions - Lookup

    public static SiteControlAction? Named(string? name) => All.FirstOrDefault(action => action.Name == name);

    /// Whether a device on `platform` offers the action.
    public bool IsOffered(DevicePlatform platform) => Platforms.Contains(platform);

    #endregion
}
