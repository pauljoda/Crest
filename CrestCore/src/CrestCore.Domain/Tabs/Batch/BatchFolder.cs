namespace CrestCore.Domain;

public sealed record BatchFolder(FolderId Id, FolderId? ParentId, TabPlacement Location);
