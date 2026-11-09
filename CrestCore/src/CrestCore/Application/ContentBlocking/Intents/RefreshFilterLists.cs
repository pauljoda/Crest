using CrestCore.Application;

namespace CrestCore.Contracts;

/// Updates every filter list the device subscribes to now, as the person
/// asked: each is downloaded again with the next updates the platform makes.
public sealed record RefreshFilterLists : Intent {
    #region Actions - Content blocking

    internal override IReadOnlyList<Change> Route(CrestApp app) => app.ChangeFilters(app.Filters.RefreshAll);

    #endregion
}
