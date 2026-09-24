namespace CrestCore.Contracts;

/// <summary>A Space's settings now read as <see cref="Settings"/>.</summary>
public sealed record SpaceSettingsChanged(Guid WorkspaceId, Guid SpaceId, SpaceSettings Settings) : Change;
