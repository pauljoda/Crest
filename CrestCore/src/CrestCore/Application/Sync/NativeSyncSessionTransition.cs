using System.Text.Json.Nodes;

using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

/// Prepares the session and journal together. Local edits stage before incoming
/// records; repair and retention finish before either resulting value is returned.
/// Publication and durable storage must accept this pair together.
public sealed record NativeSyncSessionTransition {
    #region Variables

    private readonly JsonObject? legacyLocal;

    public NativeSyncJournal Journal { get; }
    internal SessionState Session { get; }
    internal IReadOnlyList<NativeSessionMaintenance.TabOrigin> Origins { get; }

    /// The legacy native checkpoint answer, encoded only when the caller needs
    /// that boundary. In-process convergence uses Session and Origins directly.
    public JsonObject Materialization => NativeSyncCheckpointCodec.Encode(Session, Origins, legacyLocal);

    #endregion

    #region Constructors

    private NativeSyncSessionTransition(NativeSyncJournal journal, SessionState session,
        IReadOnlyList<NativeSessionMaintenance.TabOrigin> origins, JsonObject? legacyLocal = null) {
        Journal = journal;
        Session = session;
        Origins = origins;
        this.legacyLocal = legacyLocal;
    }

    #endregion

    #region Actions - Sync

    internal static NativeSyncSessionTransition Prepare(NativeSyncJournal journal, JsonObject local, JsonArray incoming,
        bool replacing, double now, JsonObject? emptySpace, SpaceAccessAuthority? access, IIdSource? ids,
        IReadOnlyDictionary<string, SyncDeletionReason>? removals = null, IReadOnlySet<string>? emptied = null) {
        var prepared = Prepare(journal, StoredSessionCodec.DecodeSession(local), incoming, replacing, StoredSessionCodec.Date(now),
            emptySpace is null ? null : StoredSessionCodec.DecodeSpace(emptySpace), access, ids ?? new SystemIdSource(), removals, emptied);
        return new(prepared.Journal, prepared.Session, prepared.Origins, local.DeepClone().AsObject());
    }

