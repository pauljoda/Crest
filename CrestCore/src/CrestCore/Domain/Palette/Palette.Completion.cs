using System.Globalization;
using System.Text;

using CrestCore.Contracts;

namespace CrestCore.Domain;

/// The address or search the text itself runs, the search suggestions that
/// join it, and the address that completes it inline.
public sealed partial class Palette {
    #region Actions - Intent

    /// The address the text opens, or the search it runs with the Space's
    /// engine; null when nothing was typed or the text names nothing loadable.
    /// An address the Space knows under another spelling, such as with
    /// `www.`, opens the way the Space knows it.
    private PaletteRow? Intent(PaletteQuery query) {
        if (query.IsEmpty) return null;
        AddressResolution? resolution;
        try {
            resolution = AddressResolution.Resolve(query.Text, context.Search, context.AllowsInternalPages);
        } catch (BrowserRuleException) {
            return null;
        }
        if (resolution is null || !Uri.TryCreate(resolution.Url, UriKind.Absolute, out var url)) return null;
        if (resolution.SearchQuery is { } searched)
            return Searching(PaletteRowKind.Search, context.Search.Kind.RowTitle(context.Search.Title), searched, resolution.Url,
                context.Search);
        string address = Known(resolution.Url) ?? resolution.Url;
        string host = url.Host.Length > 0 ? PaletteMemory.WithoutWww(url.Host) : resolution.Url;
        return PaletteRow.Of(PaletteRowKind.OpenAddress, $"Open {host}", address, address: address);
    }

    /// The address the Space knows for the same place as `url`: an open or
    /// kept tab's, else history's; null when it knows none.
    private string? Known(string url) {
        if (context.Space is not { } space || PaletteMemory.Place(url) is not { } place) return null;
        foreach (var tab in space.Tabs)
            if ((tab.SavedAddress ?? tab.Url) is { } known && PaletteMemory.Place(known) == place) return known;
        return space.History.Take(HistoryFinder.Scan).FirstOrDefault(entry => PaletteMemory.Place(entry.Url) == place)?.Url;
    }

    private static PaletteRow Searching(PaletteRowKind kind, string title, string subtitle, string address, SearchProvider provider) =>
        PaletteRow.Of(kind, title, subtitle, address: address, provider: provider);

    #endregion

    #region Actions - Suggestions

    /// The fetched suggestions the shown rows and the typed text do not
    /// already say, each as a search with `provider`.
    private IReadOnlyList<PaletteRow> Suggestions(string text, IReadOnlyList<string> remote, IReadOnlyList<PaletteRow> shown,
        SearchProvider provider) {
        if (remote.Count == 0) return [];
        var claimed = new HashSet<string>(StringComparer.Ordinal) { Folded(Collapsed(text)) };
        foreach (var row in shown) claimed.Add(Folded(Collapsed(row.Title)));
        List<PaletteRow> rows = [];
        foreach (var fetched in remote) {
            if (rows.Count >= Preferences.Limit(PaletteSource.Suggestions)) break;
            string suggestion = Collapsed(fetched);
            if (suggestion.Length == 0 || suggestion.Length > MaximumSuggestionLength || !claimed.Add(Folded(suggestion))) continue;
            rows.Add(Searching(PaletteRowKind.SearchSuggestion, suggestion, provider.Kind.RowTitle(provider.Title), provider.Search(suggestion),
                provider));
        }
        return rows;
    }

    /// Where to fetch suggestions for `text`, or null when this palette asks
    /// for none.
    private string? SuggestionAddress(string text) {
        string trimmed = text.Trim();
        if (trimmed.Length == 0 || trimmed.Length > MaximumSuggestionLength || context.IsPrivate || context.Space is null || !context.Suggests
            || !Preferences.Offers(PaletteSource.Suggestions))
            return null;
        return context.Search.Suggest(text);
    }

