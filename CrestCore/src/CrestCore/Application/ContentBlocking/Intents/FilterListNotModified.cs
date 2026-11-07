using CrestCore.Application;

namespace CrestCore.Contracts;

/// `List`'s server said the copy the device holds is still current.
public sealed record FilterListNotModified(FilterList List) : Intent {
    #region Actions - Content blocking

    internal override IReadOnlyList<Change> Route(CrestApp app) => app.Turn(changes => app.Filters.NotModified(List, changes));

    #endregion
}
