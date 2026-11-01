using CrestCore.Contracts;

namespace CrestCore.Domain;

/// <summary>
/// A setting every Space of a group shares. Each member keeps a copy with the time
/// someone chose it; an edit of one copy changes every copy, and when copies drift apart
/// through sync the latest choice wins across the group. Among equal times a setting
/// that guards something keeps the guarded side, and any other follows the primary.
/// </summary>
internal sealed class GroupSetting {
    #region Static Variables

    /// Who may open the group's Spaces. A lock set anywhere in the group wins a tie.
    public static readonly GroupSetting Lock = new(
        chosenAt: settings => settings.AccessPolicyModifiedAt,
        copy: (from, to) => to with { AccessPolicy = from.AccessPolicy, AccessPolicyModifiedAt = from.AccessPolicyModifiedAt },
        guards: settings => settings.RequiresAuthentication);

    /// Whether the group offers to save and fill passwords, and where this
    /// device keeps them.
    public static readonly GroupSetting CrestPasswords = new(
        chosenAt: settings => settings.CredentialsEnabledModifiedAt,
        copy: (from, to) => to with {
            CredentialPreferences = from.CredentialPreferences,
            CredentialsEnabledModifiedAt = from.CredentialsEnabledModifiedAt
        });

    /// How the group blocks content and how long it keeps what it browses.
    public static readonly GroupSetting Protection = new(
        chosenAt: settings => settings.ProtectionModifiedAt,
        copy: (from, to) => to with {
            BrowsingPreferences = to.BrowsingPreferences with {
                ContentBlocking = from.BrowsingPreferences.ContentBlocking,
                DataRetention = from.BrowsingPreferences.DataRetention
            },
            ProtectionModifiedAt = from.ProtectionModifiedAt
        });

    /// Whether each Sub-Space shows the pinned tabs stored in it instead of the
    /// primary's.
    public static readonly GroupSetting PinnedTabs = new(
        chosenAt: settings => settings.SeparatesPinnedTabsModifiedAt,
        copy: (from, to) => to with {
            SeparatesPinnedTabs = from.SeparatesPinnedTabs,
            SeparatesPinnedTabsModifiedAt = from.SeparatesPinnedTabsModifiedAt
        });

    public static IReadOnlyList<GroupSetting> All { get; } = [Lock, CrestPasswords, Protection, PinnedTabs];

    #endregion

    #region Variables

    private readonly Func<SpaceSettings, DateTimeOffset?> chosenAt;
    private readonly Func<SpaceSettings, SpaceSettings, SpaceSettings> copy;
    private readonly Func<SpaceSettings, bool>? guards;

    #endregion

    #region Constructors

    private GroupSetting(Func<SpaceSettings, DateTimeOffset?> chosenAt, Func<SpaceSettings, SpaceSettings, SpaceSettings> copy,
        Func<SpaceSettings, bool>? guards = null) {
        this.chosenAt = chosenAt;
        this.copy = copy;
        this.guards = guards;
    }

    #endregion

    #region Actions - Groups

    /// `to` with this setting as `from` holds it.
    internal SpaceSettings Copied(SpaceSettings from, SpaceSettings to) => copy(from, to);

    /// The member whose copy the group takes, of `members` with the primary
    /// first: the one chosen latest; among equal times, the first on the
    /// guarded side when this setting guards something, otherwise the first.
    internal SpaceState Source(IReadOnlyList<SpaceState> members) {
        var latest = members.Max(member => chosenAt(member.Settings));
        var candidates = members.Where(member => chosenAt(member.Settings) == latest).ToList();
        return guards is { } guarded ? candidates.FirstOrDefault(member => guarded(member.Settings)) ?? candidates[0] : candidates[0];
    }

    /// `members` of a group, primary first, with every shared setting settled
    /// to its source's copy, in order; a member that needs no change is the
    /// same object.
    internal static IReadOnlyList<SpaceState> Settled(IReadOnlyList<SpaceState> members) {
        var settled = members.ToList();
        foreach (var setting in All) {
            var source = setting.Source(settled);
            for (var index = 0; index < settled.Count; index++)
                if (settled[index].Id != source.Id)
                    settled[index] = settled[index].Configured(setting.Copied(source.Settings, settled[index].Settings));
        }
        return settled;
    }

    #endregion
}
