using CrestCore.Domain;

namespace CrestCore.Contracts;

/// A kind of result the palette may offer, which a person turns on or off,
/// and which finds and scores its own rows through its finders, one for each
/// kind of row it offers. A kind that is a section shows its rows under its
/// own header, in the order the person set; the others join `Section` or,
/// with none, lead the list. Before anything is typed only the kinds with a `RestingSection`
/// show, in that same order, so the first of them holds the row Return runs.
/// The stored preferences spell a kind as its `Name`, so a name never
/// changes. A kind travels as its index in `All`, so `All` is append-only.
public sealed class PaletteSource {
    #region Static Variables

    public static readonly PaletteSource RecentTabs = new(name: "recentTabs", title: "Recent Tabs", detail: null, section: PaletteSection.RecentTabs,
        isSection: true, isEnabledByDefault: true, restingSection: PaletteSection.RecentTabs, finders: [new RecentTabFinder()]);
    public static readonly PaletteSource OpenTabs = new(name: "openTabs", title: "Open Tabs", detail: null, section: PaletteSection.Tabs,
        isSection: true, isEnabledByDefault: true, restingSection: null, finders: [new OpenTabFinder()]);
    public static readonly PaletteSource Saved = new(name: "saved", title: "Pinned & Saved", detail: null, section: PaletteSection.Saved,
        isSection: true, isEnabledByDefault: true, restingSection: null, finders: [new SavedTabFinder(), new FolderFinder()]);
    public static readonly PaletteSource History = new(name: "history", title: "History", detail: null, section: PaletteSection.History,
        isSection: true, isEnabledByDefault: true, restingSection: null, finders: [new HistoryFinder()]);
    public static readonly PaletteSource Actions = new(name: "actions", title: "Actions", detail: null, section: PaletteSection.Actions,
        isSection: true, isEnabledByDefault: true, restingSection: PaletteSection.Actions, finders: [new CommandFinder()]);
    public static readonly PaletteSource Spaces = new(name: "spaces", title: "Spaces", detail: null, section: PaletteSection.Spaces,
        isSection: true, isEnabledByDefault: true, restingSection: null, finders: [new SpaceFinder()]);
    public static readonly PaletteSource ArchivedTabs = new(name: "archivedTabs", title: "Archived Tabs", detail: null,
        section: PaletteSection.Archived, isSection: true, isEnabledByDefault: false, restingSection: null, finders: [new ArchiveFinder()]);
    public static readonly PaletteSource Suggestions = new(name: "suggestions", title: "Search Suggestions", detail: null,
        section: PaletteSection.SearchSuggestions, isSection: true, isEnabledByDefault: true, restingSection: null, finders: []);
    public static readonly PaletteSource SettingsPages = new(name: "settingsPages", title: "Settings Pages", detail: "Finds Settings pages by name.",
        section: PaletteSection.Actions, isSection: false, isEnabledByDefault: true, restingSection: null, finders: [new SettingsPageFinder()]);
    public static readonly PaletteSource Scopes = new(name: "scopes", title: "@ Filters", detail: "Type @tabs, @saved, @history, @actions or @spaces, then a space or Tab, to show only that kind.", section: PaletteSection.Intent,
        isSection: false, isEnabledByDefault: true, restingSection: null, finders: [new ScopeFinder()]);
    public static readonly PaletteSource Calculator = new(name: "calculator", title: "Calculator", detail: "Answers arithmetic such as 24 * 7. Return copies the answer.", section: PaletteSection.TopHit,
        isSection: false, isEnabledByDefault: true, restingSection: null, finders: []);
    public static readonly PaletteSource PasteAndGo = new(name: "pasteAndGo", title: "Paste and Go", detail: "Offers the address you copied when the palette opens.", section: PaletteSection.Intent,
        isSection: false, isEnabledByDefault: false, restingSection: null, finders: [new PasteFinder()]);

    /// The kinds, sections first in their default order.
    public static IReadOnlyList<PaletteSource> All { get; } =
        [RecentTabs, OpenTabs, Saved, History, Actions, Spaces, ArchivedTabs, Suggestions, SettingsPages, Scopes, Calculator, PasteAndGo];

    #endregion

    #region Variables

    public string Name { get; }

    /// What the settings call the kind.
    [Localized]
    public string Title { get; }

    /// What the settings say the kind does, where its title alone does not.
    [Localized]
    public string? Detail { get; }

    /// Where the kind's rows go when the palette shows sections.
    public PaletteSection Section { get; }

    /// The kind shows its rows under its own header, in the order the person set.
    public bool IsSection { get; }

    /// Whether the palette offers the kind for a person who never chose.
    public bool IsEnabledByDefault { get; }

    /// Where the kind's rows go before anything is typed, or null when it
    /// offers none then.
    public PaletteSection? RestingSection { get; }

    /// The most rows the kind shows unless the person chose a number: its
    /// section's, or before anything is typed for a kind that only shows then.
    public int DefaultLimit => Section.Limit > 0 ? Section.Limit : Section.RestingLimit;

    /// Whether the person places the kind among the sections: every section
    /// but search suggestions, which always come last and which the search
    /// engine settings turn on or off.
    public bool IsArranged => IsSection && this != Suggestions;

    /// How the kind finds and scores its rows, each finder a kind of row it offers.
    private readonly IReadOnlyList<PaletteFinder> finders;

    #endregion

    #region Constructors

    private PaletteSource(string name, string title, string? detail, PaletteSection section, bool isSection, bool isEnabledByDefault,
        PaletteSection? restingSection, IReadOnlyList<PaletteFinder> finders) {
        Name = name;
        Title = title;
        Detail = detail;
        Section = section;
        IsSection = isSection;
        IsEnabledByDefault = isEnabledByDefault;
        RestingSection = restingSection;
        this.finders = finders;
    }

    #endregion

    #region Actions - Lookup

    public static PaletteSource? Named(string? name) => All.FirstOrDefault(source => source.Name == name);

    #endregion

    #region Actions - Offering

    /// The rows the kind offers for `query`, every one when the person
    /// narrowed the palette to it and typed nothing.
    internal IEnumerable<PaletteCandidate> Candidates(PaletteContext context, PaletteQuery query, PaletteSuggestions question, bool narrowed) =>
        finders.SelectMany(finder => finder.Find(context, this, query, question, narrowed));

    /// The rows the kind offers before anything is typed.
    internal IReadOnlyList<PaletteRow> RestingRows(PaletteContext context, PaletteSuggestions question) =>
        [.. finders.SelectMany(finder => finder.Resting(context, question))];

    /// The rows the kind adds beside the address or search typed text runs.
    internal IEnumerable<PaletteRow> Offers(PaletteContext context, PaletteQuery query, PaletteSuggestions question) =>
        finders.SelectMany(finder => finder.Offers(context, query, question));

    /// The rows the kind adds before anything is typed, above every section.
    internal IEnumerable<PaletteRow> RestingOffers(PaletteContext context, PaletteSuggestions question) =>
        finders.SelectMany(finder => finder.RestingOffers(context, question));

    #endregion
}
