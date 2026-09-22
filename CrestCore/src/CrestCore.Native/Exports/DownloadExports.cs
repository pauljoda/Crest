using System.Collections.Concurrent;
using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;

using CrestCore.Application;
using CrestCore.Contracts;

namespace CrestCore.Native;

public static unsafe partial class Exports {
    #region Variables

    private static readonly ConcurrentDictionary<ulong, NativeDownloadLedger> DownloadLedgers = new();

    #endregion

    #region Actions - Native exports

    [UnmanagedCallersOnly(EntryPoint = "crest_downloads_create", CallConvs = [typeof(CallConvCdecl)])]
    public static int DownloadsCreate(ulong* handle) {
        if (handle == null) return CoreStatus.InvalidArgument;
        *handle = 0;
        try {
            var id = checked((ulong)Interlocked.Increment(ref nextHandle));
            if (!DownloadLedgers.TryAdd(id, new())) return CoreStatus.InternalError;
            *handle = id;
            return CoreStatus.Ok;
        } catch { return CoreStatus.InternalError; }
    }

    [UnmanagedCallersOnly(EntryPoint = "crest_downloads_apply", CallConvs = [typeof(CallConvCdecl)])]
    public static int DownloadsApply(ulong handle, byte* input, nuint inputLength, nuint* length) {
        if (length == null) return CoreStatus.InvalidArgument;
        *length = 0;
        if (input == null || inputLength == 0) return CoreStatus.InvalidArgument;
        if (inputLength > NativeDownloadLedger.MaximumInputBytes) return CoreStatus.LimitExceeded;
        try {
            if (!DownloadLedgers.TryGetValue(handle, out var ledger)) return CoreStatus.InvalidHandle;
            lock (ledger) *length = (nuint)ledger.Apply(new ReadOnlySpan<byte>(input, (int)inputLength)).Length;
            return CoreStatus.Ok;
        } catch (ProtocolException error) { return error.Code == ProtocolErrorCodes.VersionMismatch ? CoreStatus.VersionMismatch : CoreStatus.InvalidMessage; } catch { return CoreStatus.InvalidMessage; }
    }

    [UnmanagedCallersOnly(EntryPoint = "crest_downloads_read", CallConvs = [typeof(CallConvCdecl)])]
    public static int DownloadsRead(ulong handle, byte* destination, nuint capacity, nuint* length) {
        if (length == null) return CoreStatus.InvalidArgument;
        *length = 0;
        if (destination == null && capacity != 0) return CoreStatus.InvalidArgument;
        try {
            if (!DownloadLedgers.TryGetValue(handle, out var ledger)) return CoreStatus.InvalidHandle;
            lock (ledger) {
                var result = ledger.LastResult;
                if (result.Length == 0) return CoreStatus.Empty;
                *length = (nuint)result.Length;
                if (capacity < *length) return CoreStatus.BufferTooSmall;
                result.CopyTo(new Span<byte>(destination, result.Length));
                return CoreStatus.Ok;
            }
        } catch { return CoreStatus.InternalError; }
    }

    [UnmanagedCallersOnly(EntryPoint = "crest_downloads_destroy", CallConvs = [typeof(CallConvCdecl)])]
    public static int DownloadsDestroy(ulong handle) {
        try { return DownloadLedgers.TryRemove(handle, out _) ? CoreStatus.Ok : CoreStatus.InvalidHandle; } catch { return CoreStatus.InternalError; }
    }

    #endregion
}
