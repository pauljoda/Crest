using CrestCore.Application;

namespace CrestCore.Contracts;

/// Every filter list as the settings show it, in `FilterList.All` order.
public sealed record GetFilterLists : Query<IReadOnlyList<FilterListState>> {
    #region Actions - Answering

    internal override IReadOnlyList<FilterListState> Answer(CrestApp app) => app.Filters.States();

    #endregion
}
