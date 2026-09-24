namespace CrestCore.Contracts;

/// An import placed these tabs, open or archived, each from a tab of the Spaces
/// it brought, so each wears the image its importer holds for the tab it came
/// from.
public sealed record TabsImported(Guid WorkspaceId, IReadOnlyList<ImportedTab> Tabs) : Change;
