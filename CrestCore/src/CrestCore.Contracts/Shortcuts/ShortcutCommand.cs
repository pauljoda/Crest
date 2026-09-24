using System.Globalization;

using static CrestCore.Contracts.ShortcutModifiers;

namespace CrestCore.Contracts;

/// A browser command a person can reach from the menu bar, the launcher and
/// the shortcut settings list, and bind a key combination to.
///
/// A command carries everything that differs by command: its stored `Name`,
/// its section, its English title, search terms and symbol, its default keys
/// on each platform, the engine capability its whole feature needs, and, for
/// a numbered command, what it selects. Persisted shortcut overrides are keyed
/// by `Name`, so a name never changes. `All` is append-only, and its order is
/// the order the settings list shows within a section.
public sealed class ShortcutCommand {
    #region Types

    /// Each platform performs a command with its own code, so the one place
    /// that performs it switches over the kind. Every numbered command selects
    /// what the core's numbered-selection rule says, so they share one kind.
    public enum Kinds {
        NewWindow,
        NewBlankWindow,
        NewTab,
        NewQuickWindow,
        NewPrivateWindow,
        CloseTabOrWindow,
        CloseWindow,
        OpenLocation,
        Back,
        Forward,
        ReloadPage,
        StopLoading,
        ReloadFromOrigin,
        ToggleSelectedTabPinned,
        DuplicateTab,
        ReopenClosedTab,
        ClearUnpinnedTabs,
        ArchiveTab,
        PreviousTab,
        NextTab,
        MostRecentTab,
        SelectNumbered,
        PreviousSpace,
        NextSpace,
        ToggleReaderMode,
        ToggleContentBlocking,
        FindInPage,
        ZoomIn,
        ZoomOut,
        ActualSize,
        CopyPageLink,
        CopyPageLinkAsMarkdown,
        SharePage,
        ExportPDF,
        SaveWebArchive,
        PrintPage,
        ToggleSidebar,
        ShowHistory,
        ShowArchive,
        ShowDownloads,
        ShowWebInspector,
        SplitWithNextTab,
        FocusNextSplitCard,
        FocusPreviousSplitCard,
        RemoveTabFromSplit,
        SeparateSplitTabs,
        MoveSplitCardLeft,
        MoveSplitCardRight,
        ToggleDeveloperToolbar,
        ToggleTranslationToolbar,
        OpenFile
    }

    #endregion

    #region Variables

