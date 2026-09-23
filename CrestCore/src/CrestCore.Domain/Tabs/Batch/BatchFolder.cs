using CrestCore.Contracts;

namespace CrestCore.Domain;

public sealed record BatchFolder(Guid Id, Guid? ParentId, TabPlacement Location);
