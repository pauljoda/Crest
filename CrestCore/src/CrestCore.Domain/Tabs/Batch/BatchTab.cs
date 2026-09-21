namespace CrestCore.Domain;

public sealed record BatchTab(TabId Id, TabPlacement Placement, FolderId? FolderId, Guid? SplitGroupId);
