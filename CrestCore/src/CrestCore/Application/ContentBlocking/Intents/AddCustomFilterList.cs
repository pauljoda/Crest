using CrestCore.Application;

namespace CrestCore.Contracts;

/// Adds the filter list at `Url`, on, for every Space that blocks; it is
/// downloaded with the next updates the platform makes. Refused for an address
/// that is not http or https, one already added, or past the most lists the
/// core keeps.
public sealed record AddCustomFilterList(Guid Id, string Url) : Intent {
    #region Actions - Content blocking

    internal override IReadOnlyList<Change> Route(CrestApp app) => app.ChangeFilters(() => {
        if (!app.Device.AddCustomFilterList(Id, Url)) return false;
        app.Filters.SubscriptionsChanged();
        return true;
    });

    #endregion
}
