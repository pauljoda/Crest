using CrestCore.Application;

namespace CrestCore.Contracts;

/// The platform could not download what `Id` names; the copy the device holds
/// stays in use, and the download is tried again later.
public sealed record FilterDownloadFailed(Guid Id) : Intent {
    #region Actions - Content blocking

    internal override IReadOnlyList<Change> Route(CrestApp app) => app.ChangeFilters(() => app.Filters.Failed(Id));

    #endregion
}
