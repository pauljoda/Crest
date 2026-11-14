using CrestCore.Application;

namespace CrestCore.Contracts;

/// The platform downloaded what `Id` names, with the validators its server
/// gave, which make the next download a conditional one. Refused for a text
/// longer than the core keeps.
public sealed record FilterDownloadFetched(Guid Id, string Text, string? EntityTag, string? LastModified) : Intent {
    #region Actions - Content blocking

    internal override IReadOnlyList<Change> Route(CrestApp app) =>
        app.ChangeFilters(() => app.Filters.Fetched(Id, Text, EntityTag, LastModified));

    #endregion
}
