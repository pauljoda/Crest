namespace CrestCore.Contracts;

/// <summary>A command made <see cref="CopyTabId"/> as a copy of <see cref="SourceTabId"/>,
/// so the copy shows the image the platform keeps for its source.</summary>
public sealed record TabCopied(Guid WorkspaceId, Guid SourceTabId, Guid CopyTabId) : Change;
