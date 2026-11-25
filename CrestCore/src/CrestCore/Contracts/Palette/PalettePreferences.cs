using CrestCore.Domain;

namespace CrestCore.Contracts;

#region Types

/// One kind of result, whether the palette offers it, and the most rows it
/// shows, or null for the kind's own number. In `PalettePreferences.Sources`
/// the order of the kinds that are sections is the order the palette shows
/// them.
public sealed record PaletteSourceChoice(PaletteSource Source, bool IsEnabled, int? Limit);

#endregion

/// How the command palette ranks and arranges what it offers, which this
/// device keeps among its app-wide preferences and never syncs: whether rows
/// stay under a header for their kind or blend into one ranked list, which
/// kinds it offers, in what order and how many rows each shows, whether one
/// best row leads, whether an open tab outranks history for the same site,
/// whether it completes addresses inline, learns from the rows a person picks,
/// searches a site when Tab follows its shortcut, says why a row is there, and
/// whether a site the person knows leads one typed word ahead of the search.
public sealed record PalettePreferences(PaletteLayout Layout, IReadOnlyList<PaletteSourceChoice> Sources, bool ShowsTopHit,
    bool PrefersOpenTabs, bool CompletesInline, bool LearnsChoices, bool SearchesSitesWithTab, bool ShowsReasons,
    SearchProviderSpaceTrigger ProviderSpaceTrigger, bool PrefersSitesOverSearch) {
    #region Static Variables

    /// The most rows a person may have one kind show.
    public const int MaximumLimit = 50;

    /// The numbers of rows Settings offers a section.
    public static IReadOnlyList<int> OfferedLimits { get; } = [.. Enumerable.Range(1, 10), 15, 20];

    /// What a person who never chose sees: every kind in its default order,
    /// each on or off as `PaletteSource.IsEnabledByDefault` says.
    public static PalettePreferences Default { get; } = new(PaletteLayout.Sections,
        [.. PaletteSource.All.Select(source => new PaletteSourceChoice(source, source.IsEnabledByDefault, Limit: null))], ShowsTopHit: true, PrefersOpenTabs: true, CompletesInline: true, LearnsChoices: true, SearchesSitesWithTab: true,
        ShowsReasons: false, ProviderSpaceTrigger: SearchProviderSpaceTrigger.PrefixedShortcut, PrefersSitesOverSearch: false);

    #endregion

    #region Variables

    /// Collections are owned when constructed or replaced on a copy.
    public IReadOnlyList<PaletteSourceChoice> Sources {
        get;
        init => field = [.. value];
    } = [.. Sources];

    #endregion

    #region Actions - Reading

    /// Whether the palette offers results of `source`.
    public bool Offers(PaletteSource source) => Sources.FirstOrDefault(choice => choice.Source == source)?.IsEnabled ?? false;

    /// The kinds the palette shows as sections, in the person's order, on or off.
    public IEnumerable<PaletteSource> OrderedSections => Sources.Select(choice => choice.Source).Where(source => source.IsSection);

    /// The most rows `source` shows: the person's number, else the kind's own.
    public int Limit(PaletteSource source) =>
        Sources.FirstOrDefault(choice => choice.Source == source)?.Limit ?? source.DefaultLimit;

    /// The kinds the person places among the sections, in their order (see
    /// `PaletteSource.IsArranged`).
    public IReadOnlyList<PaletteSourceChoice> Sections => [.. Sources.Where(choice => choice.Source.IsArranged)];

    #endregion

    #region Actions - Editing

    /// These preferences with `source` offered or not.
    public PalettePreferences Offering(PaletteSource source, bool isEnabled) => Editing(source, choice => choice with { IsEnabled = isEnabled });

    /// These preferences with `source` showing at most `limit` rows, or its
    /// own number when `limit` is that number.
    public PalettePreferences Limiting(PaletteSource source, int limit) =>
        Editing(source, choice => choice with { Limit = limit == source.DefaultLimit ? null : limit });

    /// These preferences with the section `source` standing at `index` among
    /// the sections, as a drag or a move command leaves it. A kind that is no
    /// section stays where it is.
    public PalettePreferences MovingSection(PaletteSource source, int index) {
        var ordered = Sections.ToList();
        int from = ordered.FindIndex(choice => choice.Source == source);
        if (from < 0) return this;
        var moving = ordered[from];
        ordered.RemoveAt(from);
        ordered.Insert(Math.Clamp(index, 0, ordered.Count), moving);
        return this with { Sources = [.. ordered, .. Sources.Where(choice => ordered.All(section => section.Source != choice.Source))] };
    }

    /// These preferences with the sections in their default order, each kept
    /// on or off as the person set it.
    public PalettePreferences RestoringSectionOrder() {
        IReadOnlyList<PaletteSourceChoice> ordered = [.. Default.Sections.Select(section =>
            Sources.FirstOrDefault(choice => choice.Source == section.Source) ?? section)];
        return this with { Sources = [.. ordered, .. Sources.Where(choice => ordered.All(section => section.Source != choice.Source))] };
    }

    private PalettePreferences Editing(PaletteSource source, Func<PaletteSourceChoice, PaletteSourceChoice> edit) =>
        this with { Sources = [.. Sources.Select(choice => choice.Source == source ? edit(choice) : choice)] };

    #endregion

    #region Actions - Restoring

    /// These preferences with every kind named exactly once: a kind repeated
    /// keeps its first place, a number of rows outside one to `MaximumLimit`
    /// goes back to the kind's own, and a kind they never named, such as one a
    /// later release added, joins after the others with its default.
    public PalettePreferences Restored() {
        List<PaletteSourceChoice> restored = [];
        foreach (var choice in Sources)
            if (restored.All(kept => kept.Source != choice.Source))
                restored.Add(choice.Limit is > 0 and <= MaximumLimit ? choice : choice with { Limit = null });
        foreach (var source in PaletteSource.All)
            if (restored.All(kept => kept.Source != source)) restored.Add(new(source, source.IsEnabledByDefault, Limit: null));
        return this with { Sources = restored };
    }

    #endregion

    #region Actions - Equality

    public bool Equals(PalettePreferences? other) => other is not null
        && Layout == other.Layout
        && Sources.SequenceEqual(other.Sources)
        && ShowsTopHit == other.ShowsTopHit
        && PrefersOpenTabs == other.PrefersOpenTabs
        && CompletesInline == other.CompletesInline
        && LearnsChoices == other.LearnsChoices
        && SearchesSitesWithTab == other.SearchesSitesWithTab
        && ProviderSpaceTrigger == other.ProviderSpaceTrigger
        && ShowsReasons == other.ShowsReasons
        && PrefersSitesOverSearch == other.PrefersSitesOverSearch;

    public override int GetHashCode() =>
        HashCode.Combine(
            HashCode.Combine(Layout, Sources.Count, ShowsTopHit, PrefersOpenTabs, CompletesInline, LearnsChoices, SearchesSitesWithTab, ShowsReasons),
            ProviderSpaceTrigger, PrefersSitesOverSearch);

    #endregion
}
