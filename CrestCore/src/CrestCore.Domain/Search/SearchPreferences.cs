using System.Globalization;
using System.Text;

using CrestCore.Contracts;

namespace CrestCore.Domain;

/// A Space's search choice and its custom engines.
public sealed class SearchPreferences {
    #region Static Variables

    public const int MaximumCustomProviders = 32;

    public static SearchPreferences Default { get; } = new(SearchProvider.Google, [], false);

    #endregion

    #region Variables

    public SearchProvider Selected { get; }
    /// The selected engine's stored spelling.
    public string SelectedId => Selected.Name;
    public IReadOnlyList<SearchProvider> CustomProviders { get; }
    public bool SuggestionsEnabled { get; }
    public IEnumerable<SearchProvider> Providers => SearchProvider.All.Concat(CustomProviders);

    #endregion

    #region Constructors

    private SearchPreferences(SearchProvider selected, IReadOnlyList<SearchProvider> custom, bool suggestions) {
        Selected = selected;
        CustomProviders = custom;
        SuggestionsEnabled = suggestions;
    }

    #endregion

    #region Actions - Search providers

    /// Restores stored preferences: the first provider for each identity, at
    /// most the custom limit, and Google when the selection is not available.
    public static SearchPreferences Restore(string? selected, IEnumerable<SearchProvider> custom, bool suggestions) {
        var providers = custom.GroupBy(p => p.Name).Select(g => g.First()).Take(MaximumCustomProviders).ToArray();
        return new(SearchProvider.All.Concat(providers).FirstOrDefault(p => p.Name == selected) ?? SearchProvider.Google,
            Array.AsReadOnly(providers), suggestions);
    }

    /// A Space's stored search choice. Stored custom engines that no longer
    /// validate are left out, as the selection that named one falls back to Google.
    public static SearchPreferences Restore(BrowsingPreferences browsing) {
        ArgumentNullException.ThrowIfNull(browsing);
        var providers = new List<SearchProvider>();
        foreach (var stored in browsing.CustomSearchProviders) {
            try {
                providers.Add(SearchProvider.Admit(stored.Id, stored.Name, stored.SearchUrlTemplate, stored.SuggestionUrlTemplate));
            } catch (Rejected) {
                // Excluded, never run.
            }
        }
        var selected = browsing.SelectedCustomEngineId is { } custom ? SearchProvider.CustomId(custom)
            : (browsing.SelectedBuiltInEngine ?? BuiltInSearchEngine.Google).Name;
        return Restore(selected, providers, browsing.SearchSuggestionsEnabled);
    }

    /// The Space's browsing preferences carrying this search choice.
    public BrowsingPreferences Applied(BrowsingPreferences browsing) => browsing with {
        SelectedBuiltInEngine = BuiltInSearchEngine.Named(Selected.Name),
        SelectedCustomEngineId = Selected.Identity(),
        CustomSearchProviders = CustomProviders.Select(provider => new CustomSearchProvider(provider.Identity()!.Value, provider.Title,
            provider.SearchTemplate, provider.SuggestionTemplate)).ToArray(),
        SearchSuggestionsEnabled = SuggestionsEnabled
    };

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

    private static string Fold(string value) => string.Concat(value.Trim().Normalize(NormalizationForm.FormD)
        .Where(c => CharUnicodeInfo.GetUnicodeCategory(c) != UnicodeCategory.NonSpacingMark)).ToUpperInvariant();

    #endregion

    #region Mutators

    /// Searches with `provider`, a built-in or one of these custom engines.
    /// Throws `Rejected` with `UnknownSearchEngine` for any other.
    public SearchPreferences Select(SearchProvider provider) {
        ArgumentNullException.ThrowIfNull(provider);
        var known = Providers.FirstOrDefault(p => p.Name == provider.Name) ?? throw new Rejected(new UnknownSearchEngine(provider.Identity()));
        return new(known, CustomProviders, SuggestionsEnabled);
    }

    /// Searches with the custom engine `id`. Throws `Rejected` with
    /// `UnknownSearchEngine` when there is none.
    public SearchPreferences Select(Guid id) =>
        Select(CustomProviders.FirstOrDefault(p => p.Name == SearchProvider.CustomId(id)) ?? throw new Rejected(new UnknownSearchEngine(id)));

    /// Adds a validated custom engine after the others. Throws `Rejected`
    /// naming the rule it breaks; an engine with the identity of one already
    /// here is not a new one.
    public SearchPreferences Add(SearchProvider provider) {
        ArgumentNullException.ThrowIfNull(provider);
        if (CustomProviders.Any(p => p.Name == provider.Name))
            throw new Rejected(new InvalidSearchEngine(SearchEngineFlaw.InvalidIdentity));
        Admit(provider, CustomProviders.Select(p => (p.Name, p.Title)).ToArray());
        return new(Selected, [.. CustomProviders, provider], SuggestionsEnabled);
    }

    /// Replaces the custom engine with `provider`'s identity, keeping its
    /// position. Throws `Rejected` naming the rule it breaks, or with
    /// `UnknownSearchEngine` when there is none.
    public SearchPreferences Update(SearchProvider provider) {
        ArgumentNullException.ThrowIfNull(provider);
        var values = CustomProviders.ToList();
        int index = values.FindIndex(p => p.Name == provider.Name);
        if (index < 0) throw new Rejected(new UnknownSearchEngine(provider.Identity()));
        Admit(provider, values.Select(p => (p.Name, p.Title)).ToArray());
        values[index] = provider;
        return new(Selected.Name == provider.Name ? provider : Selected, values.AsReadOnly(), SuggestionsEnabled);
    }

    /// Removes a custom engine; removing the selected one selects Google.
    /// Throws `Rejected` with `UnknownSearchEngine` when there is none.
    public SearchPreferences Remove(Guid id) {
        string key = SearchProvider.CustomId(id);
        if (CustomProviders.All(p => p.Name != key)) throw new Rejected(new UnknownSearchEngine(id));
        return new(Selected.Name == key ? SearchProvider.Google : Selected,
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
