namespace CrestCore.Domain;

public sealed class SystemIdSource : IIdSource { public Guid Next() => Guid.NewGuid(); }
