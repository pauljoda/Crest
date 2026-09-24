namespace CrestCore.Contracts;

/// What a tab's page shows now, which a copy of the tab starts from: its
/// address, when it has one, and its title, which may be empty. The platform
/// reports it because a page can move on before the session records where it
/// went.
///
/// TRANSITIONAL until `DuplicateTab` reads its source's live page from
/// `Pages`, as a split join already does: this record and `DuplicateTab.Source`
/// then go.
public sealed record SourcePage(Guid TabId, string? Address, string Title);
