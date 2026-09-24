using System.Collections.Concurrent;
using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;

using CrestCore.Application;
using CrestCore.Contracts;

namespace CrestCore.Native;

public static unsafe partial class Exports {
    #region Variables

    private static readonly ConcurrentDictionary<ulong, NativeSessionTransfer> SessionTransfers = new();

    #endregion

    #region Actions - Native exports

    [UnmanagedCallersOnly(EntryPoint = "crest_session_prepare_transfer", CallConvs = [typeof(CallConvCdecl)])]
    public static int SessionPrepareTransfer(ulong source, ulong sourceRevision, ulong destination, ulong destinationRevision,
        byte* bytes, nuint count, ulong* transfer) {
        if (transfer == null) return CoreStatus.InvalidArgument;
        *transfer = 0;
        if (!ValidSessionInput(bytes, count)) return CoreStatus.InvalidArgument;
        if (!Sessions.TryGetValue(source, out var a) || !Sessions.TryGetValue(destination, out var b)) return CoreStatus.InvalidHandle;
        try {
            var value = NativeSessionAuthority.PrepareTransfer(a, sourceRevision, b, destinationRevision, new(bytes, (int)count));
            var id = checked((ulong)Interlocked.Increment(ref nextHandle));
            if (!SessionTransfers.TryAdd(id, value)) { value.Dispose(); return CoreStatus.InternalError; }
            *transfer = id; return CoreStatus.Ok;
        } catch (Exception e) { return SessionError(e); }
    }

    [UnmanagedCallersOnly(EntryPoint = "crest_session_read_transfer", CallConvs = [typeof(CallConvCdecl)])]
    public static int SessionReadTransfer(ulong handle, byte* destination, nuint capacity, nuint* length) {
        if (length == null || destination == null && capacity != 0) return CoreStatus.InvalidArgument;
        *length = 0;
        if (capacity > NativeSessionAuthority.MaximumEditBytes) return CoreStatus.LimitExceeded;
        if (!SessionTransfers.TryGetValue(handle, out var value)) return CoreStatus.InvalidHandle;
        *length = (nuint)value.Output.Length;
        if (capacity < *length) return CoreStatus.BufferTooSmall;
        value.Output.CopyTo(new Span<byte>(destination, (int)capacity)); return CoreStatus.Ok;
    }

    [UnmanagedCallersOnly(EntryPoint = "crest_session_commit_transfer", CallConvs = [typeof(CallConvCdecl)])]
    public static int SessionCommitTransfer(ulong handle, ulong transaction, ulong* sourceRevision, ulong* destinationRevision) {
        if (sourceRevision == null || destinationRevision == null) return CoreStatus.InvalidArgument;
        *sourceRevision = 0; *destinationRevision = 0;
        if (!SessionTransfers.TryGetValue(handle, out var value)) return CoreStatus.InvalidHandle;
        NativeSyncTransaction? sync = null;
        if (transaction != 0 && !SyncTransactions.TryGetValue(transaction, out sync)) return CoreStatus.InvalidHandle;
        try {
            var result = value.CommitDurably(sync);
            *sourceRevision = result.Source; *destinationRevision = result.Destination;
            return CoreStatus.Ok;
        } catch (Exception e) { return DurableError(e); }
    }

    [UnmanagedCallersOnly(EntryPoint = "crest_session_release_transfer", CallConvs = [typeof(CallConvCdecl)])]
    public static int SessionReleaseTransfer(ulong handle) {
        if (!SessionTransfers.TryRemove(handle, out var value)) return CoreStatus.InvalidHandle;
        value.Dispose(); return CoreStatus.Ok;
    }

    #endregion
}
