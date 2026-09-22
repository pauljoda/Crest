using System.Text;
using System.Text.Json.Nodes;

using CrestCore.Domain;

namespace CrestCore.Application;

public sealed class NativeSyncTransaction : IDisposable {
    #region Variables

    internal NativeSyncAuthority Owner { get; }
    internal ulong? SourceRevision { get; }
    internal bool IsSealed { get; set; }
    private bool completed, committed;
    internal bool IsReadyToCommit => IsSealed && !completed;
    public NativeSyncJournal Journal { get; private set; }
    public byte[]? Materialization { get; private set; }
    internal JsonNode? MaterializedSpaceDeletions { get; private set; }

    #endregion

    #region Constructors

    internal NativeSyncTransaction(NativeSyncAuthority owner, ulong? revision, NativeSyncJournal journal) { Owner = owner; SourceRevision = revision; Journal = journal; }

    #endregion

    #region Actions - Sync

    internal void Build(ReadOnlySpan<byte> input) {
        if (input.Length is 0 or > NativeSyncJournal.MaximumBytes) throw new BrowserRuleException(BrowserRuleCodes.SyncSizeLimit);
        var request = JsonNode.Parse(input, documentOptions: new() { MaxDepth = 64 })!.AsObject();
        request["preferences"] = Journal.Preferences;
        if (request["operation"]!.GetValue<string>() is NativeSyncOperations.Merge or NativeSyncOperations.Replace) {
            var result = NativeSyncSessionTransition.Prepare(Journal, Encoding.UTF8.GetBytes(request.ToJsonString()), Owner.Session?.Access);
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
            if (completed) throw new BrowserRuleException(BrowserRuleCodes.InvalidSyncTransaction);
            Owner.Commit(this); completed = committed = true;
        }
    }

    public void Dispose() {
        lock (NativeSessionAuthority.Gate) {
            if (completed) return;
            Owner.Cancel(this); completed = true;
        }
    }

    #endregion
}
