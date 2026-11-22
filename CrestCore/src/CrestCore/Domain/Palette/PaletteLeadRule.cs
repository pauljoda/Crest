using CrestCore.Contracts;

namespace CrestCore.Domain;

#region Types

/// What deciding the palette's best match reads for typed text: the query,
/// the address the field completes, the row the person picked before for the
/// same text, every row ranked, whether the field may complete now, which for
/// text that names no address it may only while that text is one word, and
/// whether the text names no address, so it searches unless a place leads.
internal sealed record PaletteLeading(PaletteQuery Query, AddressMatch? Completion, PaletteDestination? Habit,
    IReadOnlyList<PaletteCandidate> Ranked, bool Completes, bool Searches);

#endregion

/// One way a row comes to lead the palette as its best match, so Return runs
/// it. The rules are asked in order and the first that names a row leads:
/// a calculation, the address the field completes, what the person picked at
/// least twice for this text, then a strongly used place whose title or
/// address starts with the text. A word that names no address leads only
/// with a place it names: a site the field completes, as the tab that shows
/// it, or a tab whose title, or the site name its title ends with, starts
/// with it, never a page only history holds. While the field may not
/// complete, as for a phrase, a single letter, a word followed by a space,
/// or after the person deleted a completion, only a calculation leads, so
/// Return runs what they typed: its search, or the address it names.
internal sealed class PaletteLeadRule {
    #region Static Variables

    /// Arithmetic the text spells, whose answer Return copies.
    public static readonly PaletteLeadRule Calculation = new((context, leading) =>
        context.Preferences.Offers(PaletteSource.Calculator) && Domain.Calculation.Of(leading.Query.Text) is { } calculation
            ? new(PaletteRow.Of(PaletteRowKind.Calculation, calculation.Answer, $"{calculation.Expression} ="), PaletteSource.Calculator,
                int.MaxValue, Place: null, MayLead: true)
            : null);

    /// The address the field completes, as its open tab when the person
    /// prefers open tabs and one shows it. For a word that names no address,
    /// the person names the site, so the tab is the best one on that site.
    public static readonly PaletteLeadRule Completion = new((context, leading) => {
        if (!leading.Completes || leading.Completion is not { } completion) return null;
        string? place = PaletteMemory.Place(completion.Opens);
        string? site = place is null ? null : PaletteMemory.Site(place);
        bool Shows(PaletteCandidate entry) => entry.Place is { } shown
            && (leading.Searches ? PaletteMemory.Site(shown) == site : shown == place);
        if (context.Preferences.PrefersOpenTabs
            && leading.Ranked.Where(entry => entry.Row.TabId is not null && Shows(entry)).MaxBy(entry => entry.Score) is { } open)
            return open with { Row = open.Row with { Reason = PaletteReason.Completion } };
        string host = completion.Text.Contains("://", StringComparison.Ordinal) ? completion.Text : completion.Text.TrimEnd('/');
        return new(PaletteRow.Of(PaletteRowKind.OpenAddress, $"Open {host}", completion.Opens, address: completion.Opens,
            reason: PaletteReason.Completion), PaletteSource.History, int.MaxValue, place, MayLead: true);
    });

    /// The row the person picked at least twice for exactly this text.
    public static readonly PaletteLeadRule Habit = new((context, leading) =>
        leading.Completes && leading.Habit is { } habit && leading.Ranked.FirstOrDefault(entry => context.Destination(entry.Row) == habit)
            is { } learned
            ? learned with { Row = learned.Row with { Reason = PaletteReason.Learned } }
            : null);

    /// The strongest row that may lead, once two letters are typed and the
    /// person shows a Top Hit; for a word that names no address, only a tab,
    /// once three letters are typed.
    public static readonly PaletteLeadRule StrongPlace = new((context, leading) =>
        leading.Completes && context.Preferences.ShowsTopHit && leading.Query.Text.Length >= (leading.Searches ? 3 : 2)
            ? leading.Ranked.Where(entry => entry.MayLead && (!leading.Searches || entry.Row.TabId is not null)).MaxBy(entry => entry.Score)
            : null);

    /// The rules, in the order the palette asks them.
    public static IReadOnlyList<PaletteLeadRule> All { get; } = [Calculation, Completion, Habit, StrongPlace];

    #endregion

    #region Variables

    private readonly Func<PaletteContext, PaletteLeading, PaletteCandidate?> leads;

    #endregion

    #region Constructors

    private PaletteLeadRule(Func<PaletteContext, PaletteLeading, PaletteCandidate?> leads) => this.leads = leads;

    #endregion

    #region Actions - Leading

    /// The row this rule makes lead, or null when it names none.
    public PaletteCandidate? Leads(PaletteContext context, PaletteLeading leading) => leads(context, leading);

    /// The row the first rule that names one makes lead, or null when none does.
    public static PaletteCandidate? First(PaletteContext context, PaletteLeading leading) =>
        All.Select(rule => rule.Leads(context, leading)).FirstOrDefault(candidate => candidate is not null);

    #endregion
}