    /// Where to fetch the suggestions of `provider`, which the person entered,
    /// for `text`, or null when this palette asks for none.
    private string? ProviderSuggestionAddress(SearchProvider provider, string text) {
        string trimmed = text.Trim();
        if (trimmed.Length == 0 || trimmed.Length > MaximumSuggestionLength || context.IsPrivate || context.Space is null || !context.Suggests)
            return null;
        return provider.Suggest(text);
    }

    /// The words of `value`, one space apart.
    private static string Collapsed(string value) =>
        string.Join(' ', value.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries));

    /// `value` without case or diacritics.
    private static string Folded(string value) {
        var decomposed = value.Normalize(NormalizationForm.FormD);
        var builder = new StringBuilder(decomposed.Length);
        foreach (char character in decomposed)
            if (CharUnicodeInfo.GetUnicodeCategory(character) != UnicodeCategory.NonSpacingMark) builder.Append(character);
        return builder.ToString().Normalize(NormalizationForm.FormC).ToLowerInvariant();
    }

    #endregion

    #region Actions - Completion

    /// The address the Space knows that best completes the text, as other
    /// browsers complete it: the host whole, without a `www.` nobody typed,
    /// up to the next `/` once a path is typed, and only for places a person
    /// typed or picked within the lifetime, a tab shows or keeps, or history
    /// visited at least four times before the Space began remembering. Null
    /// when none does, when one is exactly what was typed, or when the field
    /// may not complete now.
    private AddressMatch? Completion(PaletteSuggestions question) {
        if (context.Space is null || !question.AllowsCompletion || !Preferences.CompletesInline
            || TypedAddress.Of(question.Text) is not { } typed)
            return null;
        AddressMatch? best = null;
        double Use(AddressCandidate candidate) {
            double remembered = context.Memory.Frecency(candidate.Url, null, context.Now);
            return remembered > 0 ? remembered
                : candidate.Visits * Math.Pow(2, -(context.Now - candidate.Date).TotalDays / PaletteMemory.HalfLifeDays);
        }
        foreach (var candidate in CompletionCandidates()) {
            if (!Completes(candidate) || candidate.Completing(typed) is not { } match) continue;
            if (string.Equals(match.Text, typed.Text, StringComparison.OrdinalIgnoreCase)) return null;
            if (best is null || match.Outranks(best, Use)) best = match;
        }
        return best is null || best.Text.Length <= typed.Text.Length ? null : best;
    }

    /// What accepting `match` leaves in the field: its text, with the scheme
    /// when the address is not https.
    private static string Accepted(AddressMatch match) =>
        match.Text.Contains("://", StringComparison.Ordinal) || match.Candidate.Scheme == "https"
            ? match.Text : $"{match.Candidate.Scheme}://{match.Text}";

    /// Whether `candidate` may complete inline: a tab's address always, and
    /// a history address the person typed or used heavily before memory began.
    private bool Completes(AddressCandidate candidate) {
        if (candidate.Source != AddressCandidate.HistorySource) return true;
        if (context.Memory.WasTyped(candidate.Authority, context.Now)) return true;
        return candidate.Visits >= 4 && candidate.FirstVisited is { } first && first < context.Memory.Since;
    }

    private IEnumerable<AddressCandidate> CompletionCandidates() {
        foreach (var tab in context.Space!.Tabs.Where(tab => !tab.IsStartPage)) {
            int source = tab.Placement.IsDurable ? AddressCandidate.SavedTabSource : AddressCandidate.OpenTabSource;
            if (tab.Url is { } url && AddressCandidate.Of(url, source, tab.LastActivatedAt, visits: 0) is { } shown) yield return shown;
            if (tab.SavedAddress is { } saved
                && AddressCandidate.Of(saved, AddressCandidate.SavedTabSource, tab.LastActivatedAt, visits: 0) is { } kept)
                yield return kept;
        }
        foreach (var candidate in context.History!.Candidates()) yield return candidate;
    }

    #endregion
}
