using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

/// This device's site permission choices. The device store keeps the
/// persistent session's choices, and only on a device with a file; every other
/// Space's choices (private, seeded, or one no attached session holds) live in
/// memory until the process ends. A borrowed workspace shows its owner's
/// Space, so its choices are the owner's. A Space's lock comes from the
/// session that holds it; a Space no session holds has no lock of its own.
/// The Spaces of a group share one session, so they share their choices; see
/// `SitePermissionLedger`.
internal sealed partial class Device {
    #region Variables

    /// The persistent session's choices, which the device store keeps.
    private readonly SitePermissionLedger keptPermissions = new();
    internal SitePermissionLedger KeptPermissions => keptPermissions;
    /// Every other Space's choices, which live as long as the process.
    private readonly SitePermissionLedger passingPermissions = new();
    internal SitePermissionLedger PassingPermissions => passingPermissions;

    #endregion

    #region Actions - Site permission intents

    /// Runs one site permission intent, publishing each Space it changed.
    public void Handle(SitePermissionIntent intent, DeviceTurn turn) => intent.Apply(this, turn);

    #endregion

    #region Actions - Site permission queries

    public SitePermissionAnswer Answer(SiteDecision question) {
        ArgumentNullException.ThrowIfNull(question);
        var (keeps, locked) = ChoiceScope(question.SpaceId);
        var group = PermissionGroups()(question.SpaceId);
        lock (gate)
            return new((keeps ? keptPermissions : passingPermissions).Decision(group, question.Origin, question.Permission,
                question.Detail, locked));
    }

    public SitePermissionAnswer Answer(CaptureDecision question) {
        ArgumentNullException.ThrowIfNull(question);
        var (keeps, locked) = ChoiceScope(question.SpaceId);
        var group = PermissionGroups()(question.SpaceId);
        lock (gate)
            return new((keeps ? keptPermissions : passingPermissions).MediaDecision(group, question.Origin, question.Media, locked));
    }

    #endregion

    #region Actions - Choice scope

    /// Whether the device store keeps `spaceId`'s site permission and engine
    /// choices, and whether this process holds no grant to show the Space. The persistent session is
    /// asked first, since a borrowed workspace holds its Space too. Called
    /// without the device lock, since it reads the sessions.
    internal (bool Keeps, bool Locked) ChoiceScope(Guid spaceId) {
        Guid? persistent;
        KeyValuePair<Guid, NativeSessionAuthority>[] attached;
        lock (gate) {
            persistent = persistentWorkspace;
            attached = [.. workspaces.OrderByDescending(entry => entry.Key == persistent)];
        }
        foreach (var (workspaceId, authority) in attached) {
            if (authority.Current.Space(spaceId) is not { } space) continue;
            return (storage is not null && workspaceId == persistent, authority.IsLocked(space));
        }
        return (false, false);
    }

    /// The Spaces whose choices answer for each Space: the Spaces of its group
    /// that stay, the one that keeps the group's records first, or the Space
    /// alone. Read now from the attached sessions, the persistent one first,
    /// so it is called without the device lock.
    internal Func<Guid, IReadOnlyList<Guid>> PermissionGroups() {
        KeyValuePair<Guid, NativeSessionAuthority>[] attached;
        lock (gate) attached = [.. workspaces.OrderByDescending(entry => entry.Key == persistentWorkspace)];
        var groups = new Dictionary<Guid, IReadOnlyList<Guid>>();
        foreach (var (_, authority) in attached)
            foreach (var group in authority.Current.Groups.Where(group => group.SubSpaces.Count > 0)) {
                IReadOnlyList<Guid> members = [.. group.Members.Select(member => member.Id)];
                foreach (var member in members) groups.TryAdd(member, members);
            }
        return space => groups.GetValueOrDefault(space) ?? [space];
    }

    /// Whether `spaceId` is a private window's Space. Called without the
    /// device lock, since it reads the sessions.
    internal bool IsPrivate(Guid spaceId) {
        NativeSessionAuthority[] attached;
        lock (gate)
            attached = [.. workspaces.Values];
        return attached.Any(authority => authority.IsPrivateBrowsing && authority.Current.Space(spaceId) is not null);
    }

    /// Publishes each Space `outcome` touched, and every other Space of its
    /// group as `groups` gives it, with the choices that answer for it now.
    /// The caller holds the device lock.
    internal void PublishPermissions(SitePermissionOutcome outcome, ChangeFeed changes, Func<Guid, IReadOnlyList<Guid>> groups) {
        foreach (var touched in outcome.Changes.SelectMany(change => groups(change.Space).Select(space => (space, change.Scope)))
            .GroupBy(change => change.space))
            changes.Publish(new SitePermissionsChanged(touched.Key, PermissionRecords(touched.Key, groups),
                [.. touched.Select(change => change.Scope).Distinct()]));
    }

    /// The choices that answer for `space`, as `groups` gives its group, in
    /// the order the settings list them. The caller holds the device lock.
    internal IReadOnlyList<SitePermissionRecordState> PermissionRecords(Guid space, Func<Guid, IReadOnlyList<Guid>> groups) {
        var group = groups(space);
        return [.. keptPermissions.Records(group).Concat(passingPermissions.Records(group)).Order(SitePermissionRecordOrder.Instance)
            .Select(record => record.State)];
    }

    /// `spaceId` joined the group `groupSpaceId` belongs to: where the group
    /// chose for a site already, its choice stands. Called without the device
    /// lock, since it reads the sessions.
    internal void ShareSitePermissions(Guid spaceId, ChangeFeed changes) {
        var groups = PermissionGroups();
        Revise(changes, groups, ledger => ledger.Joining(spaceId, groups(spaceId)));
    }

    /// The Space `successor` names keeps the choices `from`, a primary whose
    /// deletion began, kept for the group it took over. Called without the
    /// device lock, since it reads the sessions.
    internal void HandOverSitePermissions(Guid from, Guid successor, ChangeFeed changes) =>
        Revise(changes, PermissionGroups(), ledger => ledger.HandingOver(from, successor));

    /// A removed Space keeps no choice of its own. Called without the device
    /// lock, since it reads the sessions.
    internal void ForgetSitePermissions(Guid spaceId, ChangeFeed changes) =>
        Revise(changes, PermissionGroups(), ledger => ledger.ResetSpace([spaceId]));

    /// Applies `revise` to both ledgers, saving and publishing what changed.
    private void Revise(ChangeFeed changes, Func<Guid, IReadOnlyList<Guid>> groups, Func<SitePermissionLedger, SitePermissionOutcome> revise) {
        lock (gate) {
            var kept = revise(keptPermissions);
            var passing = revise(passingPermissions);
            if (kept.PersistenceChanged) storage?.EnqueueDevice(Records());
            PublishPermissions(new(kept.PersistenceChanged, [.. kept.Changes.Concat(passing.Changes).Distinct()]), changes, groups);
        }
    }

    #endregion
}
