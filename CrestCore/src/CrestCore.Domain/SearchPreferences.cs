using System.Globalization;
using System.Net;
using System.Text;

namespace CrestCore.Domain;

public sealed record SearchProvider(string Id, string Name, string SearchTemplate, string? SuggestionTemplate = null)
{
    public string Search(string query) => SearchTemplate.Replace("%s", Uri.EscapeDataString(query), StringComparison.Ordinal)
        .Replace("{searchTerms}", Uri.EscapeDataString(query), StringComparison.Ordinal);

    public static SearchProvider Custom(Guid id, string name, string search, string? suggestions)
    {
        name = name.Trim();
        if (id == Guid.Empty || name.Length is 0 or > 64) throw new BrowserRuleException("invalid_search_name");
        return new("custom:" + id.ToString(), name, ValidateTemplate(search),
            string.IsNullOrWhiteSpace(suggestions) ? null : ValidateTemplate(suggestions));
    }
    private static string ValidateTemplate(string value)
    {
        value = value.Trim();
        if (value.Length > 2048) throw new BrowserRuleException("invalid_search_template");
        int count = value.Split("%s").Length + value.Split("{searchTerms}").Length - 2;
        if (count != 1) throw new BrowserRuleException("invalid_search_placeholder");
        for (int i = 0; i < value.Length; i++)
        {
            if (value[i] != '%') continue;
            if (i + 1 < value.Length && value[i + 1] == 's') { i++; continue; }
            if (i + 2 >= value.Length || !Uri.IsHexDigit(value[i + 1]) || !Uri.IsHexDigit(value[i + 2]))
                throw new BrowserRuleException("invalid_search_template");
            i += 2;
        }
        const string marker = "crest-template-probe";
        var probe = value.Replace("%s", marker, StringComparison.Ordinal).Replace("{searchTerms}", marker, StringComparison.Ordinal);
        if (!Uri.TryCreate(probe, UriKind.Absolute, out var uri) || uri.Scheme != "https" || uri.Port != 443
            || uri.UserInfo.Length != 0 || !uri.Host.Contains('.') || uri.Host.EndsWith(".local", StringComparison.OrdinalIgnoreCase)
            || uri.Host.EndsWith(".localhost", StringComparison.OrdinalIgnoreCase) || uri.Host.Contains(marker, StringComparison.Ordinal)
            || IPAddress.TryParse(uri.Host, out _) || uri.Fragment.Contains(marker, StringComparison.Ordinal))
            throw new BrowserRuleException("unsafe_search_template");
        string[] secrets = ["token", "key", "apikey", "api_key", "access_token", "password", "credential", "credentials", "auth", "authorization"];
        foreach (var parameter in uri.Query.TrimStart('?').Split('&'))
            if (secrets.Contains(Uri.UnescapeDataString(parameter.Split('=')[0]), StringComparer.OrdinalIgnoreCase))
                throw new BrowserRuleException("search_template_contains_secret");
        return value;
    }
}

public sealed class SearchPreferences
{
    public static readonly IReadOnlyList<SearchProvider> BuiltIns = Array.AsReadOnly<SearchProvider>([
        new("google", "Google", "https://www.google.com/search?q=%s"),
        new("duckDuckGo", "DuckDuckGo", "https://duckduckgo.com/?q=%s"),
        new("bing", "Bing", "https://www.bing.com/search?q=%s"),
        new("ecosia", "Ecosia", "https://www.ecosia.org/search?q=%s"),
        new("brave", "Brave Search", "https://search.brave.com/search?q=%s")
    ]);
    public static SearchPreferences Default { get; } = new("google", [], false);
    public string SelectedId { get; }
    public IReadOnlyList<SearchProvider> CustomProviders { get; }
    public bool SuggestionsEnabled { get; }
    public IEnumerable<SearchProvider> Providers => BuiltIns.Concat(CustomProviders);
    private SearchPreferences(string selected, IReadOnlyList<SearchProvider> custom, bool suggestions)
    { SelectedId = selected; CustomProviders = custom; SuggestionsEnabled = suggestions; }
    public static SearchPreferences Restore(string? selected, IEnumerable<SearchProvider> custom, bool suggestions)
    {
        var providers = custom.Take(32).GroupBy(p => p.Id).Select(g => g.First()).ToArray();
        if (!BuiltIns.Concat(providers).Any(p => p.Id == selected)) selected = "google";
        return new(selected!, Array.AsReadOnly(providers), suggestions);
    }
    public SearchPreferences Select(string id, bool suggestions)
    {
        if (!Providers.Any(p => p.Id == id)) throw new BrowserRuleException("unknown_search_provider");
        return new(id, CustomProviders, suggestions);
    }
    public SearchPreferences Upsert(SearchProvider provider)
    {
        if (!provider.Id.StartsWith("custom:", StringComparison.Ordinal)) throw new BrowserRuleException("invalid_search_provider");
        var validated = SearchProvider.Custom(Guid.Parse(provider.Id[7..]), provider.Name, provider.SearchTemplate, provider.SuggestionTemplate);
        string Fold(string value) => string.Concat(value.Normalize(NormalizationForm.FormD)
            .Where(c => CharUnicodeInfo.GetUnicodeCategory(c) != UnicodeCategory.NonSpacingMark)).ToUpperInvariant();
        if (CustomProviders.Any(p => p.Id != validated.Id && Fold(p.Name) == Fold(validated.Name)))
            throw new BrowserRuleException("duplicate_search_name");
        var values = CustomProviders.ToList(); int index = values.FindIndex(p => p.Id == validated.Id);
        if (index < 0) { if (values.Count >= 32) throw new BrowserRuleException("search_provider_limit"); values.Add(validated); }
        else values[index] = validated;
        return new(SelectedId, values.AsReadOnly(), SuggestionsEnabled);
    }
    public SearchPreferences Remove(Guid id)
    {
        string key = "custom:" + id.ToString();
        return new(SelectedId == key ? "google" : SelectedId, CustomProviders.Where(p => p.Id != key).ToList().AsReadOnly(), SuggestionsEnabled);
    }
    public string Resolve(string input, bool allowsInternalPages)
    {
        var value = input.Trim();
        var resolution = value == "about:blank" ? new AddressResolution(value, null)
            : AddressResolution.Resolve(input, Providers.Single(p => p.Id == SelectedId), allowsInternalPages)
                ?? throw new BrowserRuleException("invalid_address");
        string address = resolution.Url;
        if (resolution.SearchQuery is null && Uri.TryCreate(address, UriKind.Absolute, out var uri)
            && uri.Scheme is "http" or "https") address = uri.AbsoluteUri;
        BrowserSpace.ValidateUrl(address, allowsInternalPages);
        return address;
    }
}
