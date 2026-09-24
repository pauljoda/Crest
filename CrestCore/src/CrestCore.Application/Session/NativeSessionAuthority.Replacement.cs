using CrestCore.Contracts;

namespace CrestCore.Application;

public sealed partial class NativeSessionAuthority {
    #region Variables

    private NativeSyncAuthority? sync;

    #endregion

    #region Actions - Replacement

    public void AttachSync(NativeSyncAuthority value) {
        lock (Gate) {
            if (workspaceKind != CrestCore.Domain.BrowserWorkspaceKind.Persistent
                || sync is not null && !ReferenceEquals(sync, value)
                || value.Session is not null && !ReferenceEquals(value.Session, this))
                throw new CrestCore.Domain.BrowserRuleException(CrestCore.Domain.BrowserRuleCodes.InvalidSyncSessionOwner);
            sync = value; value.Session = this;
        }
    }

    /// Reserves a validated revision while the platform commits durable storage.
    /// Other writes are rejected until commit or cancellation. No platform I/O
    /// occurs under the core lock, and cancellation leaves the authority intact.
    public NativeSessionReplacement ReserveReplacement(ulong expected, ReadOnlySpan<byte> delta,
        NativeSyncTransaction? transaction = null, bool nativeValueEdit = false) {
        lock (Gate) {
            IReadOnlyList<CrestCore.Contracts.SpaceDeletionState>? authorizedDeletions = null;
            if (transaction is not null) {
                if (!transaction.IsReadyToCommit || !ReferenceEquals(transaction.Owner.Session, this) || transaction.Materialization is null)
                    throw new CrestCore.Domain.BrowserRuleException(CrestCore.Domain.BrowserRuleCodes.InvalidSyncSessionOwner);
                authorizedDeletions = transaction.MaterializedSpaceDeletions;
            }
            var next = Prepare(expected, delta, authorizedDeletions, nativeValueEdit && transaction is null);
            var nextRevision = checked(Revision + 1);
            var checkpoint = new NativeSessionCheckpoint(next);
            // Validate serialization before granting the lease.
            _ = checkpoint.Read(NativeSessionCheckpoint.CorePart);
            var reserved = new NativeSessionReplacement(this, next, nextRevision, checkpoint);
            if (transaction is not null) reserved.BindSync(transaction);
            replacement = reserved;
            return replacement;
        }
    }

    internal ulong CompleteReplacement(NativeSessionReplacement value, bool commit) {
        lock (Gate) {
            if (!ReferenceEquals(replacement, value))
                throw new CrestCore.Domain.BrowserRuleException(CrestCore.Domain.BrowserRuleCodes.InvalidSessionTransaction);
            if (commit) {
                value.SyncTransaction?.Commit();
                session = value.Session; Revision = value.Revision;
                borrowedSourceRevision = value.BorrowedSourceRevision ?? borrowedSourceRevision;
                if (value.TransientCompletion is { } completed) completedTransients.Add(completed);
            }
            replacement = null;
            return Revision;
        }
    }

    internal NativeSessionReplacement ReserveCommand(NativeSessionCommand command) {
        lock (Gate) {
            RequireWritable(requireCurrentBorrowedPolicy: false);
            command.RequireAccepted();
            if (command.ExpectedRevision != Revision)
                throw new CrestCore.Domain.BrowserRuleException(CrestCore.Domain.BrowserRuleCodes.StaleSessionRevision);
            var nextRevision = checked(Revision + 1);
            var checkpoint = new NativeSessionCheckpoint(command.Session);
            _ = checkpoint.Read(NativeSessionCheckpoint.CorePart);
            replacement = new(this, command.Session, nextRevision, checkpoint, command.BorrowedSourceRevision, command.TransientCompletion);
            return replacement;
        }
    }

    #endregion
}
