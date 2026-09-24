namespace CrestCore.Contracts;

/// <summary>A workspace's app-wide preferences now read as <see cref="Preferences"/>,
/// or as none before they are imported.</summary>
public sealed record AppPreferencesChanged(Guid WorkspaceId, AppPreferences? Preferences) : Change;
