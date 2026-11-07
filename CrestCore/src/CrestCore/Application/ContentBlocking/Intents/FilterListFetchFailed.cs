using CrestCore.Application;

namespace CrestCore.Contracts;

/// The platform could not download `List`. The copy the device holds stays in
/// use, and the list is tried again later.
public sealed record FilterListFetchFailed(FilterList List) : Intent {
    #region Actions - Content blocking

    internal override IReadOnlyList<Change> Route(CrestApp app) => app.Turn(changes => app.Filters.Failed(List, changes));

    #endregion
}
