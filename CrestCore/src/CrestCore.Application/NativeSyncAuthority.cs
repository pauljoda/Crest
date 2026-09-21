using System.Text;
using System.Text.Json.Nodes;
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

public sealed class NativeSyncTransaction : IDisposable {
    internal NativeSyncAuthority Owner { get; }
    internal ulong? SourceRevision { get; }
    internal bool IsSealed { get; set; }
    private bool completed, committed;
    internal bool IsReadyToCommit => IsSealed && !completed;
    public NativeSyncJournal Journal { get; private set; }
    public byte[]? Materialization { get; private set; }
    internal JsonNode? MaterializedSpaceDeletions { get; private set; }
    internal NativeSyncTransaction(NativeSyncAuthority owner, ulong? revision, NativeSyncJournal journal) { Owner = owner; SourceRevision = revision; Journal = journal; }

    internal void Build(ReadOnlySpan<byte> input) {
        if (input.Length is 0 or > NativeSyncJournal.MaximumBytes) throw new BrowserRuleException("sync_size_limit");
        var request = JsonNode.Parse(input, documentOptions: new() { MaxDepth = 64 })!.AsObject();
        request["preferences"] = Journal.Preferences;
        if (request["operation"]!.GetValue<string>() is "merge" or "replace") {
            var result = NativeSyncSessionTransition.Prepare(Journal, Encoding.UTF8.GetBytes(request.ToJsonString()));
            Journal = result.Journal;
            MaterializedSpaceDeletions = result.Materialization["session"]!["spaceDeletions"]?.DeepClone();
            Materialization = NativeSyncQuery.Success(result.Materialization);
        } else Journal = Journal.Apply(Encoding.UTF8.GetBytes(request.ToJsonString()));
        _ = Journal.Read();
    }
    public bool Seal() => Owner.Seal(this);
    public void Commit() {
        lock (NativeSessionAuthority.Gate) {
            // A paired session replacement may already have published this
            // journal under the same core lock as the browser revision.
            if (committed) return;
            if (completed) throw new BrowserRuleException("invalid_sync_transaction");
            Owner.Commit(this); completed = committed = true;
        }
    }
    public void Dispose() {
        lock (NativeSessionAuthority.Gate) {
            if (completed) return;
            Owner.Cancel(this); completed = true;
        }
    }
}
