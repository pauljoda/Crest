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
    /// What the command chose for the window that issued it to show next.
    internal WindowFollowUp? FollowUp { get; }
    internal NativeSessionCheckpoint Checkpoint { get; }
    internal NativeSyncTransaction? SyncTransaction { get; private set; }

    #endregion

    #region Constructors

    internal NativeSessionReplacement(NativeSessionAuthority owner, SessionState session,
        ulong revision, NativeSessionCheckpoint checkpoint, ulong? borrowedSourceRevision = null, Guid? transientCompletion = null,
        WindowFollowUp? followUp = null) {
        this.owner = owner; Session = session; Revision = revision; Checkpoint = checkpoint;
        BorrowedSourceRevision = borrowedSourceRevision;
        TransientCompletion = transientCompletion;
        FollowUp = followUp;
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

    /// Publishes the reserved revision, then tells the device.
    internal ulong Commit() {
        var revision = Complete();
        owner.Published(Session, FollowUp);
        return revision;
    }

    /// Publishes the reserved revision. The caller tells the device once it
    /// holds no lock.
    internal ulong Complete() {
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
