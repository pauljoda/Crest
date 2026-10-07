using System.Globalization;
using System.Text;

using CrestCore.Contracts;

namespace CrestCore.Domain;

/// A window's command palette over the Space it shows: what it offers for
/// typed text, ranked in sections. It reads only immutable records, so it
/// answers without holding the core's lock. `Space` is null when the window
/// shows no Space the palette may read, as a locked one; the palette then
/// offers only the address or search and the commands.
public sealed class Palette {
    #region Static Variables

    /// The newest history entries a query ranks.
    private const int HistoryScan = 1_500;
    /// The matching history entries a query ranks before it stops looking.
    private const int HistoryCandidates = 40;
    /// A folder ranks below a tab that matches as well.
    private const int FolderPenalty = 50;
    private const int MaximumHistoryRecencyBonus = 120;
    private const int HistoryRecencyDecayInterval = 8;
    private const int MaximumHistoryRepetitionBonus = 60;
    private const int HistoryVisitBonus = 4;
    /// The longest text the palette asks suggestions for or offers as one.
    private const int MaximumSuggestionLength = 256;

    #endregion

    #region Variables

    private readonly SpaceState? space;
    private readonly Guid? shownTabId;
    private readonly bool isPrivate;
    private readonly bool allowsInternalPages;
    private readonly SearchPreferences search;

    #endregion

    #region Constructors

    /// The palette of a window that shows `space`, or none the palette may
    /// read, and `shownTabId` there, in a private workspace or not, whose
    /// default engine opens internal pages or not.
    public Palette(SpaceState? space, Guid? shownTabId, bool isPrivate, bool allowsInternalPages) {
        this.space = space;
        this.shownTabId = shownTabId;
        this.isPrivate = isPrivate;
        this.allowsInternalPages = allowsInternalPages;
        search = space is null ? SearchPreferences.Default : SearchPreferences.Restore(space.Settings.BrowsingPreferences);
    }

    #endregion

    #region Actions - Answering

    /// What the palette offers for `text`, with `commands` among its actions
    /// and `remote` as the search suggestions fetched for the same text.
    public PaletteAnswer Answer(string text, IReadOnlyList<PaletteCommand> commands, IReadOnlyList<string> remote) {
        ArgumentNullException.ThrowIfNull(text);
        ArgumentNullException.ThrowIfNull(commands);
        ArgumentNullException.ThrowIfNull(remote);
        var query = new PaletteQuery(text);
        var intent = Intent(query);
        List<PaletteGroup> groups = [];
        void Add(PaletteSection section, IReadOnlyList<PaletteRow> rows) {
            if (rows.Count > 0) groups.Add(new(section, rows));
        }
        if (intent is not null) Add(PaletteSection.Intent, [intent]);
        var tabs = Tabs(query);
        List<PaletteRow> local = [.. tabs.Rows];
        var actions = Actions(query, commands);
        var saved = Saved(query);
        var history = History(query, intent);
        local.AddRange(actions);
        local.AddRange(saved);
        local.AddRange(history);
        Add(PaletteSection.SearchSuggestions, Suggestions(text, remote, intent, local));
        Add(tabs.Section, tabs.Rows);
        Add(PaletteSection.Actions, actions);
        Add(PaletteSection.Saved, saved);
        Add(PaletteSection.History, history);
        return new(groups, Completion(text), SuggestionAddress(text));
    }

    #endregion

    #region Actions - Intent

    /// The address the text opens, or the search it runs with the Space's
    /// engine; null when nothing was typed or the text names nothing loadable.
    private PaletteRow? Intent(PaletteQuery query) {
        if (query.IsEmpty) return null;
        AddressResolution? resolution;
        try {
            resolution = AddressResolution.Resolve(query.Text, search.Selected, allowsInternalPages);
        } catch (BrowserRuleException) {
            return null;
        }
        if (resolution is null || !Uri.TryCreate(resolution.Url, UriKind.Absolute, out var url)) return null;
        if (resolution.SearchQuery is { } searched)
            return Searching(PaletteRowKind.Search, $"Search with {search.Selected.Title}", searched, resolution.Url);
        string host = url.Host.Length > 0 ? url.Host.Replace("www.", "", StringComparison.Ordinal) : resolution.Url;
        return new(PaletteRowKind.OpenAddress, $"Open {host}", resolution.Url, PaletteRowKind.OpenAddress.Symbol, SubjectId: null,
            TabId: null, resolution.Url, Command: null, Engine: null, CustomEngineId: null);
    }

