using CrestCore.Application;

namespace CrestCore.Contracts;

/// The platform stopped downloading what `Id` names once it grew past the
/// most the core keeps; the copy the device holds stays in use, the list shows
/// it is too large, and the download is tried again later.
public sealed record FilterDownloadTooLarge(Guid Id) : Intent {
    #region Actions - Content blocking

    internal override IReadOnlyList<Change> Route(CrestApp app) => app.ChangeFilters(() => app.Filters.TooLarge(Id));

    #endregion
}
