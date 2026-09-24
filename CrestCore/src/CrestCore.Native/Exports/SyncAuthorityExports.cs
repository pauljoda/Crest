using System.Collections.Concurrent;
using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;

using CrestCore.Application;
using CrestCore.Contracts;

namespace CrestCore.Native;

public static unsafe partial class Exports {
    #region Variables

    private static readonly ConcurrentDictionary<ulong, NativeSyncAuthority> SyncAuthorities = new();
    private static readonly ConcurrentDictionary<ulong, NativeSyncTransaction> SyncTransactions = new();

    #endregion

    #region Actions - Native exports

    [UnmanagedCallersOnly(EntryPoint = "crest_sync_authority_create", CallConvs = [typeof(CallConvCdecl)])]
    public static int SyncAuthorityCreate(ulong journal, ulong* handle) {
        if (handle == null) return CoreStatus.InvalidArgument;
        *handle = 0;
        if (!SyncJournals.TryGetValue(journal, out var source)) return CoreStatus.InvalidHandle;
        try {
            var id = checked((ulong)Interlocked.Increment(ref nextHandle));
            if (!SyncAuthorities.TryAdd(id, new(source))) return CoreStatus.InternalError;
            *handle = id; return CoreStatus.Ok;
        } catch (Exception error) { return SyncJournalError(error); }
    }

    [UnmanagedCallersOnly(EntryPoint = "crest_sync_authority_snapshot", CallConvs = [typeof(CallConvCdecl)])]
    public static int SyncAuthoritySnapshot(ulong handle, ulong* journal) {
        if (journal == null) return CoreStatus.InvalidArgument;
        *journal = 0;
        if (!SyncAuthorities.TryGetValue(handle, out var owner)) return CoreStatus.InvalidHandle;
        try {
            var id = checked((ulong)Interlocked.Increment(ref nextHandle));
            if (!SyncJournals.TryAdd(id, owner.Snapshot)) return CoreStatus.InternalError;
            *journal = id; return CoreStatus.Ok;
        } catch (Exception error) { return SyncJournalError(error); }
    }

    [UnmanagedCallersOnly(EntryPoint = "crest_sync_authority_release", CallConvs = [typeof(CallConvCdecl)])]
    public static int SyncAuthorityRelease(ulong handle) => SyncAuthorities.TryRemove(handle, out _) ? CoreStatus.Ok : CoreStatus.InvalidHandle;

    [UnmanagedCallersOnly(EntryPoint = "crest_session_attach_sync", CallConvs = [typeof(CallConvCdecl)])]
    public static int SessionAttachSync(ulong session, ulong sync) {
        if (!Sessions.TryGetValue(session, out var owner) || !SyncAuthorities.TryGetValue(sync, out var value)) return CoreStatus.InvalidHandle;
        try { owner.AttachSync(value); return CoreStatus.Ok; } catch (Exception error) { return SyncJournalError(error); }
    }

    [UnmanagedCallersOnly(EntryPoint = "crest_sync_authority_version", CallConvs = [typeof(CallConvCdecl)])]
    public static int SyncAuthorityVersion(ulong handle, ulong* version) {
        if (version == null) return CoreStatus.InvalidArgument;
        *version = 0;
        if (!SyncAuthorities.TryGetValue(handle, out var owner)) return CoreStatus.InvalidHandle;
        *version = owner.Version; return CoreStatus.Ok;
    }

    [UnmanagedCallersOnly(EntryPoint = "crest_sync_authority_flush", CallConvs = [typeof(CallConvCdecl)])]
    public static int SyncAuthorityFlush(ulong handle) {
        if (!SyncAuthorities.TryGetValue(handle, out var owner)) return CoreStatus.InvalidHandle;
        owner.Flush(); return CoreStatus.Ok;
    }

    [UnmanagedCallersOnly(EntryPoint = "crest_sync_authority_prepare", CallConvs = [typeof(CallConvCdecl)])]
    public static int SyncAuthorityPrepare(ulong handle, byte* input, nuint count,
        ulong* transaction, ulong* journal, ulong* query) {
        if (transaction == null || journal == null || query == null) return CoreStatus.InvalidArgument;
        *transaction = 0; *journal = 0; *query = 0;
        if (input == null || count == 0) return CoreStatus.InvalidArgument;
        if (count > NativeSyncJournal.MaximumBytes) return CoreStatus.LimitExceeded;
        if (!SyncAuthorities.TryGetValue(handle, out var owner)) return CoreStatus.InvalidHandle;
        NativeSyncTransaction? value = null;
        ulong transactionId = 0, journalId = 0, queryId = 0;
        try {
            value = owner.Prepare(new(input, (int)count));
            transactionId = checked((ulong)Interlocked.Increment(ref nextHandle));
            journalId = checked((ulong)Interlocked.Increment(ref nextHandle));
            if (!SyncTransactions.TryAdd(transactionId, value) || !SyncJournals.TryAdd(journalId, value.Journal))
                throw new InvalidOperationException(ProtocolErrorCodes.HandleCollision);
            if (value.Materialization is { } bytes) queryId = RetainSyncQuery(bytes);
            *transaction = transactionId; *journal = journalId; *query = queryId;
            return CoreStatus.Ok;
        } catch (Exception error) {
            SyncTransactions.TryRemove(transactionId, out _); SyncJournals.TryRemove(journalId, out _);
            if (queryId != 0) SyncQueries.TryRemove(queryId, out _);
            value?.Dispose();
            if (error is NativeSyncDocumentException semantic) {
                try { *query = RetainSyncQuery(NativeSyncQuery.Failure(semantic)); } catch { return CoreStatus.InternalError; }
            }
            return SyncJournalError(error);
        }
    }

    [UnmanagedCallersOnly(EntryPoint = "crest_sync_transaction_seal", CallConvs = [typeof(CallConvCdecl)])]
    public static int SyncTransactionSeal(ulong handle, int* accepted) {
        if (accepted == null) return CoreStatus.InvalidArgument;
        *accepted = 0;
        if (!SyncTransactions.TryGetValue(handle, out var value)) return CoreStatus.InvalidHandle;
        try { *accepted = value.Seal() ? 1 : 0; return CoreStatus.Ok; } catch (Exception error) { return SyncJournalError(error); }
    }

    [UnmanagedCallersOnly(EntryPoint = "crest_sync_transaction_commit", CallConvs = [typeof(CallConvCdecl)])]
    public static int SyncTransactionCommit(ulong handle, ulong* version) {
        if (version == null) return CoreStatus.InvalidArgument;
        *version = 0;
        if (!SyncTransactions.TryGetValue(handle, out var value)) return CoreStatus.InvalidHandle;
        try {
            value.CommitDurably();
            *version = value.Version;
            return CoreStatus.Ok;
        } catch (StorageException) {
            return CoreStatus.StorageFailed;
        } catch (Exception error) { return SyncJournalError(error); }
    }

    [UnmanagedCallersOnly(EntryPoint = "crest_sync_transaction_release", CallConvs = [typeof(CallConvCdecl)])]
    public static int SyncTransactionRelease(ulong handle) {
        if (!SyncTransactions.TryRemove(handle, out var value)) return CoreStatus.InvalidHandle;
        value.Dispose(); return CoreStatus.Ok;
    }

    #endregion
}
