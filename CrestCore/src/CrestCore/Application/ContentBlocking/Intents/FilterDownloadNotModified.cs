using CrestCore.Application;

namespace CrestCore.Contracts;

/// The server of what `Id` names said the device's copy is still current.
public sealed record FilterDownloadNotModified(Guid Id) : Intent {
    #region Actions - Content blocking

    internal override IReadOnlyList<Change> Route(CrestApp app) => app.ChangeFilters(() => app.Filters.NotModified(Id));

    #endregion
}
