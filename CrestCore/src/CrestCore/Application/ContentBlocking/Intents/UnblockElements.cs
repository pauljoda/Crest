using CrestCore.Application;

namespace CrestCore.Contracts;

/// Shows again what the person blocked on the site `PageUrl` shows: the core
/// removes the rules of their own filters that hide elements on its host.
public sealed record UnblockElements(string PageUrl) : Intent {
    #region Actions - Content blocking

    internal override IReadOnlyList<Change> Route(CrestApp app) => app.ChangeFilters(() => {
        if (ElementRule.HostOf(PageUrl) is not { } host
            || !app.Device.RemoveCustomFilters(line => ElementRule.Hides(line, host))) return false;
        app.Filters.SubscriptionsChanged();
        return true;
    });

    #endregion
}
