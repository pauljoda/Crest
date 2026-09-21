namespace CrestCore.Domain;

public sealed record WindowState(WindowId Id, SpaceId SpaceId, IReadOnlyDictionary<SpaceId, TabId?> Selections,
    string? PlatformSceneId = null);
