namespace CrestCore.Contracts;

/// How much Crest blocks, on every page in every Space. Off blocks nothing.
/// Balanced subscribes to the lists that block ads and trackers while keeping
/// sites working. Strict adds the lists that also hide cookie notices and other
/// annoyances, and AdGuard's own ad list, at a greater risk of breaking a site.
/// Choosing a level sets every catalog list to what that level turns on; the
/// person may then turn single lists on or off.
///
/// The device store spells a level as its `Name`, so a name never changes. A
/// level travels as its index in `All`, so `All` is append-only.
public sealed class ContentBlockingLevel {
    #region Static Variables

    public static readonly ContentBlockingLevel Off = new(name: "off", title: "Off",
        summary: "Crest doesn’t block ads or trackers.", blocksContent: false, includesStrictLists: false);
    public static readonly ContentBlockingLevel Balanced = new(name: "balanced", title: "Balanced",
        summary: "Blocks ads and trackers while keeping sites working.", blocksContent: true, includesStrictLists: false);
    public static readonly ContentBlockingLevel Strict = new(name: "strict", title: "Strict",
        summary: "Also hides cookie notices and other annoyances. A few sites may not work.", blocksContent: true,
        includesStrictLists: true);

    public static IReadOnlyList<ContentBlockingLevel> All { get; } = [Off, Balanced, Strict];

    #endregion

    #region Variables

    public string Name { get; }

    /// What the settings call the level.
    [Localized]
    public string Title { get; }

    /// What the level does, in one sentence the settings show beneath it.
    [Localized]
    public string Summary { get; }

    /// The level blocks anything at all.
    public bool BlocksContent { get; }

    /// The level turns on the lists only Strict turns on.
    public bool IncludesStrictLists { get; }

    #endregion

    #region Constructors

    private ContentBlockingLevel(string name, string title, string summary, bool blocksContent, bool includesStrictLists) {
        Name = name;
        Title = title;
        Summary = summary;
        BlocksContent = blocksContent;
        IncludesStrictLists = includesStrictLists;
    }

    #endregion

    #region Actions - Lookup

    public static ContentBlockingLevel? Named(string? name) => All.FirstOrDefault(level => level.Name == name);

    #endregion
}
