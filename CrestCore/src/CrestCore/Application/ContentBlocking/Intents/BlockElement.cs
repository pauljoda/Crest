using CrestCore.Application;

namespace CrestCore.Contracts;

/// Hides what `Selector` matches on the site `PageUrl` shows from now on, as a
/// rule the core adds to the person's own filters. Refused for a page that is
/// not on the web, a selector a rule cannot hold, or filters longer than the
/// core keeps.
public sealed record BlockElement(string PageUrl, string Selector) : Intent {
    #region Actions - Content blocking

    internal override IReadOnlyList<Change> Route(CrestApp app) => app.ChangeFilters(() => {
        if (!app.Device.AddCustomFilter(ElementRule.For(PageUrl, Selector).Text)) return false;
        app.Filters.SubscriptionsChanged();
        return true;
    });

    #endregion
}
