using CrestCore.Application;

namespace CrestCore.Contracts;

/// Turns a filter list on or off on this device, against what the level turns on.
/// A list turned on is downloaded with the next updates the platform makes.
public sealed record SetFilterList(FilterList List, bool IsOn) : Intent {
    #region Actions - Content blocking

    internal override IReadOnlyList<Change> Route(CrestApp app) => app.ChangeFilters(() => {
        if (!app.Device.ChooseFilterList(List, IsOn)) return false;
        app.Filters.SubscriptionsChanged();
        return true;
    });

    #endregion
}