    public static readonly ShortcutCommand NewWindow = new(Kinds.NewWindow, name: "newWindow", ShortcutSection.Everyday,
        title: "New Window", symbol: "macwindow.badge.plus", shortcuts: Everywhere(Character("n", Command)));
    public static readonly ShortcutCommand NewBlankWindow = new(Kinds.NewBlankWindow, name: "newBlankWindow",
        ShortcutSection.Everyday, title: "New Blank Window", symbol: "macwindow.badge.plus",
        shortcuts: [new(DevicePlatform.Desktop, Character("n", Command | Option), YieldsToOverrides: true)],
        searchTerms: "temporary disposable unsynced window");
    public static readonly ShortcutCommand NewTab = new(Kinds.NewTab, name: "newTab", ShortcutSection.Everyday,
        title: "New Tab", symbol: "plus.square", shortcuts: Everywhere(Character("t", Command)));
    // The Mac moves the Quick Window one modifier up to make room for the blank window.
    public static readonly ShortcutCommand NewQuickWindow = new(Kinds.NewQuickWindow, name: "newQuickWindow",
        ShortcutSection.Everyday, title: "New Quick Window", symbol: "macwindow.badge.plus",
        shortcuts: [
            new(DevicePlatform.Desktop, Character("n", Command | Option | Shift), YieldsToOverrides: true),
            new(DevicePlatform.Mobile, Character("n", Command | Option), YieldsToOverrides: false)
        ],
        searchTerms: "little arc quick lookup");
    public static readonly ShortcutCommand NewPrivateWindow = new(Kinds.NewPrivateWindow, name: "newPrivateWindow",
        ShortcutSection.Everyday, title: "New Private Window", symbol: "eyeglasses",
        shortcuts: Everywhere(Character("n", Command | Shift)), searchTerms: "incognito private browsing");
    public static readonly ShortcutCommand CloseTabOrWindow = new(Kinds.CloseTabOrWindow, name: "closeTabOrWindow",
        ShortcutSection.Everyday, title: "Close Current Tab or Window", symbol: "xmark.square",
        shortcuts: Everywhere(Character("w", Command)), searchTerms: "close archive current tab window");
    public static readonly ShortcutCommand CloseWindow = new(Kinds.CloseWindow, name: "closeWindow", ShortcutSection.Everyday,
        title: "Close Window", symbol: "xmark.square", shortcuts: Everywhere(Character("w", Command | Shift)));
    public static readonly ShortcutCommand OpenLocation = new(Kinds.OpenLocation, name: "openLocation",
        ShortcutSection.Everyday, title: "Open Location", symbol: "magnifyingglass",
        shortcuts: Everywhere(Character("l", Command)), searchTerms: "change current tab url address focus");
    public static readonly ShortcutCommand Back = new(Kinds.Back, name: "back", ShortcutSection.Everyday, title: "Back",
        symbol: "chevron.left", shortcuts: Everywhere(Character("[", Command)));
    public static readonly ShortcutCommand Forward = new(Kinds.Forward, name: "forward", ShortcutSection.Everyday,
        title: "Forward", symbol: "chevron.right", shortcuts: Everywhere(Character("]", Command)));
    public static readonly ShortcutCommand ReloadPage = new(Kinds.ReloadPage, name: "reloadPage", ShortcutSection.Everyday,
        title: "Reload Page", symbol: "arrow.clockwise", shortcuts: Everywhere(Character("r", Command)));
    public static readonly ShortcutCommand StopLoading = new(Kinds.StopLoading, name: "stopLoading", ShortcutSection.Everyday,
        title: "Stop Loading", symbol: "xmark.circle", shortcuts: Everywhere(Character(".", Command)));
    public static readonly ShortcutCommand ReloadFromOrigin = new(Kinds.ReloadFromOrigin, name: "reloadFromOrigin",
        ShortcutSection.Everyday, title: "Reload from Origin", symbol: "arrow.clockwise",
        shortcuts: Everywhere(Character("r", Command | Shift)));
    public static readonly ShortcutCommand ToggleSelectedTabPinned = new(Kinds.ToggleSelectedTabPinned,
        name: "toggleSelectedTabPinned", ShortcutSection.Tabs, title: "Pin or Unpin Current Tab", symbol: "pin",
        shortcuts: Everywhere(Character("d", Command)), searchTerms: "favorite bookmark pin unpin",
        menuTitle: "Pin or Unpin Tab");
    public static readonly ShortcutCommand DuplicateTab = new(Kinds.DuplicateTab, name: "duplicateTab", ShortcutSection.Tabs,
        title: "Duplicate Tab", symbol: "plus.square.on.square");
    public static readonly ShortcutCommand ReopenClosedTab = new(Kinds.ReopenClosedTab, name: "reopenClosedTab",
        ShortcutSection.Tabs, title: "Reopen Last Closed Tab", symbol: "arrow.uturn.backward",
        shortcuts: Everywhere(Character("t", Command | Shift)), menuTitle: "Reopen Closed Tab");
    public static readonly ShortcutCommand ClearUnpinnedTabs = new(Kinds.ClearUnpinnedTabs, name: "clearUnpinnedTabs",
        ShortcutSection.Tabs, title: "Clear Unpinned Tabs", symbol: "sparkles",
        shortcuts: Everywhere(Character("k", Command | Shift)), searchTerms: "clean tidy archive unpinned tabs");
    public static readonly ShortcutCommand ArchiveTab = new(Kinds.ArchiveTab, name: "archiveTab", ShortcutSection.Tabs,
        title: "Archive Tab", symbol: "archivebox", shortcuts: Everywhere(Character("e", Command)));
    public static readonly ShortcutCommand PreviousTab = new(Kinds.PreviousTab, name: "previousTab", ShortcutSection.Tabs,
        title: "Previous Tab", symbol: "chevron.up", shortcuts: Everywhere(Special("upArrow", Command | Option)),
        searchTerms: "switch cycle tabs up down arrow");
    public static readonly ShortcutCommand NextTab = new(Kinds.NextTab, name: "nextTab", ShortcutSection.Tabs,
        title: "Next Tab", symbol: "chevron.down", shortcuts: Everywhere(Special("downArrow", Command | Option)),
        searchTerms: "switch cycle tabs up down arrow");
    public static readonly ShortcutCommand MostRecentTab = new(Kinds.MostRecentTab, name: "mostRecentTab",
        ShortcutSection.Tabs, title: "Most Recent Tab", symbol: "arrow.left.arrow.right",
        shortcuts: Everywhere(Special("tab", Control)), searchTerms: "toggle recent switch tabs");
    public static readonly ShortcutCommand SelectTab1 = SelectingTab(name: "selectTab1", number: 1);
    public static readonly ShortcutCommand SelectTab2 = SelectingTab(name: "selectTab2", number: 2);
    public static readonly ShortcutCommand SelectTab3 = SelectingTab(name: "selectTab3", number: 3);
    public static readonly ShortcutCommand SelectTab4 = SelectingTab(name: "selectTab4", number: 4);
    public static readonly ShortcutCommand SelectTab5 = SelectingTab(name: "selectTab5", number: 5);
    public static readonly ShortcutCommand SelectTab6 = SelectingTab(name: "selectTab6", number: 6);
    public static readonly ShortcutCommand SelectTab7 = SelectingTab(name: "selectTab7", number: 7);
    public static readonly ShortcutCommand SelectTab8 = SelectingTab(name: "selectTab8", number: 8);
    public static readonly ShortcutCommand SelectTab9 = SelectingTab(name: "selectTab9", number: 9);
    public static readonly ShortcutCommand PreviousSpace = new(Kinds.PreviousSpace, name: "previousSpace",
        ShortcutSection.Spaces, title: "Previous Space", symbol: "chevron.up",
        shortcuts: Everywhere(Special("leftArrow", Command | Option)), searchTerms: "switch cycle spaces left right arrow");
    public static readonly ShortcutCommand NextSpace = new(Kinds.NextSpace, name: "nextSpace", ShortcutSection.Spaces,
        title: "Next Space", symbol: "chevron.down", shortcuts: Everywhere(Special("rightArrow", Command | Option)),
        searchTerms: "switch cycle spaces left right arrow");
    public static readonly ShortcutCommand SelectSpace1 = SelectingSpace(name: "selectSpace1", number: 1);
    public static readonly ShortcutCommand SelectSpace2 = SelectingSpace(name: "selectSpace2", number: 2);
    public static readonly ShortcutCommand SelectSpace3 = SelectingSpace(name: "selectSpace3", number: 3);
    public static readonly ShortcutCommand SelectSpace4 = SelectingSpace(name: "selectSpace4", number: 4);
    public static readonly ShortcutCommand SelectSpace5 = SelectingSpace(name: "selectSpace5", number: 5);
    public static readonly ShortcutCommand SelectSpace6 = SelectingSpace(name: "selectSpace6", number: 6);
    public static readonly ShortcutCommand SelectSpace7 = SelectingSpace(name: "selectSpace7", number: 7);
    public static readonly ShortcutCommand SelectSpace8 = SelectingSpace(name: "selectSpace8", number: 8);
    public static readonly ShortcutCommand SelectSpace9 = SelectingSpace(name: "selectSpace9", number: 9);
    public static readonly ShortcutCommand ToggleReaderMode = new(Kinds.ToggleReaderMode, name: "toggleReaderMode",
        ShortcutSection.Page, title: "Show or Hide Reader", symbol: "doc.plaintext", searchTerms: "reader reading mode",
        requiredCapability: EngineCapabilities.Reader);
    public static readonly ShortcutCommand ToggleContentBlocking = new(Kinds.ToggleContentBlocking,
        name: "toggleContentBlocking", ShortcutSection.Page, title: "Toggle Content Blocking", symbol: "shield",
        searchTerms: "ads trackers privacy protection", requiredCapability: EngineCapabilities.ContentBlocking);
    public static readonly ShortcutCommand FindInPage = new(Kinds.FindInPage, name: "findInPage", ShortcutSection.Page,
        title: "Find in Page", symbol: "text.magnifyingglass", shortcuts: Everywhere(Character("f", Command)));
    public static readonly ShortcutCommand ZoomIn = new(Kinds.ZoomIn, name: "zoomIn", ShortcutSection.Page, title: "Zoom In",
        symbol: "plus.magnifyingglass", shortcuts: Everywhere(Character("+", Command)));
    public static readonly ShortcutCommand ZoomOut = new(Kinds.ZoomOut, name: "zoomOut", ShortcutSection.Page,
        title: "Zoom Out", symbol: "minus.magnifyingglass", shortcuts: Everywhere(Character("-", Command)));
    public static readonly ShortcutCommand ActualSize = new(Kinds.ActualSize, name: "actualSize", ShortcutSection.Page,
        title: "Actual Size", symbol: "1.magnifyingglass", shortcuts: Everywhere(Character("0", Command)),
        searchTerms: "reset zoom zero");
    public static readonly ShortcutCommand CopyPageLink = new(Kinds.CopyPageLink, name: "copyPageLink", ShortcutSection.Page,
        title: "Copy Page Link", symbol: "link", shortcuts: Everywhere(Character("c", Command | Shift)),
        searchTerms: "copy url address clipboard");
    public static readonly ShortcutCommand CopyPageLinkAsMarkdown = new(Kinds.CopyPageLinkAsMarkdown,
        name: "copyPageLinkAsMarkdown", ShortcutSection.Page, title: "Copy Page Link as Markdown", symbol: "link",
        shortcuts: Everywhere(Character("c", Command | Option | Shift)), searchTerms: "copy url address markdown clipboard");
    public static readonly ShortcutCommand SharePage = new(Kinds.SharePage, name: "sharePage", ShortcutSection.Page,
        title: "Share Page", symbol: "square.and.arrow.up", menuTitle: "Share…");
    public static readonly ShortcutCommand ExportPDF = new(Kinds.ExportPDF, name: "exportPDF", ShortcutSection.Page,
        title: "Export as PDF", symbol: "square.and.arrow.down", menuTitle: "Export as PDF…");
    public static readonly ShortcutCommand SaveWebArchive = new(Kinds.SaveWebArchive, name: "saveWebArchive",
        ShortcutSection.Page, title: "Save Web Archive", symbol: "square.and.arrow.down", menuTitle: "Save Web Archive…");
    public static readonly ShortcutCommand PrintPage = new(Kinds.PrintPage, name: "printPage", ShortcutSection.Page,
        title: "Print Page", symbol: "printer", shortcuts: Everywhere(Character("p", Command)), menuTitle: "Print…");
    public static readonly ShortcutCommand ToggleSidebar = new(Kinds.ToggleSidebar, name: "toggleSidebar",
        ShortcutSection.View, title: "Show or Hide Sidebar", symbol: "sidebar.leading",
        shortcuts: Everywhere(Character("s", Command)), menuTitle: "Toggle Sidebar");
    public static readonly ShortcutCommand ShowHistory = new(Kinds.ShowHistory, name: "showHistory", ShortcutSection.View,
        title: "Show History", symbol: "clock", shortcuts: Everywhere(Character("y", Command)),
        searchTerms: "visited pages history");
    public static readonly ShortcutCommand ShowArchive = new(Kinds.ShowArchive, name: "showArchive", ShortcutSection.View,
        title: "Show Archive", symbol: "archivebox", searchTerms: "closed tabs archive");
    public static readonly ShortcutCommand ShowDownloads = new(Kinds.ShowDownloads, name: "showDownloads",
        ShortcutSection.View, title: "Show Downloads", symbol: "arrow.down.circle",
        shortcuts: Everywhere(Character("j", Command | Shift)), searchTerms: "download files transfers");
    // The stored name is the one this command shipped with.
    public static readonly ShortcutCommand ShowWebInspector = new(Kinds.ShowWebInspector, name: "webInspectorInstructions",
        ShortcutSection.View, title: "Show Web Inspector", symbol: "hammer", shortcuts: Everywhere(Character("i", Command | Option)),
        searchTerms: "developer tools inspect element webkit safari");
    public static readonly ShortcutCommand SplitWithNextTab = new(Kinds.SplitWithNextTab, name: "splitWithNextTab",
        ShortcutSection.Tabs, title: "Split With Next Tab", symbol: "rectangle.split.2x1",
        searchTerms: "split view cards side by side columns");
    // ⌃⌘←/→ is the one arrow pair left free: ⌥⌘←/→ switch Spaces and ⌥⌘↑/↓ tabs.
    // Splitting a single card stays menu-only because Arc's ⌘⇧+ collides with
    // zoom and ⌘W already closes the focused card.
    public static readonly ShortcutCommand FocusNextSplitCard = new(Kinds.FocusNextSplitCard, name: "focusNextSplitCard",
        ShortcutSection.Tabs, title: "Focus Next Split Card", symbol: "rectangle.righthalf.filled",
        shortcuts: Everywhere(Special("rightArrow", Control | Command)), searchTerms: "split view cards focus cycle left right arrow");
    public static readonly ShortcutCommand FocusPreviousSplitCard = new(Kinds.FocusPreviousSplitCard,
        name: "focusPreviousSplitCard", ShortcutSection.Tabs, title: "Focus Previous Split Card",
        symbol: "rectangle.lefthalf.filled", shortcuts: Everywhere(Special("leftArrow", Control | Command)),
        searchTerms: "split view cards focus cycle left right arrow");
    public static readonly ShortcutCommand RemoveTabFromSplit = new(Kinds.RemoveTabFromSplit, name: "removeTabFromSplit",
        ShortcutSection.Tabs, title: "Remove Tab From Split", symbol: "minus.rectangle",
        searchTerms: "split view card remove leave unsplit");
    public static readonly ShortcutCommand SeparateSplitTabs = new(Kinds.SeparateSplitTabs, name: "separateSplitTabs",
        ShortcutSection.Tabs, title: "Separate All Tabs", symbol: "rectangle.split.2x1.slash",
        shortcuts: Everywhere(Character("u", Command | Option)), searchTerms: "split view break up unsplit separate cards");
    // A fixed-direction arrow, not a mirroring backward or forward one: the
    // command names a side of the screen, and it still names that side in a
    // right-to-left layout. ⇧⌘←/→ shadows extend-selection only while a split
    // is on screen; the menu items carrying it are disabled otherwise.
    public static readonly ShortcutCommand MoveSplitCardLeft = new(Kinds.MoveSplitCardLeft, name: "moveSplitCardLeft",
        ShortcutSection.Tabs, title: "Move Split Card Left", symbol: "arrow.left.square",
        shortcuts: Everywhere(Special("leftArrow", Command | Shift)),
        searchTerms: "split view cards move reorder rearrange left right arrow");
    public static readonly ShortcutCommand MoveSplitCardRight = new(Kinds.MoveSplitCardRight, name: "moveSplitCardRight",
        ShortcutSection.Tabs, title: "Move Split Card Right", symbol: "arrow.right.square",
        shortcuts: Everywhere(Special("rightArrow", Command | Shift)),
        searchTerms: "split view cards move reorder rearrange left right arrow");
    public static readonly ShortcutCommand ToggleDeveloperToolbar = new(Kinds.ToggleDeveloperToolbar,
        name: "toggleDeveloperToolbar", ShortcutSection.View, title: "Show or Hide Developer Toolbar",
        symbol: "macbook.and.iphone", shortcuts: Everywhere(Character("i", Command | Shift)),
        searchTerms: "developer toolbar viewport preview responsive custom size", menuTitle: "Show Developer Toolbar");
    public static readonly ShortcutCommand ToggleTranslationToolbar = new(Kinds.ToggleTranslationToolbar,
        name: "toggleTranslationToolbar", ShortcutSection.View, title: "Show or Hide Translation Toolbar", symbol: "translate",
        shortcuts: Everywhere(Character("l", Command | Shift)), searchTerms: "translate translation language toolbar show hide",
        requiredCapability: EngineCapabilities.Translation);
    public static readonly ShortcutCommand OpenFile = new(Kinds.OpenFile, name: "openFile", ShortcutSection.Everyday,
        title: "Open File", symbol: "folder", searchTerms: "open local file document html pdf archive webarchive mhtml",
        menuTitle: "Open File…");

