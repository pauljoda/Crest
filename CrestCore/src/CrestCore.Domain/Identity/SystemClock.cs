namespace CrestCore.Domain;

public sealed class SystemClock : IClock { public DateTimeOffset Now => DateTimeOffset.UtcNow; }
