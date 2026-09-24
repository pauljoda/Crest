namespace CrestCore.Contracts;

/// What a tab's page shows now, which a copy of the tab starts from: its
/// address, when it has one, and its title, which may be empty. The platform
/// reports it because a page can move on before the session records where it
/// went.
///
/// TRANSITIONAL until WP C slice (c) keeps each page's live state in `Pages`:
/// the core then reads a source page's live address and title itself, and
/// this record and the `SourcePages` of `JoinSplit` and `OpenLinkInSplit` go.
public sealed record SourcePage(Guid TabId, string? Address, string Title);
