using System.Collections.Concurrent;
using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
using CrestCore.Application;
using CrestCore.Domain;

namespace CrestCore.Native;

public static unsafe partial class Exports
{
    private static readonly ConcurrentDictionary<ulong, NativeSyncJournal> SyncJournals = new();
    private static int SyncJournalError(Exception error) => error is BrowserRuleException rule
        ? rule.Code switch { "sync_clock_exhausted" => CoreStatus.InvalidState, "version_mismatch" => CoreStatus.VersionMismatch,
            "sync_size_limit" or "sync_record_limit" => CoreStatus.LimitExceeded, _ => CoreStatus.InvalidMessage }
        : CoreStatus.InvalidMessage;

    [UnmanagedCallersOnly(EntryPoint = "crest_sync_journal_create", CallConvs = [typeof(CallConvCdecl)])]
    public static int SyncJournalCreate(byte* input, nuint count, ulong* handle)
    {
        if (handle == null) return CoreStatus.InvalidArgument;
        *handle = 0;
        if (input == null || count == 0) return CoreStatus.InvalidArgument;
        if (count > NativeSyncJournal.MaximumBytes) return CoreStatus.LimitExceeded;
        try
        {
            var journal = new NativeSyncJournal(new(input, (int)count));
            var id = checked((ulong)Interlocked.Increment(ref nextHandle));
            if (!SyncJournals.TryAdd(id, journal)) return CoreStatus.InternalError;
            *handle = id; return CoreStatus.Ok;
        }
        catch (Exception error) { return SyncJournalError(error); }
    }

    [UnmanagedCallersOnly(EntryPoint = "crest_sync_journal_apply", CallConvs = [typeof(CallConvCdecl)])]
    public static int SyncJournalApply(ulong handle, byte* input, nuint count, ulong* result)
        => ApplySyncJournal(handle, input, count, result, null);

    [UnmanagedCallersOnly(EntryPoint = "crest_sync_journal_apply_checked", CallConvs = [typeof(CallConvCdecl)])]
    public static int SyncJournalApplyChecked(ulong handle, byte* input, nuint count, ulong* result, ulong* errorResult)
    {
        if (errorResult == null) return CoreStatus.InvalidArgument;
        *errorResult = 0;
        return ApplySyncJournal(handle, input, count, result, errorResult);
    }

    private static int ApplySyncJournal(ulong handle, byte* input, nuint count, ulong* result, ulong* errorResult)
    {
        if (result == null) return CoreStatus.InvalidArgument;
        *result = 0;
        if (input == null || count == 0) return CoreStatus.InvalidArgument;
        if (count > NativeSyncJournal.MaximumBytes) return CoreStatus.LimitExceeded;
        if (!SyncJournals.TryGetValue(handle, out var journal)) return CoreStatus.InvalidHandle;
        try
        {
            var next = journal.Apply(new(input, (int)count));
            var id = checked((ulong)Interlocked.Increment(ref nextHandle));
            if (!SyncJournals.TryAdd(id, next)) return CoreStatus.InternalError;
            *result = id; return CoreStatus.Ok;
        }
        catch (NativeSyncDocumentException error)
        {
            if (errorResult != null)
            {
                try { *errorResult = RetainSyncQuery(NativeSyncQuery.Failure(error)); }
                catch { return CoreStatus.InternalError; }
            }
            return CoreStatus.InvalidMessage;
        }
        catch (Exception error) { return SyncJournalError(error); }
    }

    [UnmanagedCallersOnly(EntryPoint = "crest_sync_journal_read", CallConvs = [typeof(CallConvCdecl)])]
    public static int SyncJournalRead(ulong handle, byte* destination, nuint capacity, nuint* length)
    {
        if (length == null) return CoreStatus.InvalidArgument;
        *length = 0;
        if (destination == null && capacity != 0) return CoreStatus.InvalidArgument;
        if (capacity > NativeSyncJournal.MaximumBytes) return CoreStatus.LimitExceeded;
        if (!SyncJournals.TryGetValue(handle, out var journal)) return CoreStatus.InvalidHandle;
        try
        {
            var bytes = journal.Read();
            *length = (nuint)bytes.Length;
            if (capacity < *length) return CoreStatus.BufferTooSmall;
            bytes.CopyTo(new Span<byte>(destination, (int)capacity)); return CoreStatus.Ok;
        }
        catch (Exception error) { return SyncJournalError(error); }
    }

    [UnmanagedCallersOnly(EntryPoint = "crest_sync_journal_release", CallConvs = [typeof(CallConvCdecl)])]
    public static int SyncJournalRelease(ulong handle) => SyncJournals.TryRemove(handle, out _) ? CoreStatus.Ok : CoreStatus.InvalidHandle;
}