    public static IReadOnlyList<ShortcutCommand> All { get; } = [
        NewWindow, NewBlankWindow, NewTab, NewQuickWindow, NewPrivateWindow, CloseTabOrWindow, CloseWindow, OpenLocation, Back,
        Forward, ReloadPage, StopLoading, ReloadFromOrigin, ToggleSelectedTabPinned, DuplicateTab, ReopenClosedTab,
        ClearUnpinnedTabs, ArchiveTab, PreviousTab, NextTab, MostRecentTab, SelectTab1, SelectTab2, SelectTab3, SelectTab4,
        SelectTab5, SelectTab6, SelectTab7, SelectTab8, SelectTab9, PreviousSpace, NextSpace, SelectSpace1, SelectSpace2,
        SelectSpace3, SelectSpace4, SelectSpace5, SelectSpace6, SelectSpace7, SelectSpace8, SelectSpace9, ToggleReaderMode,
        ToggleContentBlocking, FindInPage, ZoomIn, ZoomOut, ActualSize, CopyPageLink, CopyPageLinkAsMarkdown, SharePage,
        ExportPDF, SaveWebArchive, PrintPage, ToggleSidebar, ShowHistory, ShowArchive, ShowDownloads, ShowWebInspector,
        SplitWithNextTab, FocusNextSplitCard, FocusPreviousSplitCard, RemoveTabFromSplit, SeparateSplitTabs,
        MoveSplitCardLeft, MoveSplitCardRight, ToggleDeveloperToolbar, ToggleTranslationToolbar, OpenFile
    ];