    private PaletteRow Searching(PaletteRowKind kind, string title, string subtitle, string address) => new(kind, title, subtitle,
        kind.Symbol, SubjectId: null, TabId: null, address, Command: null, BuiltInSearchEngine.Named(search.Selected.Name),
        search.Selected.Identity());

    #endregion

    #region Actions - Tabs

    /// The Space's open tabs other than the one shown: before anything is
    /// typed the first few, and then the current tabs that match.
    private (PaletteSection Section, IReadOnlyList<PaletteRow> Rows) Tabs(PaletteQuery query) {
        if (space is null) return (PaletteSection.Tabs, []);
        var open = space.Tabs.Where(tab => tab.Id != shownTabId && !tab.IsStartPage);
        if (query.IsEmpty)
            return (PaletteSection.OpenTabs, [.. open.Take(PaletteSection.OpenTabs.Shows(resting: true)).Select(TabRow)]);
        var ranked = Ranked(open.Where(tab => !tab.Placement.IsDurable), PaletteSection.Tabs.Shows(resting: false),
            tab => query.Score(tab.DisplayTitle, tab.Url ?? ""));
        return (PaletteSection.Tabs, [.. ranked.Select(TabRow)]);
    }

    private static PaletteRow TabRow(TabState tab) => new(PaletteRowKind.Tab, tab.DisplayTitle, Host(tab.Url) ?? tab.Url ?? "",
        PaletteRowKind.Tab.Symbol, SubjectId: null, tab.Id, Address: null, Command: null, Engine: null, CustomEngineId: null);

    #endregion

    #region Actions - Commands

    /// Before anything is typed, the resting commands the platform offers;
    /// then the commands that match.
    private static IReadOnlyList<PaletteRow> Actions(PaletteQuery query, IReadOnlyList<PaletteCommand> commands) {
        var offered = commands.Where(command => command.Command.OffersInPalette).ToList();
        if (query.IsEmpty)
            return [.. offered.Where(command => command.Command.PaletteRest is not null).OrderBy(command => command.Command.PaletteRest)
                .Take(PaletteSection.Actions.Shows(resting: true)).Select(CommandRow)];
        return [.. Ranked(offered, PaletteSection.Actions.Shows(resting: false),
            command => query.Score(command.Title, command.SectionTitle)).Select(CommandRow)];
    }

    private static PaletteRow CommandRow(PaletteCommand command) => new(PaletteRowKind.Command, command.Title, command.SectionTitle,
        command.Command.Symbol, SubjectId: null, TabId: null, Address: null, command.Command, Engine: null, CustomEngineId: null);

    #endregion

    #region Actions - Saved

