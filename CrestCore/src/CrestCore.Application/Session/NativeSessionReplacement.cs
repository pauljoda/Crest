using CrestCore.Contracts;

namespace CrestCore.Application;

/// A validated revision reserved while it is saved. Other writers are
/// refused until it is committed or disposed; disposing an uncommitted
/// reservation leaves the session as it was.
internal sealed class NativeSessionReplacement : IDisposable {
    #region Variables

    private readonly NativeSessionAuthority owner;
    private bool completed;
    internal SessionState Session { get; }
    internal ulong Revision { get; }
    internal ulong? BorrowedSourceRevision { get; }
    internal Guid? TransientCompletion { get; }
    internal NativeSessionCheckpoint Checkpoint { get; }
    internal NativeSyncTransaction? SyncTransaction { get; private set; }

    #endregion

    #region Constructors

    internal NativeSessionReplacement(NativeSessionAuthority owner, SessionState session,
        ulong revision, NativeSessionCheckpoint checkpoint, ulong? borrowedSourceRevision = null, Guid? transientCompletion = null) {
        this.owner = owner; Session = session; Revision = revision; Checkpoint = checkpoint;
        BorrowedSourceRevision = borrowedSourceRevision;
        TransientCompletion = transientCompletion;
    }

    #endregion

    #region Actions - Replacement

    internal void BindSync(NativeSyncTransaction value) {
        lock (NativeSessionAuthority.Gate) {
            if (completed || SyncTransaction is not null || !value.IsReadyToCommit || !ReferenceEquals(value.Owner.Session, owner))
                throw new CrestCore.Domain.BrowserRuleException(CrestCore.Domain.BrowserRuleCodes.InvalidSyncSessionOwner);
            SyncTransaction = value;
        }
    }

    internal ulong Commit() {
        lock (NativeSessionAuthority.Gate) {
            if (completed) throw new CrestCore.Domain.BrowserRuleException(CrestCore.Domain.BrowserRuleCodes.InvalidSessionTransaction);
            var revision = owner.CompleteReplacement(this, true);
            completed = true;
            return revision;
        }
    }

    public void Dispose() {
        lock (NativeSessionAuthority.Gate) {
            if (completed) return;
            owner.CompleteReplacement(this, false);
            completed = true;
        }
    }

    #endregion
}
