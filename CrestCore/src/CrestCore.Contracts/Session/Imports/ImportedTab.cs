namespace CrestCore.Contracts;

/// A tab an import placed, `TabId`, and the tab it came from: `SourceTabId`,
/// open or archived, of the import's Space at position `Source` among its
/// Spaces.
public sealed record ImportedTab(Guid TabId, int Source, Guid SourceTabId);
