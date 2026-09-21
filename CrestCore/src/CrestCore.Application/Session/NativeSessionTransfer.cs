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
    public NativeSessionCheckpoint SourceCheckpoint => a!.Checkpoint;
    public NativeSessionCheckpoint DestinationCheckpoint => b!.Checkpoint;

    #endregion

    #region Constructors

    internal NativeSessionTransfer(NativeSessionAuthority source, NativeSessionCommand a,
        NativeSessionAuthority destination, NativeSessionCommand b, byte[] output) { this.source = source; sourceCommand = a; this.destination = destination; destinationCommand = b; Output = output; }

    #endregion

    #region Actions - Transfer

    public void Reserve(NativeSyncTransaction? sync = null) {
        lock (NativeSessionAuthority.Gate) {
            if (completed || a is not null) throw new BrowserRuleException(BrowserRuleCodes.InvalidTransferTransaction);
            try {
                a = sourceCommand.Reserve(NativeSessionAuthority.TransferSelection(sourceCommand.Document));
                b = destinationCommand.Reserve(NativeSessionAuthority.TransferSelection(destinationCommand.Document));
                if (sync is not null) {
                    if (ReferenceEquals(sync.Owner.Session, source)) a.BindSync(sync);
                    else if (ReferenceEquals(sync.Owner.Session, destination)) b.BindSync(sync);
                    else throw new BrowserRuleException(BrowserRuleCodes.InvalidSyncSessionOwner);
                }
            } catch { a?.Dispose(); b?.Dispose(); a = b = null; throw; }
        }
    }

    public (ulong Source, ulong Destination) Commit() {
        lock (NativeSessionAuthority.Gate) {
            if (completed || a is null || b is null) throw new BrowserRuleException(BrowserRuleCodes.InvalidTransferTransaction);
            // At most one side is persistent. Publish its journal first; the
            // two reserved session commits then cannot fail or interleave.
            a.SyncTransaction?.Commit(); b.SyncTransaction?.Commit();
            var result = (a.Commit(), b.Commit()); completed = true; return result;
        }
    }

    public void Dispose() {
        lock (NativeSessionAuthority.Gate) { if (completed) return; a?.Dispose(); b?.Dispose(); completed = true; }
    }

    #endregion
}
