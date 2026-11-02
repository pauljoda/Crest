namespace CrestCore.Contracts;

/// <summary>
/// What a person chose for a Space apart from its records: its name, look and
/// preferences, who may open it, and whether its saved tabs are expanded.
/// <see cref="CredentialsEnabledModifiedAt"/> is when the person last turned
/// Crest Passwords on or off for the Space, on any device, or null when nobody has.
/// <see cref="AccessPolicyModifiedAt"/> is when the person last turned the Space's lock
/// on or off, on any device, or null when nobody has since Crest kept that time.
/// <see cref="SeparatesPinnedTabs"/> is whether the Sub-Spaces of the Space's group each
/// show the pinned tabs stored in them instead of the primary's, and
/// <see cref="SeparatesPinnedTabsModifiedAt"/> when someone chose.
/// <see cref="ProtectionModifiedAt"/> is when someone last changed how the Space blocks
/// content or how long it keeps what it browses, or null when nobody has since Crest
/// kept that time.
/// <see cref="Branding"/> is null for a Space stored before branding existed, which
/// wears the look its accent and symbol give it; <see cref="Look"/> is what it wears.
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
    DateTimeOffset? SavedTabsExpansionModifiedAt,
    DateTimeOffset? CredentialsEnabledModifiedAt = null,
    DateTimeOffset? AccessPolicyModifiedAt = null,
    bool SeparatesPinnedTabs = false,
    DateTimeOffset? SeparatesPinnedTabsModifiedAt = null,
    DateTimeOffset? ProtectionModifiedAt = null) {
    #region Variables

    /// <summary>The branding the Space wears: its own, with a banner strength stored
    /// before the baseline vocabulary in today's units, or for a Space stored before
    /// branding existed, the legacy look of its accent and symbol.</summary>
    [Resolved]
    public SpaceBranding Look => Branding?.InTodaysUnits() ?? SpaceBranding.Legacy(Accent, Symbol);

    /// <summary>The Space shows only while this process holds the grant for its
    /// profile. A policy this build cannot name reads as guarded (see
    /// `StoredSessionCodec`), so only an open Space skips authentication.</summary>
    [Resolved]
    public bool RequiresAuthentication => AccessPolicy != SpaceAccessPolicy.Open;

    #endregion

    #region Actions - Choices

    /// When a new choice is made: now, or a second after the choice it
    /// replaces when this device's clock is behind the one that made it, so
    /// the newer choice always wins a merge.
    internal static DateTimeOffset Chosen(DateTimeOffset? replaced, DateTimeOffset now) =>
        replaced is { } earlier && earlier >= now ? earlier.AddSeconds(1) : now;

    #endregion
}