    /// Stage local edits, accept incoming records, materialize and repair a typed
    /// session, retaining local deletion work and device preferences throughout.
    internal static NativeSyncSessionTransition Prepare(NativeSyncJournal journal, SessionState local, JsonArray incoming,
        bool replacing, DateTimeOffset now, SpaceState? emptySpace, SpaceAccessAuthority? access, IIdSource ids,
        IReadOnlyDictionary<string, SyncDeletionReason>? removals = null, IReadOnlySet<string>? emptied = null) {
        var seconds = StoredSessionCodec.Seconds(now);
        var next = journal;
        if (!replacing && local.DisposableSeedMarker is null)
            next = next.Stage(StoredSessionCodec.Encode(local), SyncDeletionReason.Superseded, seconds, removals, emptied);
        next = replacing ? next.Replace(incoming) : next.Merge(incoming);
        var records = NativeSyncEvaluator.Reconcile(next.Records).Select(record => SyncSessionRecord.Read(record!.AsObject())).ToArray();
        // Only accepted explicit Space tombstones authorize erasing a local
        // profile. Cleanup remains pending until that device acknowledges it.
        var pending = local.SpaceDeletions.ToList();
        var pendingIds = pending.Select(deletion => deletion.SpaceId).ToHashSet();
        var deleted = records.Where(record => record.Kind == SyncRecordKind.Space && record.Tombstone?.Reason.IsExplicit == true)
            .Select(record => local.Space(record.Id)).OfType<SpaceState>().ToDictionary(space => space.Id);
        // Hold the deleted Spaces and their group data until any successor
        // chosen by the sender reaches us. A tombstone may arrive first.
        pending.AddRange(deleted.Values.Where(space => !pendingIds.Contains(space.Id))
            .Select(space => new SpaceDeletionState(Guid.NewGuid(), space.Id, space.OwnProfileId, [])));
        local = local with { SpaceDeletions = pending };
        var policy = NativeSyncProjection.Preferences(journal.Preferences);
        var raw = replacing && incoming.Count == 0 ? local with { Spaces = [], DisposableSeedMarker = null }
            : NativeSyncMaterializer.Materialize(local, policy, records, now, access);
        raw = ApplyingArrivedHandovers(raw, deleted.Values.Where(space => local.PendingDeletion(space.Id)?.SuccessorId is null),
            policy, records);
        var repaired = NativeSessionMaintenance.Repair(raw, now, emptySpace, ids, out var origins);
        repaired = NativeSessionMaintenance.Retain(repaired, now, out var removed);
        if (pending.Count > 0) {
            pending = repaired.SpaceDeletions.ToList();
            var spaces = repaired.Spaces.ToList();
            foreach (var intent in pending) {
                if (!spaces.Any(space => space.Id == intent.SpaceId)) spaces.Add(local.KnownSpace(intent.SpaceId));
            }
            repaired = repaired with { Spaces = spaces, SpaceDeletions = pending };
            for (int index = 0; index < pending.Count; index++) {
                var intent = pending[index];
                if (intent.SuccessorId is not null || !deleted.TryGetValue(intent.SpaceId, out var space)) continue;
                var successor = repaired.CredentialSuccessor(space);
                if (!pendingIds.Contains(space.Id) || successor is not null)
                    pending[index] = repaired.Deleting(space, intent.Id) with { SuccessorId = successor };
            }
            repaired = (repaired with { SpaceDeletions = pending }).PreservingDeletionProfiles();
        }
        repaired = repaired with { AppPreferences = local.AppPreferences };
        // A folder of the open tabs that another device emptied arrives marked,
        // and stays out of sight here while it holds nothing. Records can
        // arrive over several batches, so nothing here clears or deletes a
        // folder: the tab that keeps it may not have arrived yet.
        if (!replacing || removed)
            next = next.Stage(StoredSessionCodec.Encode(repaired), removed ? SyncDeletionReason.Retention : SyncDeletionReason.Superseded, seconds);
        return new(next, repaired, origins);
    }

    #endregion

    #region Actions - Handover

    /// If the sender already named a successor, keep it even when some
    /// children still arrive naming the old primary, and move the shared pins
    /// that have yet to arrive. Use the sender's time for inferred changes.
    private static SessionState ApplyingArrivedHandovers(SessionState raw, IEnumerable<SpaceState> deleted,
        SyncPreferences policy, IReadOnlyList<SyncSessionRecord> records) {
        var tombstonedTabs = policy.Includes(TabPlacement.Pinned)
            ? records.Where(record => record.Kind == SyncRecordKind.Tab && record.Tombstone is not null)
                .Select(record => record.Id).ToHashSet()
            : [];
        foreach (var former in deleted) {
            if (raw.CredentialSuccessor(former) is not { } successorId) continue;
            // The pending primary still holds its pre-merge tabs. Honor
            // accepted tombstones for shared pins that sync on this device.
            var source = tombstonedTabs.Count == 0 || former.Settings.SeparatesPinnedTabs ? former : former with {
                Tabs = former.Tabs.Where(tab => !tab.IsPinned || !tombstonedTabs.Contains(tab.Id)
                    || !NativeSyncMaterializer.Portable(tab)).ToArray()
            };
            var (departing, successor) = SpaceGroup.HandingOverPins(source, raw.KnownSpace(successorId));
            var handoverTime = successor.Membership!.ModifiedAt;
            var children = raw.StayingSpaces.Where(space => space.PrimaryId == former.Id).Select(space => {
                var childTime = space.Membership!.ModifiedAt;
                var modifiedAt = childTime > handoverTime ? childTime : handoverTime;
                return space with { Membership = SpaceMembership.Joining(successor, modifiedAt) };
            });
            raw = raw.Replacing([departing, successor, .. children]);
        }
        return raw;
    }

    #endregion

}