    /// The pinned and saved tabs, and the folders that hold some, that match.
    private IReadOnlyList<PaletteRow> Saved(PaletteQuery query) {
        if (query.IsEmpty || space is null) return [];
        var tabs = space.Tabs.Where(tab => tab.Placement.IsDurable).ToList();
        var tree = new FolderTree(space.Folders);
        var byFolder = tabs.Where(tab => tab.FolderId is not null).ToLookup(tab => tab.FolderId!.Value);
        List<(PaletteRow Row, int Score)> scored = [];
        foreach (var tab in tabs) {
            if (query.Score(tab.DisplayTitle, tab.SavedAddress ?? tab.Url ?? "") is not { } score) continue;
            var kind = tab.Placement.PaletteRow;
            scored.Add((new(kind, tab.DisplayTitle, SavedSubtitle(tab, tree), kind.Symbol, SubjectId: null, tab.Id, Address: null,
                Command: null, Engine: null, CustomEngineId: null), score));
        }
        foreach (var folder in tree.DisplayOrder()) {
            string path = tree.PathTitle(folder.Id);
            if (query.Score(folder.Title, path) is not { } score || byFolder[folder.Id].FirstOrDefault() is not { } first) continue;
            int count = byFolder[folder.Id].Count();
            scored.Add((new(PaletteRowKind.Folder, folder.Title, FolderSubtitle(count, path), folder.DisplaySymbol, folder.Id, first.Id,
                Address: null, Command: null, Engine: null, CustomEngineId: null), score - FolderPenalty));
        }
        return [.. scored.Select((entry, position) => (entry.Row, entry.Score, Position: position))
            .OrderByDescending(entry => entry.Score).ThenBy(entry => entry.Position)
            .Take(PaletteSection.Saved.Shows(resting: false)).Select(entry => entry.Row)];
    }

    /// Where a saved tab lives and the site it belongs to.
    private static string SavedSubtitle(TabState tab, FolderTree tree) {
        string host = Host(tab.SavedAddress) ?? Host(tab.Url) ?? "";
        if (tab.FolderId is not { } folderId) return host;
        string path = tree.PathTitle(folderId);
        return host.Length == 0 ? path : $"{path} · {host}";
    }

    private static string FolderSubtitle(int count, string path) {
        string tabs = count == 1 ? "1 tab" : $"{count} tabs";
        return path.Contains('›') ? $"{path} · {tabs}" : tabs;
    }

    #endregion

    #region Actions - History

    /// The newest history entries that match, other than the pages the
    /// Space's tabs show and the address the text opens.
    private IReadOnlyList<PaletteRow> History(PaletteQuery query, PaletteRow? intent) {
        if (query.IsEmpty || space is null || space.History.Count == 0) return [];
        var claimed = new HashSet<string>(StringComparer.Ordinal);
        foreach (var tab in space.Tabs) if (tab.Url is { } url) claimed.Add(Key(url));
        if (intent?.Address is { } opened) claimed.Add(Key(opened));
        List<(HistoryEntryState Entry, int Score, int Position)> candidates = [];
        int position = 0;
        foreach (var entry in space.History.Take(HistoryScan)) {
            int at = position++;
            if (claimed.Contains(Key(entry.Url)) || query.Score(entry.Title, entry.Url) is not { } score) continue;
            candidates.Add((entry, score + RecencyBonus(at, entry), at));
            if (candidates.Count >= HistoryCandidates) break;
        }
        return [.. candidates.OrderByDescending(candidate => candidate.Score).ThenBy(candidate => candidate.Position)
            .Take(PaletteSection.History.Shows(resting: false))
            .Select(candidate => new PaletteRow(PaletteRowKind.History,
                candidate.Entry.Title.Length > 0 ? candidate.Entry.Title : Host(candidate.Entry.Url) ?? candidate.Entry.Url,
                candidate.Entry.Url, PaletteRowKind.History.Symbol, candidate.Entry.Id, TabId: null, candidate.Entry.Url, Command: null,
                Engine: null, CustomEngineId: null))];
    }

    /// Newer entries and ones visited more often rank higher.
    private static int RecencyBonus(int position, HistoryEntryState entry) =>
        Math.Max(0, MaximumHistoryRecencyBonus - position / HistoryRecencyDecayInterval)
        + Math.Min(MaximumHistoryRepetitionBonus, entry.VisitCount * HistoryVisitBonus);

    /// The address as history keeps it, so a fragment never makes one page two.
    private static string Key(string url) => new WebAddress(url).Normalized ?? url;

    #endregion

    #region Actions - Suggestions

