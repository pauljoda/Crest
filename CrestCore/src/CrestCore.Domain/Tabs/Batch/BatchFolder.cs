namespace CrestCore.Domain;

public sealed record BatchFolder(Guid Id, Guid? ParentId, TabPlacement Location);
