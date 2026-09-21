namespace CrestCore.Domain;

public readonly record struct WorkspaceId(Guid Value);
public readonly record struct SpaceId(Guid Value);
public readonly record struct ProfileId(Guid Value);
public readonly record struct TabId(Guid Value);
public readonly record struct WindowId(Guid Value);
public readonly record struct PageId(Guid Value);
public readonly record struct FolderId(Guid Value);

public interface IIdSource { Guid Next(); }
public interface IClock { DateTimeOffset Now { get; } }
public sealed class SystemIdSource : IIdSource { public Guid Next() => Guid.NewGuid(); }
public sealed class SystemClock : IClock { public DateTimeOffset Now => DateTimeOffset.UtcNow; }

public sealed class BrowserRuleException(string code) : Exception(code) {
    public string Code { get; } = code;
}
