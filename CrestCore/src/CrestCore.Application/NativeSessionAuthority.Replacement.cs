namespace CrestCore.Application;

public sealed partial class NativeSessionAuthority
{
    /// Reserves a validated revision while the platform commits durable storage.
    /// Other writes are rejected until commit or cancellation. No platform I/O
    /// occurs under the core lock, and cancellation leaves the authority intact.
    public NativeSessionReplacement ReserveReplacement(ulong expected, ReadOnlySpan<byte> delta,
        ReadOnlySpan<byte> selection)
    {
        lock (Gate)
        {
            var next = Prepare(expected, delta);
            var nextRevision = checked(Revision + 1);
            var checkpoint = new NativeSessionCheckpoint(next, Parse(selection));
            // Validate the selection and serialization before granting the lease.
            _ = checkpoint.Read("core");
            replacement = new(this, next, nextRevision, checkpoint);
            return replacement;
        }
    }

    internal ulong CompleteReplacement(NativeSessionReplacement value, bool commit)
    {
        lock (Gate)
        {
            if (!ReferenceEquals(replacement, value))
                throw new CrestCore.Domain.BrowserRuleException("invalid_session_transaction");
            if (commit) { document = value.Document; Revision = value.Revision; }
            replacement = null;
            return Revision;
        }
    }
}

public sealed class NativeSessionReplacement : IDisposable
{
    private readonly NativeSessionAuthority owner;
    private bool completed;
    internal NativeSessionAuthority.SessionDocument Document { get; }
    internal ulong Revision { get; }
    public NativeSessionCheckpoint Checkpoint { get; }
    internal NativeSessionReplacement(NativeSessionAuthority owner, NativeSessionAuthority.SessionDocument document,
        ulong revision, NativeSessionCheckpoint checkpoint)
    { this.owner = owner; Document = document; Revision = revision; Checkpoint = checkpoint; }
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
