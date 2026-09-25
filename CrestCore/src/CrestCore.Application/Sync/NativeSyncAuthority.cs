using System.Text.Json.Nodes;

using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

/// The sync component of a native session. It accepts journals one
/// transaction at a time and stages the session's accepted revisions itself:
/// the session hands it each revision with how that revision stages, and the
/// transport hears `SyncJournalChanged` once the journal holds it.
public sealed class NativeSyncAuthority {
    #region Variables

    private readonly SyncStager stager;
    private NativeSyncJournal journal;
    private NativeSyncTransaction? pending;
    internal NativeSessionAuthority? Session { get; set; }
    public NativeSyncJournal Snapshot { get { lock (NativeSessionAuthority.Gate) return journal; } }

    /// Counts the journals this authority accepted, so a reader holding a
    /// copy knows when to read it again.
    public ulong Version { get { lock (NativeSessionAuthority.Gate) return version; } }
    private ulong version;

    #endregion

    #region Constructors

    public NativeSyncAuthority(NativeSyncJournal initial) {
        journal = initial;
        stager = new(this);
    }

    #endregion

    #region Actions - Transactions

    /// Prepares one journal mutation or session materialization the transport
    /// asked for, waiting for any transaction in progress to finish. A merge,
    /// replacement or overwrite stages the local session itself, so it
    /// supersedes the stages still queued.
    public NativeSyncTransaction Prepare(ReadOnlySpan<byte> input) {
        if (input.Length is 0 or > NativeSyncJournal.MaximumBytes) throw new BrowserRuleException(BrowserRuleCodes.SyncSizeLimit);
        var request = JsonNode.Parse(input, documentOptions: new() { MaxDepth = 64 })!.AsObject();
        var operation = NativeSyncOperationCodes.Parse(request["operation"]?.GetValue<string>());
        if (NativeSyncOperationCodes.SupersedesStaging(operation)) stager.Supersede();
        var value = Begin(sequence: null);
        // Projection and encoding use immutable inputs outside the gate.
        try { value.Build(request, operation); return value; } catch { value.Dispose(); throw; }
    }

    /// A merge, replacement or overwrite stages the session itself, so the
    /// stages still queued have nothing left to add. Answers the request it
    /// replaced.
    internal SyncStager.Request? Supersede() => stager.Supersede();

    /// Starts a transaction the cloud transport asked for once the one in
    /// progress completes. The caller holds no lock: waiting releases the gate.
    internal NativeSyncTransaction BeginTransaction() => Begin(sequence: null);

    /// Starts a transaction once the one in progress completes. The caller
    /// holds no lock.
    private NativeSyncTransaction Begin(ulong? sequence) {
        lock (NativeSessionAuthority.Gate) {
            while (pending is not null) Monitor.Wait(NativeSessionAuthority.Gate);
            var value = new NativeSyncTransaction(this, sequence, journal);
            pending = value;
            return value;
        }
    }

    internal bool Seal(NativeSyncTransaction value) {
        lock (NativeSessionAuthority.Gate) {
            RequirePending(value);
            if (value.Sequence is { } sequence && !stager.IsCurrent(sequence)) return false;
            value.IsSealed = true;
            return true;
        }
    }

    internal void Commit(NativeSyncTransaction value) {
        lock (NativeSessionAuthority.Gate) {
            RequirePending(value);
            if (!value.IsSealed) throw new BrowserRuleException(BrowserRuleCodes.SyncTransactionNotSealed);
            journal = value.Journal;
            value.Version = ++version;
            pending = null;
            Monitor.PulseAll(NativeSessionAuthority.Gate);
        }
    }

    internal void Cancel(NativeSyncTransaction value) {
        lock (NativeSessionAuthority.Gate) {
            RequirePending(value);
            pending = null;
            Monitor.PulseAll(NativeSessionAuthority.Gate);
        }
        stager.Requeue(value.Superseded);
    }

