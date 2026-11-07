using CrestCore.Application;

namespace CrestCore.Contracts;

/// The platform downloaded `List`'s text, with the validators its server
/// gave, which make the next download a conditional one. Refused for a text
/// longer than the core keeps.
public sealed record FilterListFetched(FilterList List, string Text, string? EntityTag, string? LastModified) : Intent {
    #region Actions - Content blocking

    internal override IReadOnlyList<Change> Route(CrestApp app) =>
        app.Turn(changes => app.Filters.Fetched(List, Text, EntityTag, LastModified, changes));

    #endregion
}
