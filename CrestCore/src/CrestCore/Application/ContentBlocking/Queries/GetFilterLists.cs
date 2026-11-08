using CrestCore.Application;

namespace CrestCore.Contracts;

/// Every filter list as the settings show it, and the person's own filters.
public sealed record GetFilterLists : Query<FilterLists> {
    #region Actions - Answering

    internal override FilterLists Answer(CrestApp app) => app.Filters.States();

    #endregion
}
