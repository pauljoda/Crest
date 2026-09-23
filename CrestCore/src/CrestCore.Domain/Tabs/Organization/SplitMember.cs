using CrestCore.Contracts;

namespace CrestCore.Domain;

public readonly record struct SplitMember(Guid? Group, TabPlacement Placement, Guid? Folder);
