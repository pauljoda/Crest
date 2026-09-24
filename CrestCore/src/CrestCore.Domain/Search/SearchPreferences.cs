using System.Globalization;
using System.Text;

using CrestCore.Contracts;

namespace CrestCore.Domain;

/// A Space's search choice and its custom engines.
public sealed class SearchPreferences {
    #region Variables

    public const int MaximumCustomProviders = 32;

    public static IReadOnlyList<SearchProvider> BuiltIns => SearchProviderCatalog.BuiltIns;
    public static SearchPreferences Default { get; } = new(SearchProviderCatalog.GoogleId, [], false);
    public string SelectedId { get; }
    public IReadOnlyList<SearchProvider> CustomProviders { get; }
    public bool SuggestionsEnabled { get; }
    public IEnumerable<SearchProvider> Providers => BuiltIns.Concat(CustomProviders);
    public SearchProvider Selected => Providers.Single(p => p.Id == SelectedId);

    #endregion

    #region Constructors

    private SearchPreferences(string selected, IReadOnlyList<SearchProvider> custom, bool suggestions) { SelectedId = selected; CustomProviders = custom; SuggestionsEnabled = suggestions; }

    #endregion

    #region Actions - Search providers

    /// Restores stored preferences: the first provider for each identity, at
    /// most the custom limit, and Google when the selection is not available.
    public static SearchPreferences Restore(string? selected, IEnumerable<SearchProvider> custom, bool suggestions) {
        var providers = custom.GroupBy(p => p.Id).Select(g => g.First()).Take(MaximumCustomProviders).ToArray();
        if (!BuiltIns.Concat(providers).Any(p => p.Id == selected)) selected = SearchProviderCatalog.GoogleId;
        return new(selected!, Array.AsReadOnly(providers), suggestions);
    }

    /// A Space's stored search choice. Stored custom engines that no longer
    /// validate are left out, as the selection that named one falls back to Google.
    public static SearchPreferences Restore(BrowsingPreferences browsing) {
        ArgumentNullException.ThrowIfNull(browsing);
        var providers = new List<SearchProvider>();
        foreach (var custom in browsing.CustomSearchProviders) {
            try {
                providers.Add(SearchProvider.Custom(custom.Id, custom.Name, custom.SearchUrlTemplate, custom.SuggestionUrlTemplate));
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
            Guid.Parse(provider.Id[SearchProvider.CustomPrefix.Length..]), provider.Name, provider.SearchTemplate,
            provider.SuggestionTemplate)).ToArray(),
        SearchSuggestionsEnabled = SuggestionsEnabled
    };

    /// Rejects an already validated custom engine whose name another custom
    /// engine uses (ignoring case and diacritics), or that would exceed the limit.
    public static void RequireAdmissible(SearchProvider provider, IReadOnlyCollection<(string Id, string Name)> existing) {
        ArgumentNullException.ThrowIfNull(provider);
        ArgumentNullException.ThrowIfNull(existing);
        if (!provider.IsCustom) throw new BrowserRuleException(BrowserRuleCodes.InvalidSearchProvider);
        string name = Fold(provider.Name);
        if (existing.Any(p => p.Id != provider.Id && Fold(p.Name) == name))
            throw new BrowserRuleException(BrowserRuleCodes.DuplicateSearchName);
        if (existing.All(p => p.Id != provider.Id) && existing.Count >= MaximumCustomProviders)
            throw new BrowserRuleException(BrowserRuleCodes.SearchProviderLimit);
    }

    private static string Fold(string value) => string.Concat(value.Trim().Normalize(NormalizationForm.FormD)
        .Where(c => CharUnicodeInfo.GetUnicodeCategory(c) != UnicodeCategory.NonSpacingMark)).ToUpperInvariant();

    #endregion

    #region Mutators

    public SearchPreferences Select(string id, bool suggestions) {
        if (!Providers.Any(p => p.Id == id)) throw new BrowserRuleException(BrowserRuleCodes.UnknownSearchProvider);
        return new(id, CustomProviders, suggestions);
    }

    /// Adds or replaces a custom engine by identity, keeping its position.
    public SearchPreferences Upsert(SearchProvider provider) {
        ArgumentNullException.ThrowIfNull(provider);
        if (!provider.IsCustom || !Guid.TryParseExact(provider.Id[SearchProvider.CustomPrefix.Length..], "D", out var id))
            throw new BrowserRuleException(BrowserRuleCodes.InvalidSearchProvider);
        var validated = SearchProvider.Custom(id, provider.Name, provider.SearchTemplate, provider.SuggestionTemplate);
        RequireAdmissible(validated, CustomProviders.Select(p => (p.Id, p.Name)).ToArray());
        var values = CustomProviders.ToList(); int index = values.FindIndex(p => p.Id == validated.Id);
        if (index < 0) values.Add(validated); else values[index] = validated;
        return new(SelectedId, values.AsReadOnly(), SuggestionsEnabled);
    }

    /// Removes a custom engine; removing the selected one selects Google.
    public SearchPreferences Remove(Guid id) {
        string key = SearchProvider.CustomId(id);
        return new(SelectedId == key ? SearchProviderCatalog.GoogleId : SelectedId,
            CustomProviders.Where(p => p.Id != key).ToList().AsReadOnly(), SuggestionsEnabled);
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
