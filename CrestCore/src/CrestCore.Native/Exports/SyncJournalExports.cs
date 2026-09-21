using System.Collections.Concurrent;
using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;

using CrestCore.Application;
using CrestCore.Domain;

namespace CrestCore.Native;

public static unsafe partial class Exports {
    #region Variables

    private static readonly ConcurrentDictionary<ulong, NativeSyncJournal> SyncJournals = new();

    #endregion

    #region Actions - Native exports

    private static int SyncJournalError(Exception error) => error is BrowserRuleException rule
        ? rule.Code switch {
            BrowserRuleCodes.SyncClockExhausted => CoreStatus.InvalidState,
            BrowserRuleCodes.VersionMismatch => CoreStatus.VersionMismatch,
            BrowserRuleCodes.SyncSizeLimit or BrowserRuleCodes.SyncRecordLimit => CoreStatus.LimitExceeded,
            _ => CoreStatus.InvalidMessage
        }
        : CoreStatus.InvalidMessage;

    [UnmanagedCallersOnly(EntryPoint = "crest_sync_journal_create", CallConvs = [typeof(CallConvCdecl)])]
    public static int SyncJournalCreate(byte* input, nuint count, ulong* handle) {
        if (handle == null) return CoreStatus.InvalidArgument;
        *handle = 0;
        if (input == null || count == 0) return CoreStatus.InvalidArgument;
        if (count > NativeSyncJournal.MaximumBytes) return CoreStatus.LimitExceeded;
        try {
            var journal = new NativeSyncJournal(new(input, (int)count));
            var id = checked((ulong)Interlocked.Increment(ref nextHandle));
            if (!SyncJournals.TryAdd(id, journal)) return CoreStatus.InternalError;
            *handle = id; return CoreStatus.Ok;
        } catch (Exception error) { return SyncJournalError(error); }
    }

    [UnmanagedCallersOnly(EntryPoint = "crest_sync_journal_apply", CallConvs = [typeof(CallConvCdecl)])]
    public static int SyncJournalApply(ulong handle, byte* input, nuint count, ulong* result)
        => ApplySyncJournal(handle, input, count, result, null);

    [UnmanagedCallersOnly(EntryPoint = "crest_sync_journal_apply_checked", CallConvs = [typeof(CallConvCdecl)])]
    public static int SyncJournalApplyChecked(ulong handle, byte* input, nuint count, ulong* result, ulong* errorResult) {
        if (errorResult == null) return CoreStatus.InvalidArgument;
        *errorResult = 0;
        return ApplySyncJournal(handle, input, count, result, errorResult);
    }

    private static int ApplySyncJournal(ulong handle, byte* input, nuint count, ulong* result, ulong* errorResult) {
        if (result == null) return CoreStatus.InvalidArgument;
        *result = 0;
        if (input == null || count == 0) return CoreStatus.InvalidArgument;
        if (count > NativeSyncJournal.MaximumBytes) return CoreStatus.LimitExceeded;
        if (!SyncJournals.TryGetValue(handle, out var journal)) return CoreStatus.InvalidHandle;
        try {
            var next = journal.Apply(new(input, (int)count));
            var id = checked((ulong)Interlocked.Increment(ref nextHandle));
            if (!SyncJournals.TryAdd(id, next)) return CoreStatus.InternalError;
            *result = id; return CoreStatus.Ok;
        } catch (NativeSyncDocumentException error) {
            if (errorResult != null) {
                try { *errorResult = RetainSyncQuery(NativeSyncQuery.Failure(error)); } catch { return CoreStatus.InternalError; }
            }
            return CoreStatus.InvalidMessage;
        } catch (Exception error) { return SyncJournalError(error); }
    }

    [UnmanagedCallersOnly(EntryPoint = "crest_sync_journal_read", CallConvs = [typeof(CallConvCdecl)])]
    public static int SyncJournalRead(ulong handle, byte* destination, nuint capacity, nuint* length) {
        if (length == null) return CoreStatus.InvalidArgument;
        *length = 0;
        if (destination == null && capacity != 0) return CoreStatus.InvalidArgument;
        if (capacity > NativeSyncJournal.MaximumBytes) return CoreStatus.LimitExceeded;
        if (!SyncJournals.TryGetValue(handle, out var journal)) return CoreStatus.InvalidHandle;
        try {
            var bytes = journal.Read();
            *length = (nuint)bytes.Length;
            if (capacity < *length) return CoreStatus.BufferTooSmall;
            bytes.CopyTo(new Span<byte>(destination, (int)capacity)); return CoreStatus.Ok;
        } catch (Exception error) { return SyncJournalError(error); }
    }

    [UnmanagedCallersOnly(EntryPoint = "crest_sync_journal_release", CallConvs = [typeof(CallConvCdecl)])]
    public static int SyncJournalRelease(ulong handle) => SyncJournals.TryRemove(handle, out _) ? CoreStatus.Ok : CoreStatus.InvalidHandle;

    [UnmanagedCallersOnly(EntryPoint = "crest_sync_session_prepare", CallConvs = [typeof(CallConvCdecl)])]
    public static int SyncSessionPrepare(ulong handle, byte* input, nuint count, ulong* nextJournal, ulong* query) {
        if (nextJournal == null || query == null) return CoreStatus.InvalidArgument;
        *nextJournal = 0; *query = 0;
        if (input == null || count == 0) return CoreStatus.InvalidArgument;
        if (count > NativeSyncJournal.MaximumBytes) return CoreStatus.LimitExceeded;
        if (!SyncJournals.TryGetValue(handle, out var journal)) return CoreStatus.InvalidHandle;
        ulong retainedJournal = 0;
        try {
            var transition = NativeSyncSessionTransition.Prepare(journal, new(input, (int)count));
            // Serialize both candidates before publishing either handle. An
            // oversized result cannot hand the caller half a transition.
            _ = transition.Journal.Read();
            var result = NativeSyncQuery.Success(transition.Materialization);
            var id = checked((ulong)Interlocked.Increment(ref nextHandle));
            if (!SyncJournals.TryAdd(id, transition.Journal)) return CoreStatus.InternalError;
            retainedJournal = id;
            *query = RetainSyncQuery(result); *nextJournal = id;
            return CoreStatus.Ok;
        } catch (Exception error) {
            if (retainedJournal != 0) SyncJournals.TryRemove(retainedJournal, out _);
            if (error is NativeSyncDocumentException semantic) {
                try { *query = RetainSyncQuery(NativeSyncQuery.Failure(semantic)); } catch { return CoreStatus.InternalError; }
            }
            return SyncJournalError(error);
        }
    }

    #endregion
}
