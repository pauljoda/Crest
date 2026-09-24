using CrestCore.Contracts;

namespace CrestCore.Domain;

/// Decides where a link opened from outside Crest goes: the first enabled
/// route whose Space can open, else the external-link destination preference.
public static class LinkRoutingPolicy {
    #region Actions - Routing

    /// Where a link from another process goes when some Spaces are locked. A
    /// locked Space is never unlocked on such a link's behalf: the link opens
    /// in a Quick Window on the selected Space when that one is unlocked and
    /// available, else on the first that is. Null when no Space can take it.
    public static LinkRoutingDecision? DecideExternal(string url, LinkRoutingPreferences preferences,
        LinkRoutingContext context, IReadOnlyCollection<Guid> locked) {
        ArgumentNullException.ThrowIfNull(locked);
        var routed = Decide(url, preferences, context);
        if (!locked.Contains(routed.SpaceId)) return routed;
        bool Open(Guid space) => context.IsAvailable(space) && !locked.Contains(space);
        Guid? substitute = Open(context.SelectedSpaceId) ? context.SelectedSpaceId
            : context.Spaces.Where(Open).Select(space => (Guid?)space).FirstOrDefault();
        return substitute is { } space ? new(true, space, SubstitutesForLockedSpace: true) : null;
    }

    public static LinkRoutingDecision Decide(string url, LinkRoutingPreferences preferences, LinkRoutingContext context) {
        var route = preferences.Routes.FirstOrDefault(candidate => candidate.IsEnabled
            && context.IsAvailable(candidate.DestinationSpaceId) && Matches(candidate, url));
        if (route is not null) return new(false, route.DestinationSpaceId);
        var destination = preferences.Destination;
        return new(destination.OpensQuickWindow, destination.Space(preferences, context));
    }

    /// The key a Quick Window remembers its Space under: the lowercased host
    /// without a leading `www.`. Null for an address without a host.
    public static string? Site(string url) {
        if (!Uri.TryCreate(url, UriKind.Absolute, out var value) || string.IsNullOrEmpty(value.Host)) return null;
        return SiteHost.WithoutWww(value.Host.ToLowerInvariant());
    }

    private static bool Matches(LinkRoute route, string url) {
        string pattern = route.Pattern.Trim();
        if (pattern.Length == 0) return false;
        return route.Match.Matches(Normalized(url), pattern, Normalized);
    }

    private static string Normalized(string address) => HistoryPolicy.Normalize(address) ?? address;

    #endregion
}
