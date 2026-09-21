namespace CrestCore.Domain;

public sealed record AddressResolution(string Url, string? SearchQuery)
{
    public static AddressResolution? Resolve(string input, SearchProvider provider, bool allowsInternalPages = false)
    {
        string value = input.Trim();
        if (value.Length == 0) return null;
        if (value.Length > 4096) throw new BrowserRuleException("invalid_address");
        if (value == "about:blank" || value.StartsWith("chrome://", StringComparison.OrdinalIgnoreCase)
            || value.StartsWith("crest://", StringComparison.OrdinalIgnoreCase)
            || value.StartsWith("chrome-extension://", StringComparison.OrdinalIgnoreCase))
        {
            if (!allowsInternalPages) return new(provider.Search(value), value);
            BrowserSpace.ValidateUrl(value, allowsInternalPages: true);
            return new(value, null);
        }
        if (Uri.TryCreate(value, UriKind.Absolute, out var explicitUrl) && explicitUrl.Scheme is "http" or "https"
            && explicitUrl.Host.Length > 0) return new(value, null);
        if (!value.Any(char.IsWhiteSpace))
        {
            if (Uri.TryCreate("http://" + value, UriKind.Absolute, out var local)
                && local.Host.Equals("localhost", StringComparison.OrdinalIgnoreCase)) return new("http://" + value, null);
            if (value.Contains('.') && Uri.TryCreate("https://" + value, UriKind.Absolute, out var domain)
                && domain.Host.Length > 0) return new("https://" + value, null);
        }
        return new(provider.Search(value), value);
    }
}
