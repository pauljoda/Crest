using System.Text;
using System.Text.Json.Nodes;

using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

public sealed class NativeSyncTransaction : IDisposable {
    #region Variables

    internal NativeSyncAuthority Owner { get; }
    /// The queued stage this transaction stages, which commits only while it
    /// is the newest; null for one that always may.
    internal ulong? Sequence { get; }
    /// The queued stage this transaction replaced, queued again if it never
    /// commits.
    internal SyncStager.Request? Superseded { get; set; }
    internal bool IsSealed { get; set; }
    /// The authority's version once it accepted this journal; zero before.
    public ulong Version { get; internal set; }
    private bool completed, committed;
    internal bool IsReadyToCommit => IsSealed && !completed;
    public NativeSyncJournal Journal { get; private set; }
    public byte[]? Materialization { get; private set; }
    internal IReadOnlyList<SpaceDeletionState>? MaterializedSpaceDeletions { get; private set; }

    #endregion

    #region Constructors

    internal NativeSyncTransaction(NativeSyncAuthority owner, ulong? sequence, NativeSyncJournal journal) {
        Owner = owner; Sequence = sequence; Journal = journal;
    }

    #endregion

    #region Actions - Sync

    internal void Build(JsonObject request, NativeSyncOperation operation) {
        request["preferences"] = Journal.Preferences;
        if (operation is NativeSyncOperation.Merge or NativeSyncOperation.Replace) {
            var result = NativeSyncSessionTransition.Prepare(Journal, Encoding.UTF8.GetBytes(request.ToJsonString()), Owner.Session?.Access);
            Journal = result.Journal;
            MaterializedSpaceDeletions = StoredSessionCodec.DecodeSpaceDeletions(result.Materialization["session"]![StoredSessionCodec.Key.SpaceDeletions]);
            Materialization = NativeSyncQuery.Success(result.Materialization);
        } else Journal = Journal.Apply(request);
        _ = Journal.Read();
    }

    /// Stages `session`, deleting each record it lost for the reason `removals`
    /// names for it, else for `reason`, and dating tombstones `now` seconds
    /// since 2001.
    internal void Stage(SessionState session, SyncDeletionReason reason,
        IReadOnlyDictionary<string, SyncDeletionReason> removals, double now) {
        Journal = Journal.Stage(StoredSessionCodec.Encode(session), reason, now, removals);
        _ = Journal.Read();
    }

    public bool Seal() => Owner.Seal(this);

    internal void Commit() {
        lock (NativeSessionAuthority.Gate) {
            // A paired session replacement may already have published this
            // journal under the same core lock as the browser revision.
            if (committed) return;
            if (completed) throw new BrowserRuleException(BrowserRuleCodes.InvalidSyncTransaction);
            Owner.Commit(this); completed = committed = true;
        }
    }

    /// Publishes a sealed journal after saving it, with the newest accepted
    /// session, when its session keeps a file. A journal that a session
    /// replacement already saved and published is left alone. A failed save
    /// leaves the transaction pending for the caller to release.
    public void CommitDurably() {
        lock (NativeSessionAuthority.Gate) {
            if (committed) return;
            if (completed || !IsSealed) throw new BrowserRuleException(BrowserRuleCodes.InvalidSyncTransaction);
        }
        Owner.Session?.Storage?.SaveJournal(Journal);
        Commit();
    }

    public void Dispose() {
        lock (NativeSessionAuthority.Gate) {
            if (completed) return;
            completed = true;
        }
        Owner.Cancel(this);
    }

    #endregion
}
