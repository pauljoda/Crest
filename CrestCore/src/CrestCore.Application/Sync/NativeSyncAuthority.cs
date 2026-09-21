using CrestCore.Domain;

namespace CrestCore.Application;

/// The sync component of a native session. Native workers schedule preparation
/// and storage, but only this owner accepts journals and orders local revisions.
public sealed class NativeSyncAuthority(NativeSyncJournal initial) {
    private NativeSyncJournal journal = initial;
    private ulong latestRevision;
    private NativeSyncTransaction? pending;
    internal NativeSessionAuthority? Session { get; set; }
    public NativeSyncJournal Snapshot { get { lock (NativeSessionAuthority.Gate) return journal; } }
    public void Advance(ulong revision) {
        lock (NativeSessionAuthority.Gate) latestRevision = Math.Max(latestRevision, revision);
    }

    public NativeSyncTransaction? Prepare(ulong? revision, ReadOnlySpan<byte> input) {
        NativeSyncTransaction value;
        lock (NativeSessionAuthority.Gate) {
            if (revision < latestRevision) return null;
            if (pending is not null) throw new BrowserRuleException("sync_transaction_in_progress");
            value = new(this, revision, journal);
            pending = value;
        }
        // Projection/encoding uses immutable inputs outside the authority lock.
        // Advancing the UI revision never waits for an older background encode.
        try { value.Build(input); return value; } catch { value.Dispose(); throw; }
    }

    internal bool Seal(NativeSyncTransaction value) {
        lock (NativeSessionAuthority.Gate) {
            RequirePending(value);
            if (value.SourceRevision < latestRevision) return false;
            value.IsSealed = true;
            return true;
        }
    }
    internal void Commit(NativeSyncTransaction value) {
        lock (NativeSessionAuthority.Gate) {
            RequirePending(value);
            if (!value.IsSealed) throw new BrowserRuleException("sync_transaction_not_sealed");
            journal = value.Journal;
            if (value.SourceRevision is { } revision) latestRevision = Math.Max(latestRevision, revision);
            pending = null;
        }
    }
    internal void Cancel(NativeSyncTransaction value) {
        lock (NativeSessionAuthority.Gate) {
            RequirePending(value);
            pending = null;
        }
    }
    private void RequirePending(NativeSyncTransaction value) {
        if (!ReferenceEquals(pending, value)) throw new BrowserRuleException("invalid_sync_transaction");
    }
}
