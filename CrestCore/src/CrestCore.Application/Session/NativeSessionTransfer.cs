using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

/// Holds two validated revisions until the one durable owner has saved. Neither
/// graph can change while reserved, and a failed save cancels both reservations.
public sealed class NativeSessionTransfer : IDisposable {
    #region Variables

    private readonly NativeSessionAuthority source, destination;
    private readonly NativeSessionCommand sourceCommand, destinationCommand;
    private NativeSessionReplacement? a, b;
    private bool completed;
    public byte[] Output { get; }
    internal NativeSessionCheckpoint SourceCheckpoint => a!.Checkpoint;
    internal NativeSessionCheckpoint DestinationCheckpoint => b!.Checkpoint;

    #endregion

    #region Constructors

    internal NativeSessionTransfer(NativeSessionAuthority source, NativeSessionCommand a,
        NativeSessionAuthority destination, NativeSessionCommand b, byte[] output) { this.source = source; sourceCommand = a; this.destination = destination; destinationCommand = b; Output = output; }

    #endregion

    #region Actions - Transfer

    internal void Reserve() {
        lock (NativeSessionAuthority.Gate) {
            if (completed || a is not null) throw new BrowserRuleException(BrowserRuleCodes.InvalidTransferTransaction);
            try {
                a = sourceCommand.Reserve();
                b = destinationCommand.Reserve();
            } catch { a?.Dispose(); b?.Dispose(); a = b = null; throw; }
        }
    }

    /// Accepts both reserved states together, then tells the device.
    internal void Commit() {
        SessionState previousSource, previousDestination;
        lock (NativeSessionAuthority.Gate) {
            if (completed || a is null || b is null) throw new BrowserRuleException(BrowserRuleCodes.InvalidTransferTransaction);
            // At most one side is persistent. Publish its journal first; the
            // two reserved session commits then cannot fail or interleave.
            a.SyncTransaction?.Commit(); b.SyncTransaction?.Commit();
            previousSource = a.Complete(); previousDestination = b.Complete(); completed = true;
        }
        source.Published(previousSource, a.Session, a.FollowUp, a.Events);
        destination.Published(previousDestination, b.Session, b.FollowUp, b.Events);
    }

    /// Reserves both states, stages the side that syncs, saves the side that
    /// keeps a file with that journal, then publishes both. A failed stage or
    /// save cancels both reservations.
    public void CommitDurably() {
        Reserve();
        NativeSyncTransaction? staged = null;
        try {
            var reason = SyncStaging.Transfer.Reason;
            if (source.StageWithSave(sourceCommand.Base, a!.Session, reason) is { } fromSource) a!.BindSync(staged = fromSource);
            else if (destination.StageWithSave(destinationCommand.Base, b!.Session, reason) is { } fromDestination)
                b!.BindSync(staged = fromDestination);
            source.Storage?.Save(a!.Session, a.Revision, a.SyncTransaction?.Journal, a.Checkpoint);
            destination.Storage?.Save(b!.Session, b.Revision, b.SyncTransaction?.Journal, b.Checkpoint);
        } catch {
            Dispose();
            staged?.Dispose();
            throw;
        }
        Commit();
        staged?.Owner.AnnounceStaged();
    }

    public void Dispose() {
        lock (NativeSessionAuthority.Gate) { if (completed) return; a?.Dispose(); b?.Dispose(); completed = true; }
    }

    #endregion
}