    /// The fetched suggestions the local rows and the typed text do not
    /// already say, each as a search with the Space's engine.
    private IReadOnlyList<PaletteRow> Suggestions(string text, IReadOnlyList<string> remote, PaletteRow? intent,
        IReadOnlyList<PaletteRow> local) {
        if (remote.Count == 0) return [];
        var claimed = new HashSet<string>(StringComparer.Ordinal) { Collapsed(text).ToLowerInvariant() };
        foreach (var row in intent is null ? local : local.Prepend(intent)) claimed.Add(Collapsed(row.Title).ToLowerInvariant());
        List<PaletteRow> rows = [];
        foreach (var fetched in remote) {
            if (rows.Count >= PaletteSection.SearchSuggestions.Shows(resting: false)) break;
            string suggestion = Collapsed(fetched);
            if (suggestion.Length == 0 || suggestion.Length > MaximumSuggestionLength || !claimed.Add(Folded(suggestion))) continue;
            rows.Add(Searching(PaletteRowKind.SearchSuggestion, suggestion, $"Search with {search.Selected.Title}",
                search.Selected.Search(suggestion)));
        }
        return rows;
    }

    /// Where to fetch suggestions for `text`, or null when this palette asks
    /// for none.
    private string? SuggestionAddress(string text) {
        string trimmed = text.Trim();
        if (trimmed.Length == 0 || trimmed.Length > MaximumSuggestionLength || isPrivate || space is null || !search.SuggestionsEnabled)
            return null;
        return search.Selected.Suggest(text);
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

    /// The address the Space knows that best completes `text`: from its open
    /// tabs, its pinned and saved tabs and the addresses they belong to, and
    /// its history. Null when none does, or when one it knows is exactly what
    /// was typed.
    private AddressCompletion? Completion(string text) {
        if (space is null || TypedAddress.Of(text) is not { } typed) return null;
        AddressMatch? best = null;
        foreach (var candidate in CompletionCandidates()) {
            if (candidate.Completing(typed) is not { } match) continue;
            if (string.Equals(match.Text.ToLowerInvariant(), typed.Lowercased, StringComparison.Ordinal)) return null;
            if (best is null || match.Outranks(best)) best = match;
        }
        if (best is null || best.Text.Length <= typed.Text.Length) return null;
        string suffix = best.Text[typed.Text.Length..];
        string completed = text + suffix;
        string accepted = text.Contains("://", StringComparison.Ordinal) || best.Candidate.Scheme == "https"
            ? completed : $"{best.Candidate.Scheme}://{completed}";
        return new(text, suffix, accepted);
    }

    private IEnumerable<AddressCandidate> CompletionCandidates() {
        foreach (var tab in space!.Tabs.Where(tab => !tab.IsStartPage)) {
            int source = tab.Placement.IsDurable ? AddressCandidate.SavedTabSource : AddressCandidate.OpenTabSource;
            if (tab.Url is { } url && AddressCandidate.Of(url, source, tab.LastActivatedAt, visits: 0) is { } shown) yield return shown;
            if (tab.SavedAddress is { } saved
                && AddressCandidate.Of(saved, AddressCandidate.SavedTabSource, tab.LastActivatedAt, visits: 0) is { } kept)
                yield return kept;
        }
        foreach (var candidate in AddressIndex.Of(space.History).Candidates()) yield return candidate;
    }

    #endregion

    #region Actions - Support

    /// The host `url` names, or null for none.
    private static string? Host(string? url) =>
        url is not null && Uri.TryCreate(url, UriKind.Absolute, out var parsed) && parsed.Host.Length > 0 ? parsed.Host : null;

    /// The first `limit` of `elements` that `score` scores, best first, in
    /// their own order where scores tie.
    private static IEnumerable<T> Ranked<T>(IEnumerable<T> elements, int limit, Func<T, int?> score) =>
        elements.Select((element, position) => (Element: element, Score: score(element), Position: position))
            .Where(entry => entry.Score is not null)
            .OrderByDescending(entry => entry.Score).ThenBy(entry => entry.Position)
            .Take(limit).Select(entry => entry.Element);

    #endregion
}
