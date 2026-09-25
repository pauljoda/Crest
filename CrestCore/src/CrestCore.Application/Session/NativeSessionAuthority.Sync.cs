using System.Text.Json;
using System.Text.Json.Nodes;

using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

public sealed partial class NativeSessionAuthority {
    #region Static Variables

    /// How often a merge computed outside the lock is computed again when the
    /// session moved meanwhile, before it computes holding the lock.
    private const int ConvergenceAttempts = 3;

    #endregion

    #region Types

    /// What converging with the cloud's records makes: the journal, the session
    /// and the tabs repair gave a new identity, each with the tab whose image
    /// it wears.
    private sealed record Convergence(NativeSyncJournal Journal, SessionState Session, SessionTabEvents Events);

    #endregion

    #region Actions - Cloud sync

    /// Runs one intent from the cloud transport at `now`, drawing the
    /// identities repair gives from `ids`, and saves the session and its
    /// journal together before it returns; see `CloudSyncIntent`. Throws
    /// `Rejected`.
    internal void Handle(CloudSyncIntent intent, DateTimeOffset now, IIdSource ids) {
        ArgumentNullException.ThrowIfNull(intent);
        ArgumentNullException.ThrowIfNull(ids);
        var sync = AttachedSync();
        switch (intent) {
            case MergeSyncRecords merge: Converging(sync, new IncomingSyncRecords(merge.Records), replacing: false, now, ids); break;
            case ReplaceWithCloudRecords replacement:
                Converging(sync, new IncomingSyncRecords(replacement.Records), replacing: true, now, ids);
                break;
            case ReplaceSeedWithCloudRecords replacement:
                if (Current.DisposableSeedMarker is null) return;
                Converging(sync, new IncomingSyncRecords(replacement.Records), replacing: true, now, ids, seedOnly: true);
                break;
            case OverwriteCloud overwrite: Overwriting(sync, new IncomingSyncRecords(overwrite.Records), now); break;
            default: throw new ArgumentOutOfRangeException(nameof(intent), intent.GetType().Name, "The session does not handle this intent.");
        }
    }

    /// The sync component this session stages into. Throws `Rejected` with
    /// `StoredSessionClosed` once the session closed, and `NoStoredSession`
    /// before a sync is attached.
    private NativeSyncAuthority AttachedSync() {
        lock (Gate) {
            if (released) throw new Rejected(new StoredSessionClosed());
            return sync ?? throw new Rejected(new NoStoredSession());
        }
    }

    /// Merges `records` into the session and its journal, or replaces both
    /// with them. The journal transaction begins before the gate is taken:
    /// waiting for one in progress releases the gate. The result is computed
    /// outside the gate from the session as it was, and again when the session
    /// moved meanwhile, a few times, then holding the gate. The stages still
    /// queued are superseded before each computation, and a merge deletes each
    /// record their edits removed for the reason of the edit that removed it;
    /// a transaction that never commits queues them again.
    private void Converging(NativeSyncAuthority sync, IncomingSyncRecords records, bool replacing, DateTimeOffset now,
        IIdSource ids, bool seedOnly = false) {
        var superseded = sync.Supersede();
        var transaction = sync.BeginTransaction();
        transaction.Superseded = superseded;
        NativeSessionReplacement? reserved = null;
        try {
            if (!replacing) records.RequireSameSpaces(transaction.Journal);
            for (int attempt = 0; reserved is null; attempt++) {
                SessionState basis;
                ulong revision;
                lock (Gate) {
                    Supersede(sync, transaction);
                    (basis, revision) = (IntentBasis(), Revision);
                }
                if (seedOnly && basis.DisposableSeedMarker is null) {
                    transaction.Dispose();
                    return;
                }
                if (attempt < ConvergenceAttempts) {
                    var computed = Converge(transaction, basis, records, replacing, now, ids);
                    lock (Gate) if (Revision == revision) reserved = Reserving(transaction, computed);
                } else {
                    lock (Gate) {
                        Supersede(sync, transaction);
                        reserved = Reserving(transaction, Converge(transaction, IntentBasis(), records, replacing, now, ids));
                    }
                }
            }
        } catch (Exception error) {
            transaction.Dispose();
            throw Refusal(error);
        }
        try {
            reserved.BindSync(transaction);
            SaveAndCommit(reserved);
        } catch (Exception error) {
            reserved.Dispose();
            transaction.Dispose();
            throw Refusal(error);
        }
        sync.AnnounceStaged();
    }

