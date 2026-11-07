using CrestCore.Application;

namespace CrestCore.Contracts;

/// The filter list downloads the platform should make now. Each one handed
/// out is not handed out again for a while, so the platform reports how it
/// went with `FilterListFetched`, `FilterListNotModified` or
/// `FilterListFetchFailed`.
public sealed record DueFilterListFetches : Query<IReadOnlyList<FilterListFetch>> {
    #region Actions - Answering

    internal override IReadOnlyList<FilterListFetch> Answer(CrestApp app) => app.Filters.Due();

    #endregion
}
