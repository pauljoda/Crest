using System.Collections.Concurrent;
using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;

using CrestCore.Application;

namespace CrestCore.Native;

public static unsafe partial class Exports {
    private static readonly ConcurrentDictionary<ulong, byte[]> SyncQueries = new();
    private static ulong RetainSyncQuery(byte[] result) {
        var id = checked((ulong)Interlocked.Increment(ref nextHandle));
        if (!SyncQueries.TryAdd(id, result)) throw new InvalidOperationException("Duplicate sync query handle");
        return id;
    }

    [UnmanagedCallersOnly(EntryPoint = "crest_sync_query_prepare", CallConvs = [typeof(CallConvCdecl)])]
    public static int SyncQueryPrepare(byte* input, nuint count, ulong* handle) {
        if (handle == null) return CoreStatus.InvalidArgument;
        *handle = 0;
        if (input == null || count == 0) return CoreStatus.InvalidArgument;
        if (count > NativeSyncQuery.MaximumBytes) return CoreStatus.LimitExceeded;
        try {
            var result = NativeSyncQuery.Prepare(new(input, (int)count));
            *handle = RetainSyncQuery(result); return CoreStatus.Ok;
        } catch (Exception error) { return SyncJournalError(error); }
    }

    [UnmanagedCallersOnly(EntryPoint = "crest_sync_query_read", CallConvs = [typeof(CallConvCdecl)])]
    public static int SyncQueryRead(ulong handle, byte* destination, nuint capacity, nuint* length) {
        if (length == null) return CoreStatus.InvalidArgument;
        *length = 0;
        if (destination == null && capacity != 0) return CoreStatus.InvalidArgument;
        if (capacity > NativeSyncQuery.MaximumBytes) return CoreStatus.LimitExceeded;
        if (!SyncQueries.TryGetValue(handle, out var bytes)) return CoreStatus.InvalidHandle;
        *length = (nuint)bytes.Length;
        if (capacity < *length) return CoreStatus.BufferTooSmall;
        bytes.CopyTo(new Span<byte>(destination, (int)capacity)); return CoreStatus.Ok;
    }

    [UnmanagedCallersOnly(EntryPoint = "crest_sync_query_release", CallConvs = [typeof(CallConvCdecl)])]
    public static int SyncQueryRelease(ulong handle) => SyncQueries.TryRemove(handle, out _) ? CoreStatus.Ok : CoreStatus.InvalidHandle;
}
