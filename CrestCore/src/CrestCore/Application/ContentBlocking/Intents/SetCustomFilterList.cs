using CrestCore.Application;

namespace CrestCore.Contracts;

/// Turns the filter list the person added as `Id` on or off.
public sealed record SetCustomFilterList(Guid Id, bool IsOn) : Intent {
    #region Actions - Content blocking

    internal override IReadOnlyList<Change> Route(CrestApp app) => app.ChangeFilters(() => {
        if (!app.Device.ChooseCustomFilterList(Id, IsOn)) return false;
        app.Filters.SubscriptionsChanged();
        return true;
    });

    #endregion
}