    /// Makes `transaction` cover the stages queued since it last superseded
    /// them. The caller holds the gate.
    private static void Supersede(NativeSyncAuthority sync, NativeSyncTransaction transaction) =>
        transaction.Superseded = SyncStager.Request.Covering(transaction.Superseded, sync.Supersede());

    /// The journal and session `records` make of `basis` and the journal
    /// `transaction` holds, at `now`, with the tabs repair gave a new identity.
    private Convergence Converge(NativeSyncTransaction transaction, SessionState basis, IncomingSyncRecords records,
        bool replacing, DateTimeOffset now, IIdSource ids) {
        var journal = transaction.Journal;
        var seconds = StoredSessionCodec.Seconds(now);
        var emptySpace = SpaceTemplate.Ordinary.Make(Guid.NewGuid(), Guid.NewGuid(), Guid.NewGuid(), number: 1, now);
        var removals = (transaction.Superseded?.Removals ?? SyncRemovals.None).Reasons(SyncDeletionReason.Superseded);
        var result = NativeSyncSessionTransition.Prepare(journal, StoredSessionCodec.Encode(basis), records.Batch(), replacing,
            seconds, journal.Preferences, StoredSessionCodec.Encode(emptySpace), Access, ids, removals);
        _ = result.Journal.Read();
        var session = StoredSessionCodec.DecodeSession(result.Materialization["session"]);
        return new(result.Journal, session, new(Copies(basis, session, result.Materialization["assets"]!.AsArray()), Favicon: null));
    }

    /// The tabs repair gave a new identity that the session held before, each
    /// with the tab it was.
    private static IReadOnlyList<SessionTabCopy> Copies(SessionState basis, SessionState next, JsonArray assets) {
        var held = basis.Spaces.SelectMany(space => space.Tabs.Select(tab => (space.Id, tab.Id))).ToHashSet();
        var copies = new List<SessionTabCopy>();
        foreach (var asset in assets) {
            var space = next.Spaces[asset!["spaceIndex"]!.GetValue<int>()];
            var copy = space.Tabs[asset["tabIndex"]!.GetValue<int>()].Id;
            var source = (StoredSessionCodec.Identity(asset["sourceSpaceID"]), StoredSessionCodec.Identity(asset["sourceTabID"]));
            if (copy != source.Item2 && held.Contains(source)) copies.Add(new(source.Item2, copy));
        }
        return copies;
    }

    /// Reserves `computed` while it is saved with its journal, which
    /// `transaction` takes. The caller holds the gate, and binds the two.
    private NativeSessionReplacement Reserving(NativeSyncTransaction transaction, Convergence computed) {
        Validate(computed.Session);
        ValidateBorrowedSession(computed.Session);
        transaction.Adopt(computed.Journal);
        _ = transaction.Seal();
        return Reserve(computed.Session, completes: null, followUp: null, computed.Events);
    }

    /// Rebases the journal above `records`, the cloud's, from the session as
    /// it is, so every record waits to upload, and saves the journal. The
    /// session does not change. A transaction that never commits queues the
    /// stages it superseded again.
    private void Overwriting(NativeSyncAuthority sync, IncomingSyncRecords records, DateTimeOffset now) {
        var superseded = sync.Supersede();
        var transaction = sync.BeginTransaction();
        transaction.Superseded = superseded;
        try {
            SessionState basis;
            lock (Gate) basis = IntentBasis();
            transaction.Adopt(transaction.Journal.Overwrite(StoredSessionCodec.Encode(basis), records.Batch(),
                StoredSessionCodec.Seconds(now)));
            _ = transaction.Seal();
            transaction.CommitDurably();
        } catch (Exception error) {
            transaction.Dispose();
            throw Refusal(error);
        }
    }

