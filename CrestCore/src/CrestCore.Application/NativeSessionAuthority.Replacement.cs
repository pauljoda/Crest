namespace CrestCore.Application;

public sealed partial class NativeSessionAuthority
{
    private NativeSyncAuthority? sync;
    public void AttachSync(NativeSyncAuthority value)
    {
        lock (Gate)
        {
            if (workspaceKind != CrestCore.Domain.BrowserWorkspaceKind.Persistent
                || sync is not null && !ReferenceEquals(sync, value)
                || value.Session is not null && !ReferenceEquals(value.Session, this))
                throw new CrestCore.Domain.BrowserRuleException("invalid_sync_session_owner");
            sync = value; value.Session = this;
        }
    }

    /// Reserves a validated revision while the platform commits durable storage.
    /// Other writes are rejected until commit or cancellation. No platform I/O
    /// occurs under the core lock, and cancellation leaves the authority intact.
    public NativeSessionReplacement ReserveReplacement(ulong expected, ReadOnlySpan<byte> delta,
        ReadOnlySpan<byte> selection, NativeSyncTransaction? transaction = null)
    {
        lock (Gate)
        {
            System.Text.Json.Nodes.JsonNode? authorizedDeletions = null;
            if (transaction is not null)
            {
                if (!transaction.IsReadyToCommit || !ReferenceEquals(transaction.Owner.Session, this) || transaction.Materialization is null)
                    throw new CrestCore.Domain.BrowserRuleException("invalid_sync_session_owner");
                authorizedDeletions = transaction.MaterializedSpaceDeletions;
            }
            var next = Prepare(expected, delta, authorizedDeletions);
            var nextRevision = checked(Revision + 1);
            var checkpoint = new NativeSessionCheckpoint(next, Parse(selection));
            // Validate the selection and serialization before granting the lease.
            _ = checkpoint.Read("core");
            var reserved = new NativeSessionReplacement(this, next, nextRevision, checkpoint);
            if (transaction is not null) reserved.BindSync(transaction);
            replacement = reserved;
            return replacement;
        }
    }

    internal ulong CompleteReplacement(NativeSessionReplacement value, bool commit)
    {
        lock (Gate)
        {
            if (!ReferenceEquals(replacement, value))
                throw new CrestCore.Domain.BrowserRuleException("invalid_session_transaction");
            if (commit)
            {
                value.SyncTransaction?.Commit();
                document = value.Document; Revision = value.Revision;
                borrowedSourceRevision = value.BorrowedSourceRevision ?? borrowedSourceRevision;
            }
            replacement = null;
            return Revision;
        }
    }

    internal NativeSessionReplacement ReserveCommand(NativeSessionCommand command, ReadOnlySpan<byte> selection)
    {
        lock (Gate)
        {
            RequireWritable(requireCurrentBorrowedPolicy: false);
            command.RequireAccepted();
            if (command.ExpectedRevision != Revision)
                throw new CrestCore.Domain.BrowserRuleException("stale_session_revision");
            var nextRevision = checked(Revision + 1);
            var checkpoint = new NativeSessionCheckpoint(command.Document, Parse(selection));
            _ = checkpoint.Read("core");
            replacement = new(this, command.Document, nextRevision, checkpoint, command.BorrowedSourceRevision);
            return replacement;
        }
    }
}

public sealed class NativeSessionReplacement : IDisposable
{
    private readonly NativeSessionAuthority owner;
    private bool completed;
    internal NativeSessionAuthority.SessionDocument Document { get; }
    internal ulong Revision { get; }
    internal ulong? BorrowedSourceRevision { get; }
    public NativeSessionCheckpoint Checkpoint { get; }
    internal NativeSyncTransaction? SyncTransaction { get; private set; }
    internal NativeSessionReplacement(NativeSessionAuthority owner, NativeSessionAuthority.SessionDocument document,
        ulong revision, NativeSessionCheckpoint checkpoint, ulong? borrowedSourceRevision = null)
    {
        this.owner = owner; Document = document; Revision = revision; Checkpoint = checkpoint;
        BorrowedSourceRevision = borrowedSourceRevision;
    }
    public void BindSync(NativeSyncTransaction value)
    {
        lock (NativeSessionAuthority.Gate)
        {
            if (completed || SyncTransaction is not null || !value.IsReadyToCommit || !ReferenceEquals(value.Owner.Session, owner))
                throw new CrestCore.Domain.BrowserRuleException("invalid_sync_session_owner");
            SyncTransaction = value;
        }
    }
    public ulong Commit()
    {
        lock (NativeSessionAuthority.Gate)
        {
            if (completed) throw new CrestCore.Domain.BrowserRuleException("invalid_session_transaction");
            var revision = owner.CompleteReplacement(this, true);
            completed = true;
            return revision;
        }
    }
    public void Dispose()
    {
        lock (NativeSessionAuthority.Gate)
        {
            if (completed) return;
            owner.CompleteReplacement(this, false);
            completed = true;
        }
    }
}
