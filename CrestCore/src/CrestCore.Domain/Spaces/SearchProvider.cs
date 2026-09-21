using System.Net;

namespace CrestCore.Domain;

public sealed record SearchProvider(string Id, string Name, string SearchTemplate, string? SuggestionTemplate = null) {
    #region Actions - Spaces

    public string Search(string query) => SearchTemplate.Replace("%s", Uri.EscapeDataString(query), StringComparison.Ordinal)
        .Replace("{searchTerms}", Uri.EscapeDataString(query), StringComparison.Ordinal);

    public static SearchProvider Custom(Guid id, string name, string search, string? suggestions) {
        name = name.Trim();
        if (id == Guid.Empty || name.Length is 0 or > 64) throw new BrowserRuleException(BrowserRuleCodes.InvalidSearchName);
        return new("custom:" + id.ToString(), name, ValidateTemplate(search),
            string.IsNullOrWhiteSpace(suggestions) ? null : ValidateTemplate(suggestions));
    }

    #endregion

    #region Actions - Validation

    private static string ValidateTemplate(string value) {
        value = value.Trim();
        if (value.Length > 2048) throw new BrowserRuleException(BrowserRuleCodes.InvalidSearchTemplate);
        int count = value.Split("%s").Length + value.Split("{searchTerms}").Length - 2;
        if (count != 1) throw new BrowserRuleException(BrowserRuleCodes.InvalidSearchPlaceholder);
        for (int i = 0; i < value.Length; i++) {
            if (value[i] != '%') continue;
            if (i + 1 < value.Length && value[i + 1] == 's') { i++; continue; }
            if (i + 2 >= value.Length || !Uri.IsHexDigit(value[i + 1]) || !Uri.IsHexDigit(value[i + 2]))
                throw new BrowserRuleException(BrowserRuleCodes.InvalidSearchTemplate);
            i += 2;
        }
        const string marker = "crest-template-probe";
        var probe = value.Replace("%s", marker, StringComparison.Ordinal).Replace("{searchTerms}", marker, StringComparison.Ordinal);
        if (!Uri.TryCreate(probe, UriKind.Absolute, out var uri) || uri.Scheme != Uri.UriSchemeHttps || uri.Port != 443
            || uri.UserInfo.Length != 0 || !uri.Host.Contains('.') || uri.Host.EndsWith(".local", StringComparison.OrdinalIgnoreCase)
            || uri.Host.EndsWith(".localhost", StringComparison.OrdinalIgnoreCase) || uri.Host.Contains(marker, StringComparison.Ordinal)
            || IPAddress.TryParse(uri.Host, out _) || uri.Fragment.Contains(marker, StringComparison.Ordinal))
            throw new BrowserRuleException(BrowserRuleCodes.UnsafeSearchTemplate);
        string[] secrets = ["token", "key", "apikey", "api_key", "access_token", "password", "credential", "credentials", "auth", "authorization"];
        foreach (var parameter in uri.Query.TrimStart('?').Split('&'))
            if (secrets.Contains(Uri.UnescapeDataString(parameter.Split('=')[0]), StringComparer.OrdinalIgnoreCase))
                throw new BrowserRuleException(BrowserRuleCodes.SearchTemplateContainsSecret);
        return value;
    }

    #endregion
}