    /// The rejection `error`, a failure to take the cloud's records, stands
    /// for. A save that failed is `SaveFailed`; a journal that cannot record
    /// the result is `SyncStagingRefused`; a rule a record breaks is
    /// `InvalidSyncRecords` with its flaw, and a failure no rule names is
    /// `InvalidSyncRecords` with `Unexpected`, never a fault the host sees.
    private static Rejected Refusal(Exception error) => error switch {
        Rejected { Rejection: InvalidSession { Flaw: SessionFlaw.SharedProfile } } =>
            new(new InvalidSyncRecords(SyncRecordFlaw.SharedProfile, null)),
        Rejected { Rejection: InvalidSession } => new(new InvalidSyncRecords(SyncRecordFlaw.Unexpected, null)),
        Rejected rejected => rejected,
        StorageException storage => new(new SaveFailed(storage.Reason)),
        NativeSyncDocumentException document => new(new InvalidSyncRecords(DocumentFlaw(document.Code),
            Guid.TryParse(document.Value, out var subject) ? subject : null)),
        BrowserRuleException { Code: BrowserRuleCodes.SyncClockExhausted } => new(new SyncStagingRefused(SyncStagingFailure.ClockExhausted)),
        BrowserRuleException { Code: BrowserRuleCodes.SyncSizeLimit } => new(new SyncStagingRefused(SyncStagingFailure.TooLarge)),
        BrowserRuleException rule => new(new InvalidSyncRecords(RuleFlaw(rule.Code), null)),
        JsonException or KeyNotFoundException or FormatException => new(new InvalidSyncRecords(SyncRecordFlaw.MalformedRecord, null)),
        _ => new(new InvalidSyncRecords(SyncRecordFlaw.Unexpected, null))
    };

    /// TRANSITIONAL until the materializer names flaws itself (8a commit 4):
    /// the flaw a sync document failure stands for.
    private static SyncRecordFlaw DocumentFlaw(string code) => code switch {
        NativeSyncDocumentErrorCodes.DanglingFolder => SyncRecordFlaw.DanglingFolder,
        NativeSyncDocumentErrorCodes.DuplicateProfile => SyncRecordFlaw.SharedProfile,
        NativeSyncDocumentErrorCodes.DuplicateRecord => SyncRecordFlaw.DuplicateRecord,
        NativeSyncDocumentErrorCodes.ImmutableProfileChanged => SyncRecordFlaw.ProfileChanged,
        NativeSyncDocumentErrorCodes.InvalidFolderHierarchy => SyncRecordFlaw.InvalidFolderHierarchy,
        NativeSyncDocumentErrorCodes.RecordLimitExceeded => SyncRecordFlaw.TooManyRecords,
        NativeSyncDocumentErrorCodes.TooManyPinnedTabs => SyncRecordFlaw.TooManyPinnedTabs,
        _ => SyncRecordFlaw.Unexpected
    };

    /// TRANSITIONAL until the sync rules throw flaws themselves (8c): the flaw
    /// a sync rule's failure stands for.
    private static SyncRecordFlaw RuleFlaw(string code) => code switch {
        BrowserRuleCodes.DuplicateSyncRecord => SyncRecordFlaw.DuplicateRecord,
        BrowserRuleCodes.SyncRecordLimit => SyncRecordFlaw.TooManyRecords,
        BrowserRuleCodes.SyncIdentityMismatch => SyncRecordFlaw.IdentityMismatch,
        BrowserRuleCodes.InvalidFolderTree => SyncRecordFlaw.InvalidFolderHierarchy,
        BrowserRuleCodes.InvalidSyncRecord or BrowserRuleCodes.InvalidSyncDeletion or BrowserRuleCodes.InvalidSyncDate
            or BrowserRuleCodes.InvalidSyncKind or BrowserRuleCodes.InvalidSyncPlacement or BrowserRuleCodes.InvalidIdentity
            or BrowserRuleCodes.InvalidSavedDate or BrowserRuleCodes.InvalidSavedIdentity or BrowserRuleCodes.InvalidSavedState
            or BrowserRuleCodes.InvalidSavedUrl => SyncRecordFlaw.MalformedRecord,
        _ => SyncRecordFlaw.Unexpected
    };

    #endregion
}
