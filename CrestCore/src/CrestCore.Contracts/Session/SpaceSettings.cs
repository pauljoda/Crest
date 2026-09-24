namespace CrestCore.Contracts;

/// <summary>
/// What a person chose for a Space apart from its records: its name, look and
/// preferences, who may open it, and whether its saved tabs are expanded.
/// <see cref="Branding"/> is null for a Space stored before branding existed; the
/// native reader derives that look from the accent and symbol.
/// </summary>
[Observed]
public sealed record SpaceSettings(
    string Name,
    string Symbol,
    SpaceAccent Accent,
    SpaceBranding? Branding,
    BrowsingPreferences BrowsingPreferences,
    CredentialPreferences CredentialPreferences,
    SpaceAccessPolicy AccessPolicy,
    bool IsSavedTabsExpanded,
    DateTimeOffset? SavedTabsExpansionModifiedAt);
