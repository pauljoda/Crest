namespace CrestCore.Contracts;

/// The session the import would leave its workspace with, without importing
/// anything: what a person sees before they import. It shows Spaces this
/// process has not unlocked, since an import that changes one waits until it
/// is; otherwise it is refused as the import would be.
[MessageLimit(64 * 1024 * 1024)]
public sealed record ImportPreview(ImportWorkspace Import) : Query<ImportedWorkspace>;
