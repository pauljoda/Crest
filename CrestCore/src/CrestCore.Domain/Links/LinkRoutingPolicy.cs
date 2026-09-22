namespace CrestCore.Domain;

/// Decides where a link opened from outside Crest goes: the first enabled
/// route whose Space can open, else the external-link destination preference.
public static class LinkRoutingPolicy {
    #region Actions - Routing

    public static LinkRoutingDecision Decide(string url, LinkRoutingPreferences preferences, LinkRoutingContext context) {
        var route = preferences.Routes.FirstOrDefault(candidate => candidate.IsEnabled
            && context.IsAvailable(candidate.DestinationSpaceId) && Matches(candidate, url));
        if (route is not null) return new(false, route.DestinationSpaceId);
        return preferences.Destination switch {
            ExternalLinkDestination.MostRecentSpace => new(false, context.Fallback()),
            ExternalLinkDestination.ChosenSpace => new(false,
                preferences.ChosenSpaceId is { } chosen && context.IsAvailable(chosen) ? chosen : context.Fallback()),
            _ => new(true, preferences.RemembersSpaceBySite && preferences.RememberedSpaceId is { } remembered
                && context.IsAvailable(remembered) ? remembered : context.Fallback())
        };
    }

    /// The key a Quick Window remembers its Space under: the lowercased host
    /// without a leading `www.`. Null for an address without a host.
    public static string? Site(string url) {
        if (!Uri.TryCreate(url, UriKind.Absolute, out var value) || string.IsNullOrEmpty(value.Host)) return null;
        string host = value.Host.ToLowerInvariant();
        return host.StartsWith("www.", StringComparison.Ordinal) ? host[4..] : host;
    }

    private static bool Matches(LinkRoute route, string url) {
        string pattern = route.Pattern.Trim();
        if (pattern.Length == 0) return false;
        string candidate = HistoryPolicy.Normalize(url) ?? url;
        return route.Match switch {
            LinkRouteMatch.Exact => string.Equals(candidate, HistoryPolicy.Normalize(pattern) ?? pattern,
                StringComparison.OrdinalIgnoreCase),
            _ => candidate.Contains(pattern, StringComparison.OrdinalIgnoreCase)
        };
    }

    #endregion
}
