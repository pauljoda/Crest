using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

/// This device's site permission choices. The device store keeps the
/// persistent session's choices, and only on a device with a file; every other
/// Space's choices (private, seeded, or one no attached session holds) live in
/// memory until the process ends. A borrowed workspace shows its owner's
/// Space, so its choices are the owner's. A Space's lock comes from the
/// session that holds it; a Space no session holds has no lock of its own.
internal sealed partial class Device {
    #region Variables

    /// The persistent session's choices, which the device store keeps.
    private readonly SitePermissionLedger keptPermissions = new();
    /// Every other Space's choices, which live as long as the process.
    private readonly SitePermissionLedger passingPermissions = new();

    #endregion

    #region Actions - Site permission intents

    /// Runs one site permission intent, publishing each Space it changed.
    public void Handle(SitePermissionIntent intent, ChangeFeed changes, DateTimeOffset now, IIdSource ids) {
        ArgumentNullException.ThrowIfNull(intent);
        ArgumentNullException.ThrowIfNull(changes);
        ArgumentNullException.ThrowIfNull(ids);
        switch (intent) {
            case AdoptSitePermissions adoption: Adopt(adoption, changes); break;
            case DecideSitePermission decision: Decide(decision, changes, now, ids); break;
            case ResetSitePermission reset: Reset(reset, changes); break;
            case ResetSpacePermissions reset: Reset(reset, changes); break;
            default: throw new ArgumentOutOfRangeException(nameof(intent), intent.GetType().Name, "The device does not handle this intent.");
        }
    }

    /// Carries the choices an installed release kept into the device store
    /// once, merged after any the store already holds, and saves them before
    /// returning. Every call publishes each Space that holds a choice.
    private void Adopt(AdoptSitePermissions intent, ChangeFeed changes) {
        lock (gate) {
            if (storage is { } target && !adopted.Contains(DeviceAdoption.SitePermissions)) {
                var merged = new SitePermissionLedger();
                merged.Restore([.. keptPermissions.PersistentRecords, .. SitePermissionDocument.Read(intent.Records)]);
                var carried = Records().Adopting(DeviceAdoption.SitePermissions) with { SitePermissions = merged.PersistentRecords };
                try {
                    target.SaveDevice(carried);
                } catch (StorageException error) {
                    throw new Rejected(new SaveFailed(error.Reason));
                }
                keptPermissions.Restore(carried.SitePermissions);
                adopted.Add(DeviceAdoption.SitePermissions);
                // Records handed to the store before this carry nothing adopted; these supersede them.
                target.EnqueueDevice(Records());
            }
            foreach (var space in keptPermissions.Spaces.Union(passingPermissions.Spaces))
                changes.Publish(new SitePermissionsChanged(space, PermissionRecords(space), []));
        }
    }

    private void Decide(DecideSitePermission intent, ChangeFeed changes, DateTimeOffset now, IIdSource ids) {
        var (keeps, locked) = PermissionScope(intent.SpaceId);
        if (locked) throw new Rejected(new SpaceLocked(intent.SpaceId));
        lock (gate) {
            var outcome = (keeps ? keptPermissions : passingPermissions).Set(intent.SpaceId, intent.Origin, intent.Permission, intent.Detail,
                intent.Decision, ids.Next(), StoredSessionCodec.Seconds(now));
            if (keeps && outcome.PersistenceChanged) storage?.EnqueueDevice(Records());
            PublishPermissions(outcome, changes);
        }
    }

    private void Reset(ResetSitePermission intent, ChangeFeed changes) {
        lock (gate) {
            var kept = keptPermissions.ResetRecord(intent.RecordId);
            if (kept.PersistenceChanged) storage?.EnqueueDevice(Records());
            PublishPermissions(kept.Changes.Count > 0 ? kept : passingPermissions.ResetRecord(intent.RecordId), changes);
        }
    }

    private void Reset(ResetSpacePermissions intent, ChangeFeed changes) {
        lock (gate) {
            var kept = keptPermissions.ResetSpace(intent.SpaceId);
            var passing = passingPermissions.ResetSpace(intent.SpaceId);
            if (kept.PersistenceChanged) storage?.EnqueueDevice(Records());
            PublishPermissions(new SitePermissionOutcome(kept.PersistenceChanged, [.. kept.Changes.Concat(passing.Changes).Distinct()]), changes);
        }
    }

    #endregion

    #region Actions - Site permission queries

    public SitePermissionAnswer Answer(SiteDecision question) {
        ArgumentNullException.ThrowIfNull(question);
        var (keeps, locked) = PermissionScope(question.SpaceId);
        lock (gate)
            return new((keeps ? keptPermissions : passingPermissions).Decision(question.SpaceId, question.Origin, question.Permission,
                question.Detail, locked));
    }

    public SitePermissionAnswer Answer(CaptureDecision question) {
        ArgumentNullException.ThrowIfNull(question);
        var (keeps, locked) = PermissionScope(question.SpaceId);
        lock (gate)
            return new((keeps ? keptPermissions : passingPermissions).MediaDecision(question.SpaceId, question.Origin, question.Media,
                locked));
    }

    #endregion

    #region Actions - Site permission scope

    /// Whether the device store keeps `spaceId`'s choices, and whether this
    /// process holds no grant to show the Space. The persistent session is
    /// asked first, since a borrowed workspace holds its Space too. Called
    /// without the device lock, since it reads the sessions.
    private (bool Keeps, bool Locked) PermissionScope(Guid spaceId) {
        Guid? persistent;
        KeyValuePair<Guid, NativeSessionAuthority>[] attached;
        lock (gate) {
            persistent = persistentWorkspace;
            attached = [.. workspaces.OrderByDescending(entry => entry.Key == persistent)];
        }
        foreach (var (workspaceId, authority) in attached) {
            if (authority.Current.Spaces.FirstOrDefault(space => space.Id == spaceId) is not { } space) continue;
            return (storage is not null && workspaceId == persistent, authority.IsLocked(space));
        }
        return (false, false);
    }

    /// Publishes each Space `outcome` touched with the choices it keeps now.
    /// The caller holds the device lock.
    private void PublishPermissions(SitePermissionOutcome outcome, ChangeFeed changes) {
        foreach (var touched in outcome.Changes.GroupBy(change => change.Space))
            changes.Publish(new SitePermissionsChanged(touched.Key, PermissionRecords(touched.Key), [.. touched.Select(change => change.Scope)]));
    }

    /// The choices `space` keeps, in the order the settings list them. The
    /// caller holds the device lock.
    private IReadOnlyList<SitePermissionRecordState> PermissionRecords(Guid space) =>
        [.. keptPermissions.Records(space).Concat(passingPermissions.Records(space)).Order(SitePermissionRecordOrder.Instance)
            .Select(record => record.State)];

    #endregion
}
