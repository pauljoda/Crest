namespace CrestCore.Contracts;

/// The session an import would leave: `Session`, the tabs it would place from
/// its Spaces, and the workspace's own tabs that would take a new identity.
public sealed record ImportedWorkspace(SessionState Session, IReadOnlyList<ImportedTab> Imported, IReadOnlyList<TabCopied> Copied);
