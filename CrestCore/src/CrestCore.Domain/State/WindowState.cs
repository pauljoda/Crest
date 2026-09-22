namespace CrestCore.Domain;

public sealed record WindowState(Guid Id, Guid SpaceId, IReadOnlyDictionary<Guid, Guid?> Selections,
    string? PlatformSceneId = null);
