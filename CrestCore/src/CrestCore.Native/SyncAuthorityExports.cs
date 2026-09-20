using System.Collections.Concurrent;
using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
using CrestCore.Application;

namespace CrestCore.Native;

public static unsafe partial class Exports
{
    private static readonly ConcurrentDictionary<ulong, NativeSyncAuthority> SyncAuthorities = new();
    private static readonly ConcurrentDictionary<ulong, NativeSyncTransaction> SyncTransactions = new();

    [UnmanagedCallersOnly(EntryPoint = "crest_sync_authority_create", CallConvs = [typeof(CallConvCdecl)])]
    public static int SyncAuthorityCreate(ulong journal, ulong* handle)
    {
        if (handle == null) return CoreStatus.InvalidArgument;
        *handle = 0;
        if (!SyncJournals.TryGetValue(journal, out var source)) return CoreStatus.InvalidHandle;
        try
        {
            var id = checked((ulong)Interlocked.Increment(ref nextHandle));
            if (!SyncAuthorities.TryAdd(id, new(source))) return CoreStatus.InternalError;
            *handle = id; return CoreStatus.Ok;
        }
        catch (Exception error) { return SyncJournalError(error); }
    }
    [UnmanagedCallersOnly(EntryPoint = "crest_sync_authority_release", CallConvs = [typeof(CallConvCdecl)])]
    public static int SyncAuthorityRelease(ulong handle) => SyncAuthorities.TryRemove(handle, out _) ? CoreStatus.Ok : CoreStatus.InvalidHandle;

    [UnmanagedCallersOnly(EntryPoint = "crest_session_attach_sync", CallConvs = [typeof(CallConvCdecl)])]
    public static int SessionAttachSync(ulong session, ulong sync)
    {
        if (!Sessions.TryGetValue(session, out var owner) || !SyncAuthorities.TryGetValue(sync, out var value)) return CoreStatus.InvalidHandle;
        try { owner.AttachSync(value); return CoreStatus.Ok; }
        catch (Exception error) { return SyncJournalError(error); }
    }
    [UnmanagedCallersOnly(EntryPoint = "crest_sync_authority_advance", CallConvs = [typeof(CallConvCdecl)])]
    public static int SyncAuthorityAdvance(ulong handle, ulong revision)
    {
        if (!SyncAuthorities.TryGetValue(handle, out var owner)) return CoreStatus.InvalidHandle;
        owner.Advance(revision); return CoreStatus.Ok;
    }
    [UnmanagedCallersOnly(EntryPoint = "crest_sync_authority_prepare", CallConvs = [typeof(CallConvCdecl)])]
    public static int SyncAuthorityPrepare(ulong handle, int hasRevision, ulong revision, byte* input, nuint count,
        ulong* transaction, ulong* journal, ulong* query)
    {
        if (transaction == null || journal == null || query == null) return CoreStatus.InvalidArgument;
        *transaction = 0; *journal = 0; *query = 0;
        if (input == null || count == 0 || hasRevision is < 0 or > 1) return CoreStatus.InvalidArgument;
        if (count > NativeSyncJournal.MaximumBytes) return CoreStatus.LimitExceeded;
        if (!SyncAuthorities.TryGetValue(handle, out var owner)) return CoreStatus.InvalidHandle;
        NativeSyncTransaction? value = null;
        ulong transactionId = 0, journalId = 0, queryId = 0;
        try
        {
            value = owner.Prepare(hasRevision == 1 ? revision : null, new(input, (int)count));
            if (value is null) return CoreStatus.Ok; // Superseded local snapshot.
            transactionId = checked((ulong)Interlocked.Increment(ref nextHandle));
            journalId = checked((ulong)Interlocked.Increment(ref nextHandle));
            if (!SyncTransactions.TryAdd(transactionId, value) || !SyncJournals.TryAdd(journalId, value.Journal))
                throw new InvalidOperationException("handle_collision");
            if (value.Materialization is { } bytes) queryId = RetainSyncQuery(bytes);
            *transaction = transactionId; *journal = journalId; *query = queryId;
            return CoreStatus.Ok;
        }
        catch (Exception error)
        {
            SyncTransactions.TryRemove(transactionId, out _); SyncJournals.TryRemove(journalId, out _);
            if (queryId != 0) SyncQueries.TryRemove(queryId, out _);
            value?.Dispose();
            if (error is NativeSyncDocumentException semantic)
            {
                try { *query = RetainSyncQuery(NativeSyncQuery.Failure(semantic)); }
                catch { return CoreStatus.InternalError; }
            }
            return SyncJournalError(error);
        }
    }
    [UnmanagedCallersOnly(EntryPoint = "crest_sync_transaction_seal", CallConvs = [typeof(CallConvCdecl)])]
    public static int SyncTransactionSeal(ulong handle, int* accepted)
    {
        if (accepted == null) return CoreStatus.InvalidArgument;
        *accepted = 0;
        if (!SyncTransactions.TryGetValue(handle, out var value)) return CoreStatus.InvalidHandle;
        try { *accepted = value.Seal() ? 1 : 0; return CoreStatus.Ok; }
        catch (Exception error) { return SyncJournalError(error); }
    }
    [UnmanagedCallersOnly(EntryPoint = "crest_sync_transaction_commit", CallConvs = [typeof(CallConvCdecl)])]
    public static int SyncTransactionCommit(ulong handle)
    {
        if (!SyncTransactions.TryGetValue(handle, out var value)) return CoreStatus.InvalidHandle;
        try { value.Commit(); return CoreStatus.Ok; }
        catch (Exception error) { return SyncJournalError(error); }
    }
    [UnmanagedCallersOnly(EntryPoint = "crest_sync_transaction_release", CallConvs = [typeof(CallConvCdecl)])]
    public static int SyncTransactionRelease(ulong handle)
    {
        if (!SyncTransactions.TryRemove(handle, out var value)) return CoreStatus.InvalidHandle;
        value.Dispose(); return CoreStatus.Ok;
    }
    [UnmanagedCallersOnly(EntryPoint = "crest_session_bind_sync_replacement", CallConvs = [typeof(CallConvCdecl)])]
    public static int SessionBindSyncReplacement(ulong replacement, ulong transaction)
    {
        if (!SessionReplacements.TryGetValue(replacement, out var target) || !SyncTransactions.TryGetValue(transaction, out var source))
            return CoreStatus.InvalidHandle;
        try { target.BindSync(source); return CoreStatus.Ok; }
        catch (Exception error) { return SyncJournalError(error); }
    }
}
