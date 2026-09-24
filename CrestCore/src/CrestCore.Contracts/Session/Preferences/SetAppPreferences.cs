namespace CrestCore.Contracts;

/// Sets the app-wide behavior preferences. The persistent workspace keeps
/// them on this device; they never sync. The translation rules keep to the
/// rule set's own limits.
public sealed record SetAppPreferences(Guid WorkspaceId, AppPreferences Preferences) : SessionIntent(WorkspaceId);
