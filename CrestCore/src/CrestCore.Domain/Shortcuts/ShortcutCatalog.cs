using System.Globalization;

namespace CrestCore.Domain;

/// Crest's default key chords, keyed by the command identities the native
/// layer persists. A command absent here has no default chord. ⌘1–⌘9 select
/// the Nth tab and ⌃1–⌃9 the Nth Space.
public static class ShortcutCatalog {
    #region Variables

    public const int NumberedCount = 9;
    public const string NewBlankWindow = "newBlankWindow";
    public const string NewQuickWindow = "newQuickWindow";

    public static readonly IReadOnlyList<string> TabSelectionCommands =
        Enumerable.Range(1, NumberedCount).Select(number => $"selectTab{number}").ToArray();

    public static readonly IReadOnlyList<string> SpaceSelectionCommands =
        Enumerable.Range(1, NumberedCount).Select(number => $"selectSpace{number}").ToArray();

    private const int Cmd = ShortcutChord.Command;
    private const int Opt = ShortcutChord.Option;
    private const int Ctrl = ShortcutChord.Control;
    private const int Shift = ShortcutChord.Shift;

    private static readonly IReadOnlyDictionary<string, ShortcutChord> Shared =
        new Dictionary<string, ShortcutChord>(StringComparer.Ordinal) {
            ["newWindow"] = Key("n", Cmd),
            ["newTab"] = Key("t", Cmd),
            [NewQuickWindow] = Key("n", Cmd | Opt),
            ["newPrivateWindow"] = Key("n", Cmd | Shift),
            ["closeTabOrWindow"] = Key("w", Cmd),
            ["closeWindow"] = Key("w", Cmd | Shift),
            ["openLocation"] = Key("l", Cmd),
            ["back"] = Key("[", Cmd),
            ["forward"] = Key("]", Cmd),
            ["reloadPage"] = Key("r", Cmd),
            ["stopLoading"] = Key(".", Cmd),
            ["reloadFromOrigin"] = Key("r", Cmd | Shift),
            ["toggleSelectedTabPinned"] = Key("d", Cmd),
            ["reopenClosedTab"] = Key("t", Cmd | Shift),
            ["clearUnpinnedTabs"] = Key("k", Cmd | Shift),
            ["archiveTab"] = Key("e", Cmd),
            ["previousTab"] = Special("upArrow", Cmd | Opt),
            ["nextTab"] = Special("downArrow", Cmd | Opt),
            ["mostRecentTab"] = Special("tab", Ctrl),
            ["previousSpace"] = Special("leftArrow", Cmd | Opt),
            ["nextSpace"] = Special("rightArrow", Cmd | Opt),
            ["findInPage"] = Key("f", Cmd),
            ["zoomIn"] = Key("+", Cmd),
            ["zoomOut"] = Key("-", Cmd),
            ["actualSize"] = Key("0", Cmd),
            ["copyPageLink"] = Key("c", Cmd | Shift),
            ["copyPageLinkAsMarkdown"] = Key("c", Cmd | Opt | Shift),
            ["printPage"] = Key("p", Cmd),
            ["toggleSidebar"] = Key("s", Cmd),
            ["showHistory"] = Key("y", Cmd),
            ["showDownloads"] = Key("j", Cmd | Shift),
            ["webInspectorInstructions"] = Key("i", Cmd | Opt),
            ["toggleDeveloperToolbar"] = Key("i", Cmd | Shift),
            ["toggleTranslationToolbar"] = Key("l", Cmd | Shift),
            // ⌃⌘←/→ is the one arrow pair left free: ⌥⌘←/→ switch Spaces and ⌥⌘↑/↓
            // tabs. Splitting a single card stays menu-only because Arc's ⌘⇧+ collides
            // with zoom and ⌘W already closes the focused card.
            ["focusNextSplitCard"] = Special("rightArrow", Ctrl | Cmd),
            ["focusPreviousSplitCard"] = Special("leftArrow", Ctrl | Cmd),
            ["separateSplitTabs"] = Key("u", Cmd | Opt),
            // ⇧⌘←/→ shadows extend-selection only while a split is on screen; the
            // menu items carrying it are disabled otherwise.
            ["moveSplitCardLeft"] = Special("leftArrow", Cmd | Shift),
            ["moveSplitCardRight"] = Special("rightArrow", Cmd | Shift)
        };

    /// The Mac adds a blank window and moves the Quick Window one modifier up.
    private static readonly IReadOnlyDictionary<string, ShortcutChord> Desktop =
        new Dictionary<string, ShortcutChord>(StringComparer.Ordinal) {
            [NewBlankWindow] = Key("n", Cmd | Opt),
            [NewQuickWindow] = Key("n", Cmd | Opt | Shift)
        };

    #endregion

    #region Actions - Catalog

    public static ShortcutChord? Default(string command, DevicePlatform platform) {
        ArgumentNullException.ThrowIfNull(command);
        if (platform == DevicePlatform.Desktop && Desktop.TryGetValue(command, out var desktop)) return desktop;
        if (NumberedIndex(TabSelectionCommands, command) is { } tab) return Key((tab + 1).ToString(CultureInfo.InvariantCulture), Cmd);
        if (NumberedIndex(SpaceSelectionCommands, command) is { } space) return Key((space + 1).ToString(CultureInfo.InvariantCulture), Ctrl);
        return Shared.GetValueOrDefault(command);
    }

    /// The zero-based position of a numbered command in its family.
    public static int? NumberedIndex(IReadOnlyList<string> family, string command) {
        ArgumentNullException.ThrowIfNull(family);
        for (int index = 0; index < family.Count; index++)
            if (family[index] == command) return index;
        return null;
    }

    private static ShortcutChord Key(string character, int modifiers) => ShortcutChord.Character(character, modifiers);

    private static ShortcutChord Special(string key, int modifiers) => ShortcutChord.Special(key, modifiers);

    #endregion
}