    public Kinds Kind { get; }

    /// The spelling persisted overrides and JSON policy requests use.
    public string Name { get; }

    public ShortcutSection Section { get; }

    /// What the settings list, the launcher and the menu bar call the command.
    /// A numbered command's title carries its number.
    [Localized(Argument = nameof(Number))]
    public string Title { get; }

    /// More words a search for the command should match, beyond its title and
    /// section.
    [Localized]
    public string? SearchTerms { get; }

    /// The menu bar's label when it differs from the title, such as one that
    /// ends in an ellipsis because the command asks for more.
    [Localized]
    public string? MenuTitle { get; }

    /// The SF Symbol shown beside the command.
    public string Symbol { get; }

    /// The engine capability, in its descriptor spelling, that the command's
    /// whole feature depends on. An engine without it never offers the command.
    /// Document actions an active page may lack, such as printing, stay offered
    /// and are dimmed by the page instead.
    public string? RequiredCapability { get; }

    /// What a numbered command selects from, and the position it selects,
    /// counting from one. Both are null for every other command.
    public NumberedSelectionTarget? Selects { get; }

    public int? Number { get; }

    /// The default keys on each platform that has one.
    public IReadOnlyList<ShortcutDefault> DefaultShortcuts { get; }

    #endregion

    #region Constructors

