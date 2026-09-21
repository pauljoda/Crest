using CrestCore.Domain;

namespace CrestCore.Application;

/// Holds two validated revisions until the one durable owner has saved. Neither
/// graph can change while reserved, and a failed save cancels both reservations.
public sealed class NativeSessionTransfer : IDisposable {
    private readonly NativeSessionAuthority source, destination;
    private readonly NativeSessionCommand sourceCommand, destinationCommand;
    private NativeSessionReplacement? a, b;
    private bool completed;
    public byte[] Output { get; }
    public NativeSessionCheckpoint SourceCheckpoint => a!.Checkpoint;
    public NativeSessionCheckpoint DestinationCheckpoint => b!.Checkpoint;
    internal NativeSessionTransfer(NativeSessionAuthority source, NativeSessionCommand a,
        NativeSessionAuthority destination, NativeSessionCommand b, byte[] output) { this.source = source; sourceCommand = a; this.destination = destination; destinationCommand = b; Output = output; }
    public void Reserve(NativeSyncTransaction? sync = null) {
        lock (NativeSessionAuthority.Gate) {
            if (completed || a is not null) throw new BrowserRuleException("invalid_transfer_transaction");
            try {
                a = sourceCommand.Reserve(NativeSessionAuthority.TransferSelection(sourceCommand.Document));
                b = destinationCommand.Reserve(NativeSessionAuthority.TransferSelection(destinationCommand.Document));
                if (sync is not null) {
                    if (ReferenceEquals(sync.Owner.Session, source)) a.BindSync(sync);
                    else if (ReferenceEquals(sync.Owner.Session, destination)) b.BindSync(sync);
                    else throw new BrowserRuleException("invalid_sync_session_owner");
                }
            } catch { a?.Dispose(); b?.Dispose(); a = b = null; throw; }
        }
    }
    public (ulong Source, ulong Destination) Commit() {
        lock (NativeSessionAuthority.Gate) {
            if (completed || a is null || b is null) throw new BrowserRuleException("invalid_transfer_transaction");
            // At most one side is persistent. Publish its journal first; the
            // two reserved session commits then cannot fail or interleave.
            a.SyncTransaction?.Commit(); b.SyncTransaction?.Commit();
            var result = (a.Commit(), b.Commit()); completed = true; return result;
        }
    }
    public void Dispose() {
        lock (NativeSessionAuthority.Gate) { if (completed) return; a?.Dispose(); b?.Dispose(); completed = true; }
    }
}
