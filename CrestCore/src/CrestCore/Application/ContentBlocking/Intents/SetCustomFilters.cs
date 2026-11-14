using CrestCore.Application;

namespace CrestCore.Contracts;

/// Replaces the person's own filters, in the lists' syntax, which every Space
/// that blocks applies beside the lists. Refused for filters longer than the
/// core keeps.
public sealed record SetCustomFilters(string Text) : Intent {
    #region Actions - Content blocking

    internal override IReadOnlyList<Change> Route(CrestApp app) => app.ChangeFilters(() => {
        if (!app.Device.SetCustomFilters(Text)) return false;
        app.Filters.SubscriptionsChanged();
        return true;
    });

    #endregion
}
