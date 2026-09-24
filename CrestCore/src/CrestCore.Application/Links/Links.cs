using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

/// The links area: where a link opened from outside Crest goes, and the site
/// key a Quick Window remembers its Space under. It holds no state; the link
/// preferences stay with the platform, which sends what routing reads.
public sealed class Links {
    #region Actions - Routing

    public ExternalLinkPlacement Answer(ExternalLinkRoute query) {
        ArgumentNullException.ThrowIfNull(query);
        var decision = LinkRoutingPolicy.DecideExternal(query.Url, query.Preferences, query.Context, query.LockedSpaceIds);
        return decision is { } placed
            ? new(placed.SpaceId, placed.OpensQuickWindow, placed.SubstitutesForLockedSpace)
            : new(null, false, false);
    }

    public QuickWindowSiteKey Answer(QuickWindowSite query) {
        ArgumentNullException.ThrowIfNull(query);
        return new(query.RemembersSpaceBySite ? LinkRoutingPolicy.Site(query.Url) : null);
    }

    #endregion
}