    private ShortcutCommand(Kinds kind, string name, ShortcutSection section, string title, string symbol,
        IReadOnlyList<ShortcutDefault>? shortcuts = null, string? searchTerms = null, string? menuTitle = null,
        string? requiredCapability = null, NumberedSelectionTarget? selects = null, int? number = null) {
        Kind = kind;
        Name = name;
        Section = section;
        Title = title;
        SearchTerms = searchTerms;
        MenuTitle = menuTitle;
        Symbol = symbol;
        RequiredCapability = requiredCapability;
        Selects = selects;
        Number = number;
        DefaultShortcuts = shortcuts ?? [];
    }

    /// ⌘1–⌘9 select the Nth tab in sidebar order.
    private static ShortcutCommand SelectingTab(string name, int number) => new(Kinds.SelectNumbered, name, ShortcutSection.Tabs,
        title: "Select Tab %lld", symbol: "square.on.square", shortcuts: Everywhere(Character(Digit(number), Command)),
        selects: NumberedSelectionTarget.Tab, number: number);

    /// ⌃1–⌃9 select the Nth Space.
    private static ShortcutCommand SelectingSpace(string name, int number) => new(Kinds.SelectNumbered, name,
        ShortcutSection.Spaces, title: "Select Space %lld", symbol: "rectangle.3.group",
        shortcuts: Everywhere(Character(Digit(number), Control)), selects: NumberedSelectionTarget.Space, number: number);

    #endregion

    #region Actions - Lookup

    public static ShortcutCommand? Named(string? name) => All.FirstOrDefault(command => command.Name == name);

    /// The command's default on `platform`, or null when it has none there.
    public ShortcutDefault? DefaultShortcut(DevicePlatform platform) =>
        DefaultShortcuts.FirstOrDefault(shortcut => shortcut.Platform == platform);

    #endregion

    #region Actions - Catalog

    private static IReadOnlyList<ShortcutDefault> Everywhere(KeyCombination keys) =>
        [.. DevicePlatform.All.Select(platform => new ShortcutDefault(platform, keys, YieldsToOverrides: false))];

    private static KeyCombination Character(string character, ShortcutModifiers modifiers) => new(character, false, modifiers);

    private static KeyCombination Special(string key, ShortcutModifiers modifiers) => new(key, true, modifiers);

    private static string Digit(int number) => number.ToString(CultureInfo.InvariantCulture);

    #endregion
}
