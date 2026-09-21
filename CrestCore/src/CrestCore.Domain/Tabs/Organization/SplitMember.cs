namespace CrestCore.Domain;

public readonly record struct SplitMember(Guid? Group, TabPlacement Placement, FolderId? Folder);