    private void RequirePending(NativeSyncTransaction value) {
        if (!ReferenceEquals(pending, value)) throw new BrowserRuleException(BrowserRuleCodes.InvalidSyncTransaction);
    }

    #endregion

    #region Actions - Staging

    /// Queues `next`, a revision the session accepted in place of `previous`,
    /// to stage as `staging` says on the worker.
    internal void Queue(SessionState previous, SessionState next, SyncStaging staging) =>
        stager.Queue(previous, next, staging);

    /// Stages `session`, a revision about to be saved in place of `previous`,
    /// for `reason`, replacing whatever is queued; a record a queued edit
    /// removed keeps that edit's reason. Answers the sealed transaction the
    /// revision's reservation saves and publishes; disposing it uncommitted
    /// queues the replaced stage again. Throws `Rejected` naming why it cannot
    /// stage.
    internal NativeSyncTransaction StageWithSave(SessionState previous, SessionState session, SyncDeletionReason reason) {
        var replaced = stager.Supersede();
        var value = Begin(sequence: null);
        value.Superseded = replaced;
        try {
            var removals = (replaced?.Removals ?? SyncRemovals.None).Adding(new(previous, session, reason));
            value.Stage(session, reason, removals.Reasons(reason), StoredSessionCodec.Seconds(DateTimeOffset.UtcNow));
            _ = value.Seal();
            return value;
        } catch (Exception error) {
            value.Dispose();
            throw new Rejected(new SyncStagingRefused(Failure(error)));
        }
    }

    /// Stages one queued request on the worker. Answers false when a newer
    /// stage replaced it, which then settles in its place.
    internal bool StageQueued(SyncStager.Request request) {
        NativeSyncTransaction value;
        try {
            value = Begin(request.Sequence);
        } catch (Exception error) {
            Announce(workspace => new SyncStagingFailed(workspace, Failure(error)));
            return true;
        }
        try {
            value.Stage(request.Session, request.Reason, request.Removals.Reasons(request.Reason),
                StoredSessionCodec.Seconds(DateTimeOffset.UtcNow));
            if (!value.Seal()) {
                value.Dispose();
                return false;
            }
            value.CommitDurably();
        } catch (Exception error) {
            value.Dispose();
            Announce(workspace => new SyncStagingFailed(workspace, Failure(error)));
            return true;
        }
        return true;
    }

    /// Tells the transport what the journal holds now: how many records, and
    /// how many of them wait to upload. Called with no lock held.
    internal void AnnounceStaged() {
        int pendingRecords, records;
        lock (NativeSessionAuthority.Gate) (pendingRecords, records) = (journal.PendingCount, journal.RecordCount);
        Announce(workspace => new SyncJournalChanged(workspace, pendingRecords, records));
    }

    /// Returns once every stage requested before the call has committed or
    /// failed, without waiting for the host's turn or a coalescing delay.
    public void Flush() => stager.Flush();

    /// Stages whatever is still queued, then stops staging.
    public void Stop() => stager.Stop();

    /// The host of the session's device finished a turn.
    internal void TurnEnded() => stager.TurnEnded();

    /// Asks the host of the session's device for a turn, after which the
    /// stages queued in this one start. Called with no lock held.
    internal void RequestTurn() => Session?.RequestTurn();

    private void Announce(Func<Guid, Change> change) => Session?.Announce(change);

    /// Why a stage failed, for the transport and the person.
    private static SyncStagingFailure Failure(Exception error) => error switch {
        StorageException => SyncStagingFailure.NotSaved,
        BrowserRuleException { Code: BrowserRuleCodes.SyncRecordLimit or BrowserRuleCodes.SyncSizeLimit } => SyncStagingFailure.TooLarge,
        BrowserRuleException { Code: BrowserRuleCodes.SyncClockExhausted } => SyncStagingFailure.ClockExhausted,
        _ => SyncStagingFailure.InvalidSession
    };

    #endregion
}
