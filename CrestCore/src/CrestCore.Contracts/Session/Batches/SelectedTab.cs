namespace CrestCore.Contracts;

/// A tab a selection holds, with where it lives.
public sealed record SelectedTab(Guid Id, TabPlacement Placement, Guid? FolderId, Guid? SplitGroupId);
