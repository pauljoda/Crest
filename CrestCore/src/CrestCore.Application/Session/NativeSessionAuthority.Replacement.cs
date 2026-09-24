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

    /// Makes `value` this session's sync component. The first time, it stages
    /// the session as it is, as a launch does.
    internal void AttachSync(NativeSyncAuthority value) {
        SessionState? attached = null;
        lock (Gate) {
            if (!workspaceKind.KeepsFile
                || sync is not null && !ReferenceEquals(sync, value)
                || value.Session is not null && !ReferenceEquals(value.Session, this))
                throw new CrestCore.Domain.BrowserRuleException(CrestCore.Domain.BrowserRuleCodes.InvalidSyncSessionOwner);
            if (sync is null) attached = session;
            sync = value; value.Session = this;
        }
        if (attached is { DisposableSeedMarker: null }) value.Queue(attached, attached, SyncStaging.Launch);
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

    /// Commits a prepared command as its staging says. A command that stages
    /// with its save is saved with its journal before either is published and
    /// before this returns; a failed save or stage leaves the session, the
    /// journal and the file as they were. Any other command is saved behind
    /// and staged on the sync worker.
    internal void Commit(NativeSessionCommand command) {
        if (command.Staging is not { Urgency.StagesWithSave: true } staging) {
            CommitCommand(command);
            return;
        }
        var reserved = ReserveCommand(command);
        NativeSyncTransaction? staged;
        try {
            staged = StageWithSave(command.Base, command.Session, staging.Reason);
            if (staged is not null) reserved.BindSync(staged);
        } catch {
            reserved.Dispose();
            throw;
        }
        try {
            SaveAndCommit(reserved);
        } catch {
            staged?.Dispose();
            throw;
        }
        staged?.Owner.AnnounceStaged();
    }

    /// The sealed journal `next`, made from `previous`, stages with its save,
    /// or null when no sync is attached or `next` is a disposable seed, which
    /// never syncs.
    internal NativeSyncTransaction? StageWithSave(SessionState previous, SessionState next,
        CrestCore.Contracts.SyncDeletionReason reason) {
        NativeSyncAuthority? target;
        lock (Gate) target = sync;
        return target is null || next.DisposableSeedMarker is not null ? null : target.StageWithSave(previous, next, reason);
    }

    /// Queues the stage of an accepted state, when a sync is attached, the
    /// state holds something `previous` did not and it is no disposable seed.
    private void QueueStage(SessionState previous, SessionState next, SyncStaging? staging) {
        NativeSyncAuthority? target;
        lock (Gate) target = sync;
        if (target is null || staging is null || next.DisposableSeedMarker is not null || next.Equals(previous)) return;
        target.Queue(previous, next, staging);
    }

    /// Replaces the session with the edits `delta` names and saves the result,
    /// with a sync transaction's journal when one is given, before publishing
    /// it. A failed save leaves the accepted state and the file unchanged.
    internal void ReplaceDurably(ReadOnlySpan<byte> delta, NativeSyncTransaction? transaction = null) =>
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
