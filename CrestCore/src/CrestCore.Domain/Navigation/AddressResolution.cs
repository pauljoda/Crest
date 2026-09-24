using CrestCore.Contracts;

namespace CrestCore.Domain;

public sealed record AddressResolution(string Url, string? SearchQuery) {
    #region Actions - Navigation

    /// The address a page loads for what the person typed or chose in a Space
    /// with `preferences`, on an engine that shows internal pages or not: an
    /// address as it is, or a search with the Space's engine. Throws
    /// `Rejected` with `UnsupportedAddress` when the input names nothing a
    /// page can load, as blank input does.
    public static string Loading(string input, BrowsingPreferences preferences, bool allowsInternalPages) {
        ArgumentNullException.ThrowIfNull(input);
        ArgumentNullException.ThrowIfNull(preferences);
        // The empty document is an address on every engine, whatever its fragment.
        var value = input.Trim();
        if (value == BrowserUrlConstants.AboutBlank || value.StartsWith(BrowserUrlConstants.AboutBlank + "#", StringComparison.Ordinal))
            return value;
        AddressResolution? resolution;
        try {
            resolution = Resolve(input, SearchPreferences.Restore(preferences).Selected, allowsInternalPages);
        } catch (BrowserRuleException) {
            throw new Rejected(new UnsupportedAddress(input));
        }
        if (resolution is null || !Uri.TryCreate(resolution.Url, UriKind.Absolute, out _))
            throw new Rejected(new UnsupportedAddress(input));
        return resolution.Url;
    }

    public static AddressResolution? Resolve(string input, SearchProvider provider, bool allowsInternalPages = false) {
        string value = input.Trim();
        if (value.Length == 0) return null;
        if (value.Length > 4096) throw new BrowserRuleException(BrowserRuleCodes.InvalidAddress);
        if (value == BrowserUrlConstants.AboutBlank || value.StartsWith(BrowserUrlConstants.ChromePrefix, StringComparison.OrdinalIgnoreCase)
            || value.StartsWith(BrowserUrlConstants.CrestPrefix, StringComparison.OrdinalIgnoreCase)
            || value.StartsWith(BrowserUrlConstants.ChromeExtensionPrefix, StringComparison.OrdinalIgnoreCase)) {
            if (!allowsInternalPages) return new(provider.Search(value), value);
            BrowserSpace.ValidateUrl(value, allowsInternalPages: true);
            return new(value, null);
        }
        if (Uri.TryCreate(value, UriKind.Absolute, out var explicitUrl)
            && (explicitUrl.Scheme == Uri.UriSchemeHttp || explicitUrl.Scheme == Uri.UriSchemeHttps)
            && explicitUrl.Host.Length > 0) return new(value, null);
        if (LocalFile(value) is { } localFile) return new(localFile, null);
        if (!value.Any(char.IsWhiteSpace)) {
            if (Uri.TryCreate("http://" + value, UriKind.Absolute, out var local)
                && local.Host.Equals("localhost", StringComparison.OrdinalIgnoreCase)) return new("http://" + value, null);
            if (value.Contains('.') && Uri.TryCreate("https://" + value, UriKind.Absolute, out var domain)
                && domain.Host.Length > 0) return new("https://" + value, null);
        }
        return new(provider.Search(value), value);
    }

    /// An explicit `file://` URL, or an absolute path the person typed. Only these
    /// three spellings reach a local document; everything else stays a search, and
    /// nothing here touches the file system, so the decision stays deterministic.
    private static string? LocalFile(string value) {
        string candidate = value;
        if (candidate.StartsWith('~')) {
            if (candidate.Length > 1 && candidate[1] != '/') return null;
            string home = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
            if (home.Length == 0) return null;
            candidate = home.TrimEnd('/') + candidate[1..];
        } else if (!candidate.StartsWith('/') && !candidate.StartsWith("file:", StringComparison.OrdinalIgnoreCase)) {
            return null;
        }
        if (!Uri.TryCreate(candidate, UriKind.Absolute, out var parsed) || parsed.Scheme != Uri.UriSchemeFile
            || parsed.UserInfo.Length > 0 || parsed.AbsolutePath.Length == 0) return null;
        if (parsed.Host.Length == 0) return parsed.AbsoluteUri;
        // `file://localhost/…` names this device the long way round; anything else
        // is a remote authority Crest does not read as a local document.
        if (!parsed.Host.Equals("localhost", StringComparison.OrdinalIgnoreCase)) return null;
        return new UriBuilder(parsed) { Host = string.Empty }.Uri.AbsoluteUri;
    }

    #endregion
}
