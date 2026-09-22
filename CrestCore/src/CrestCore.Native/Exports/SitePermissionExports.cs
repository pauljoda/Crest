using System.Collections.Concurrent;
using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;

using CrestCore.Application;
using CrestCore.Contracts;

namespace CrestCore.Native;

public static unsafe partial class Exports {
    #region Variables

    private static readonly ConcurrentDictionary<ulong, NativeSitePermissionLedger> SitePermissionLedgers = new();

    #endregion

    #region Actions - Native exports

    [UnmanagedCallersOnly(EntryPoint = "crest_permissions_create", CallConvs = [typeof(CallConvCdecl)])]
    public static int PermissionsCreate(ulong* handle) {
        if (handle == null) return CoreStatus.InvalidArgument;
        *handle = 0;
        try {
            var id = checked((ulong)Interlocked.Increment(ref nextHandle));
            if (!SitePermissionLedgers.TryAdd(id, new())) return CoreStatus.InternalError;
            *handle = id;
            return CoreStatus.Ok;
        } catch { return CoreStatus.InternalError; }
    }

    [UnmanagedCallersOnly(EntryPoint = "crest_permissions_apply", CallConvs = [typeof(CallConvCdecl)])]
    public static int PermissionsApply(ulong handle, byte* input, nuint inputLength, nuint* length) {
        if (length == null) return CoreStatus.InvalidArgument;
        *length = 0;
        if (input == null || inputLength == 0) return CoreStatus.InvalidArgument;
        if (inputLength > NativeSitePermissionLedger.MaximumInputBytes) return CoreStatus.LimitExceeded;
        try {
            if (!SitePermissionLedgers.TryGetValue(handle, out var ledger)) return CoreStatus.InvalidHandle;
            lock (ledger) *length = (nuint)ledger.Apply(new ReadOnlySpan<byte>(input, (int)inputLength)).Length;
            return CoreStatus.Ok;
        } catch (ProtocolException error) { return error.Code == ProtocolErrorCodes.VersionMismatch ? CoreStatus.VersionMismatch : CoreStatus.InvalidMessage; } catch { return CoreStatus.InvalidMessage; }
    }

    [UnmanagedCallersOnly(EntryPoint = "crest_permissions_read", CallConvs = [typeof(CallConvCdecl)])]
    public static int PermissionsRead(ulong handle, byte* destination, nuint capacity, nuint* length) {
        if (length == null) return CoreStatus.InvalidArgument;
        *length = 0;
        if (destination == null && capacity != 0) return CoreStatus.InvalidArgument;
        try {
            if (!SitePermissionLedgers.TryGetValue(handle, out var ledger)) return CoreStatus.InvalidHandle;
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

    [UnmanagedCallersOnly(EntryPoint = "crest_permissions_destroy", CallConvs = [typeof(CallConvCdecl)])]
    public static int PermissionsDestroy(ulong handle) {
        try { return SitePermissionLedgers.TryRemove(handle, out _) ? CoreStatus.Ok : CoreStatus.InvalidHandle; } catch { return CoreStatus.InternalError; }
    }

    #endregion
}
