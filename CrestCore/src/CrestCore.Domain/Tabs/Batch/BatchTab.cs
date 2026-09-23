using CrestCore.Contracts;

namespace CrestCore.Domain;

public sealed record BatchTab(Guid Id, TabPlacement Placement, Guid? FolderId, Guid? SplitGroupId);
