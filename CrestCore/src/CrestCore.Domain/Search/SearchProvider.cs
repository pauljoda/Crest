using System.Globalization;
using System.Net;

namespace CrestCore.Domain;

/// One search engine: a built-in from `SearchProviderCatalog` or a Space's
/// custom engine. Templates hold exactly one `%s` or `{searchTerms}` query
/// placeholder; both engines and both platforms build their URLs here.
public sealed record SearchProvider(string Id, string Name, string SearchTemplate, string? SuggestionTemplate = null) {
    #region Variables

    public const string CustomPrefix = "custom:";
    public const int MaximumNameLength = 64;
    public const int MaximumTemplateLength = 2048;
    private const string PercentPlaceholder = "%s";
    private const string OpenSearchPlaceholder = "{searchTerms}";
    private const string ProbeMarker = "crest-template-probe";

    private static readonly string[] SecretParameters =
        ["token", "key", "apikey", "api_key", "access_token", "password", "credential", "credentials", "auth", "authorization"];

    public bool IsCustom => Id.StartsWith(CustomPrefix, StringComparison.Ordinal);

    #endregion

    #region Actions - Queries

    /// The results URL for a query. The query is percent-encoded as UTF-8 with
    /// only RFC 3986 unreserved characters left bare, and replaces the single
    /// placeholder exactly once, so a query that spells a placeholder stays text.
    public string Search(string query) => Render(SearchTemplate, query);

    /// The suggestion endpoint for a query, or null when the engine has none.
    public string? Suggest(string query) => SuggestionTemplate is { } template ? Render(template, query) : null;

    public static string CustomId(Guid id) => CustomPrefix + id.ToString("D");

    private static string Render(string template, string query) {
        ArgumentNullException.ThrowIfNull(query);
        string encoded = Uri.EscapeDataString(query);
        int index = template.IndexOf(PercentPlaceholder, StringComparison.Ordinal);
        int length = PercentPlaceholder.Length;
        if (index < 0) { index = template.IndexOf(OpenSearchPlaceholder, StringComparison.Ordinal); length = OpenSearchPlaceholder.Length; }
        return index < 0 ? template : string.Concat(template.AsSpan(0, index), encoded, template.AsSpan(index + length));
    }

    #endregion

    #region Actions - Validation

    /// Validates and normalizes a custom engine. Names and templates are
    /// trimmed; an empty suggestion template means the engine has none.
    public static SearchProvider Custom(Guid id, string name, string search, string? suggestions) {
        ArgumentNullException.ThrowIfNull(name);
        ArgumentNullException.ThrowIfNull(search);
        if (id == Guid.Empty) throw new BrowserRuleException(BrowserRuleCodes.InvalidSearchProvider);
        name = name.Trim();
        if (name.Length == 0) throw new BrowserRuleException(BrowserRuleCodes.InvalidSearchName);
        if (new StringInfo(name).LengthInTextElements > MaximumNameLength) throw new BrowserRuleException(BrowserRuleCodes.SearchNameTooLong);
        return new(CustomId(id), name, ValidateTemplate(search),
            string.IsNullOrWhiteSpace(suggestions) ? null : ValidateTemplate(suggestions));
    }

    private static string ValidateTemplate(string value) {
        value = value.Trim();
        if (value.Length > MaximumTemplateLength) throw new BrowserRuleException(BrowserRuleCodes.SearchTemplateTooLong);
        int count = Occurrences(value, PercentPlaceholder) + Occurrences(value, OpenSearchPlaceholder);
        if (count == 0) throw new BrowserRuleException(BrowserRuleCodes.SearchPlaceholderMissing);
        if (count != 1) throw new BrowserRuleException(BrowserRuleCodes.InvalidSearchPlaceholder);
        for (int i = 0; i < value.Length; i++) {
            if (value[i] != '%') continue;
            if (i + 1 < value.Length && value[i + 1] == 's') { i++; continue; }
            if (i + 2 >= value.Length || !Uri.IsHexDigit(value[i + 1]) || !Uri.IsHexDigit(value[i + 2]))
                throw new BrowserRuleException(BrowserRuleCodes.InvalidSearchTemplate);
            i += 2;
        }
        var probe = value.Replace(PercentPlaceholder, ProbeMarker, StringComparison.Ordinal)
            .Replace(OpenSearchPlaceholder, ProbeMarker, StringComparison.Ordinal);
        // A template without a scheme is an HTTPS omission, not a malformed URL.
        if (!Uri.TryCreate(probe, UriKind.Absolute, out var uri) || uri.IsFile)
            throw new BrowserRuleException(probe.Contains("://", StringComparison.Ordinal)
                ? BrowserRuleCodes.InvalidSearchTemplate : BrowserRuleCodes.SearchTemplateRequiresHttps);
        if (uri.Scheme != Uri.UriSchemeHttps) throw new BrowserRuleException(BrowserRuleCodes.SearchTemplateRequiresHttps);
        if (uri.Host.Length == 0) throw new BrowserRuleException(BrowserRuleCodes.InvalidSearchTemplate);
        if (uri.UserInfo.Length != 0) throw new BrowserRuleException(BrowserRuleCodes.SearchTemplateCredentials);
        if (uri.Port != 443) throw new BrowserRuleException(BrowserRuleCodes.SearchTemplatePort);
        if (!IsPublicHost(uri.Host)) throw new BrowserRuleException(BrowserRuleCodes.UnsafeSearchTemplate);
        if (uri.Fragment.Contains(ProbeMarker, StringComparison.Ordinal))
            throw new BrowserRuleException(BrowserRuleCodes.SearchPlaceholderInFragment);
        foreach (var parameter in uri.Query.TrimStart('?').Split('&'))
            if (SecretParameters.Contains(Uri.UnescapeDataString(parameter.Split('=')[0]), StringComparer.OrdinalIgnoreCase))
                throw new BrowserRuleException(BrowserRuleCodes.SearchTemplateContainsSecret);
        return value;
    }

    /// A named public host: never local, numeric, or the query itself.
    private static bool IsPublicHost(string host) =>
        host.Contains('.') && !host.Contains(':')
        && !host.EndsWith(".local", StringComparison.OrdinalIgnoreCase)
        && !host.Equals("localhost", StringComparison.OrdinalIgnoreCase)
        && !host.EndsWith(".localhost", StringComparison.OrdinalIgnoreCase)
        && !host.Contains(ProbeMarker, StringComparison.OrdinalIgnoreCase)
        && !IPAddress.TryParse(host.Trim('[', ']'), out _);

    private static int Occurrences(string value, string placeholder) {
        int count = 0;
        for (int index = value.IndexOf(placeholder, StringComparison.Ordinal); index >= 0;
            index = value.IndexOf(placeholder, index + placeholder.Length, StringComparison.Ordinal)) count++;
        return count;
    }

    #endregion
}
