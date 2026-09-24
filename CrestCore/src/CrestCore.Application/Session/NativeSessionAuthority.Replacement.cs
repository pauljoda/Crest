using CrestCore.Contracts;

namespace CrestCore.Application;

public sealed partial class NativeSessionAuthority {
    #region Variables

    private NativeSyncAuthority? sync;

    /// The file this session keeps, for the saves a sync journal or a
    /// workspace transfer makes on its behalf; null in memory.
    internal SessionStorage? Storage => storage;

    #endregion

    #region Actions - Replacement

    public void AttachSync(NativeSyncAuthority value) {
        lock (Gate) {
            if (workspaceKind != WorkspaceKind.Persistent
                || sync is not null && !ReferenceEquals(sync, value)
                || value.Session is not null && !ReferenceEquals(value.Session, this))
                throw new CrestCore.Domain.BrowserRuleException(CrestCore.Domain.BrowserRuleCodes.InvalidSyncSessionOwner);
            sync = value; value.Session = this;
        }
    }

    /// Reserves a validated revision while it is saved. Other writes are
    /// rejected until commit or cancellation. No I/O occurs under the core
    /// lock, and cancellation leaves the authority intact.
    internal NativeSessionReplacement ReserveReplacement(ReadOnlySpan<byte> delta,
        NativeSyncTransaction? transaction = null, bool nativeValueEdit = false) {
        lock (Gate) {
            IReadOnlyList<CrestCore.Contracts.SpaceDeletionState>? authorizedDeletions = null;
            if (transaction is not null) {
                if (!transaction.IsReadyToCommit || !ReferenceEquals(transaction.Owner.Session, this) || transaction.Materialization is null)
                    throw new CrestCore.Domain.BrowserRuleException(CrestCore.Domain.BrowserRuleCodes.InvalidSyncSessionOwner);
                authorizedDeletions = transaction.MaterializedSpaceDeletions;
            }
            var next = Prepare(delta, authorizedDeletions, nativeValueEdit && transaction is null);
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

    /// Ends a reservation, accepting its state when `commit`, and answers the
    /// state it replaced; null when it is cancelled.
    internal SessionState? CompleteReplacement(NativeSessionReplacement value, bool commit) {
        lock (Gate) {
            if (!ReferenceEquals(replacement, value))
                throw new CrestCore.Domain.BrowserRuleException(CrestCore.Domain.BrowserRuleCodes.InvalidSessionTransaction);
            SessionState? previous = null;
            if (commit) {
                value.SyncTransaction?.Commit();
                previous = session;
                session = value.Session; Revision = value.Revision;
                if (value.TransientCompletion is { } completed) completedTransients.Add(completed);
                storage?.Enqueue(session, Revision);
            }
            replacement = null;
            return previous;
        }
    }

    /// Commits a prepared command with `durability`. A sync transaction's
    /// journal is saved and published with it, so a command that carries one
    /// must wait for disk.
    internal void Commit(NativeSessionCommand command, Durability durability, NativeSyncTransaction? transaction) {
        if (!durability.WaitsForDisk) {
            if (transaction is not null) throw new ArgumentException("A command that carries a journal waits for disk.", nameof(durability));
            CommitCommand(command);
            return;
        }
        NativeSessionReplacement reserved;
        lock (Gate) {
            reserved = ReserveCommand(command);
            try {
                if (transaction is not null) reserved.BindSync(transaction);
            } catch {
                reserved.Dispose();
                throw;
            }
        }
        SaveAndCommit(reserved);
    }

    /// Replaces the session with the edits `delta` names and saves the result,
    /// with a sync transaction's journal when one is given, before publishing
    /// it. A failed save leaves the accepted state and the file unchanged.
    public void ReplaceDurably(ReadOnlySpan<byte> delta, NativeSyncTransaction? transaction = null) =>
        SaveAndCommit(ReserveReplacement(delta, transaction, nativeValueEdit: transaction is null));

    /// Saves a reserved state, then publishes it. No lock is held while the
    /// file is written, and other writers stay excluded by the reservation.
    private void SaveAndCommit(NativeSessionReplacement reserved) {
        try {
            storage?.Save(reserved.Session, reserved.Revision, reserved.SyncTransaction?.Journal, reserved.Checkpoint);
        } catch {
            reserved.Dispose();
            throw;
        }
        reserved.Commit();
    }

    /// Reserves a prepared command's state while it is saved. Throws `Rejected`
    /// with `StaleCommand` when the session accepted anything after the
    /// command was prepared.
    internal NativeSessionReplacement ReserveCommand(NativeSessionCommand command) {
        lock (Gate) {
            RequireWritable(requireCurrentBorrowedPolicy: false);
            command.RequireAccepted(session);
            var nextRevision = checked(Revision + 1);
            var checkpoint = new NativeSessionCheckpoint(command.Session);
            _ = checkpoint.Read(NativeSessionCheckpoint.CorePart);
            replacement = new(this, command.Session, nextRevision, checkpoint, command.TransientCompletion, command.FollowUp,
                command.Events);
            return replacement;
        }
    }

    #endregion
}
