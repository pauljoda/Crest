using System.Globalization;
using System.Text;

using CrestCore.Contracts;

namespace CrestCore.Domain;

/// A Space's search choice and its custom engines.
public sealed class SearchPreferences {
    #region Variables

    public const int MaximumCustomProviders = 32;

    public static SearchPreferences Default { get; } = new(SearchProvider.Google.Name, [], false);
    public string SelectedId { get; }
    public IReadOnlyList<SearchProvider> CustomProviders { get; }
    public bool SuggestionsEnabled { get; }
    public IEnumerable<SearchProvider> Providers => SearchProvider.All.Concat(CustomProviders);
    public SearchProvider Selected => Providers.Single(p => p.Name == SelectedId);

    #endregion

    #region Constructors

    private SearchPreferences(string selected, IReadOnlyList<SearchProvider> custom, bool suggestions) { SelectedId = selected; CustomProviders = custom; SuggestionsEnabled = suggestions; }

    #endregion

    #region Actions - Search providers

    /// Restores stored preferences: the first provider for each identity, at
    /// most the custom limit, and Google when the selection is not available.
    public static SearchPreferences Restore(string? selected, IEnumerable<SearchProvider> custom, bool suggestions) {
        var providers = custom.GroupBy(p => p.Name).Select(g => g.First()).Take(MaximumCustomProviders).ToArray();
        if (!SearchProvider.All.Concat(providers).Any(p => p.Name == selected)) selected = SearchProvider.Google.Name;
        return new(selected!, Array.AsReadOnly(providers), suggestions);
    }

    /// A Space's stored search choice. Stored custom engines that no longer
    /// validate are left out, as the selection that named one falls back to Google.
    public static SearchPreferences Restore(BrowsingPreferences browsing) {
        ArgumentNullException.ThrowIfNull(browsing);
        var providers = new List<SearchProvider>();
        foreach (var custom in browsing.CustomSearchProviders) {
            try {
                providers.Add(Custom(custom.Id, custom.Name, custom.SearchUrlTemplate, custom.SuggestionUrlTemplate));
            } catch (BrowserRuleException) {
                // Excluded, never run.
            }
        }
        return Restore(browsing.SelectedSearchProviderId, providers, browsing.SearchSuggestionsEnabled);
    }

    /// The Space's browsing preferences carrying this search choice.
    public BrowsingPreferences Applied(BrowsingPreferences browsing) => browsing with {
        SelectedSearchProviderId = SelectedId,
        CustomSearchProviders = CustomProviders.Select(provider => new CustomSearchProvider(
            Guid.Parse(provider.Name[SearchProvider.CustomPrefix.Length..]), provider.Title, provider.SearchTemplate,
            provider.SuggestionTemplate)).ToArray(),
        SearchSuggestionsEnabled = SuggestionsEnabled
    };

    /// `SearchProvider.Admit` for session commands and stored preferences,
    /// which report a flaw as its rule code.
    public static SearchProvider Custom(Guid id, string name, string search, string? suggestions) {
        try {
            return SearchProvider.Admit(id, name, search, suggestions);
        } catch (Rejected rejected) {
            throw new BrowserRuleException(BrowserRuleCodes.SearchEngine(rejected.Rejection));
        }
    }

    /// Refuses an already validated custom engine whose title another custom
    /// engine uses (ignoring case and diacritics), or that would exceed the
    /// limit. `existing` holds each custom engine's name and title. Throws
    /// `Rejected` naming the rule.
    public static void Admit(SearchProvider provider, IReadOnlyCollection<(string Name, string Title)> existing) {
        ArgumentNullException.ThrowIfNull(provider);
        ArgumentNullException.ThrowIfNull(existing);
        if (!provider.IsCustom()) throw new Rejected(new InvalidSearchEngine(SearchEngineFlaw.InvalidIdentity));
        string title = Fold(provider.Title);
        if (existing.Any(p => p.Name != provider.Name && Fold(p.Title) == title)) throw new Rejected(new DuplicateSearchEngineName());
        if (existing.All(p => p.Name != provider.Name) && existing.Count >= MaximumCustomProviders)
            throw new Rejected(new SearchEngineLimitReached(MaximumCustomProviders));
    }

    /// `Admit` for session commands, which report the rule as its code.
    public static void RequireAdmissible(SearchProvider provider, IReadOnlyCollection<(string Name, string Title)> existing) {
        try {
            Admit(provider, existing);
        } catch (Rejected rejected) {
            throw new BrowserRuleException(BrowserRuleCodes.SearchEngine(rejected.Rejection));
        }
    }

    private static string Fold(string value) => string.Concat(value.Trim().Normalize(NormalizationForm.FormD)
        .Where(c => CharUnicodeInfo.GetUnicodeCategory(c) != UnicodeCategory.NonSpacingMark)).ToUpperInvariant();

    #endregion

    #region Mutators

    public SearchPreferences Select(string id, bool suggestions) {
        if (!Providers.Any(p => p.Name == id)) throw new BrowserRuleException(BrowserRuleCodes.UnknownSearchProvider);
        return new(id, CustomProviders, suggestions);
    }

    /// Adds or replaces a custom engine by identity, keeping its position.
    public SearchPreferences Upsert(SearchProvider provider) {
        ArgumentNullException.ThrowIfNull(provider);
        if (!provider.IsCustom() || !Guid.TryParseExact(provider.Name[SearchProvider.CustomPrefix.Length..], "D", out var id))
            throw new BrowserRuleException(BrowserRuleCodes.InvalidSearchProvider);
        var validated = Custom(id, provider.Title, provider.SearchTemplate, provider.SuggestionTemplate);
        RequireAdmissible(validated, CustomProviders.Select(p => (p.Name, p.Title)).ToArray());
        var values = CustomProviders.ToList(); int index = values.FindIndex(p => p.Name == validated.Name);
        if (index < 0) values.Add(validated); else values[index] = validated;
        return new(SelectedId, values.AsReadOnly(), SuggestionsEnabled);
    }

    /// Removes a custom engine; removing the selected one selects Google.
    public SearchPreferences Remove(Guid id) {
        string key = SearchProvider.CustomId(id);
        return new(SelectedId == key ? SearchProvider.Google.Name : SelectedId,
            CustomProviders.Where(p => p.Name != key).ToList().AsReadOnly(), SuggestionsEnabled);
    }

    public string Resolve(string input, bool allowsInternalPages) {
        var value = input.Trim();
        var resolution = value == BrowserUrlConstants.AboutBlank ? new AddressResolution(value, null)
            : AddressResolution.Resolve(input, Selected, allowsInternalPages)
                ?? throw new BrowserRuleException(BrowserRuleCodes.InvalidAddress);
        string address = resolution.Url;
        if (resolution.SearchQuery is null && Uri.TryCreate(address, UriKind.Absolute, out var uri)
            && (uri.Scheme == Uri.UriSchemeHttp || uri.Scheme == Uri.UriSchemeHttps)) address = uri.AbsoluteUri;
        BrowserSpace.ValidateUrl(address, allowsInternalPages);
        return address;
    }

    #endregion
}
