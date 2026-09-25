using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;

using CrestCore.Application;
using CrestCore.Contracts;

namespace CrestCore.Native;

public static unsafe partial class Exports {
    #region Actions - Stored session

    /// TRANSITIONAL until typed sync (slice 8): the sync component of the
    /// session the app keeps in its file, for the journal calls. EMPTY while
    /// the app keeps no file or its file holds no session yet.
    [UnmanagedCallersOnly(EntryPoint = "crest_app_sync", CallConvs = [typeof(CallConvCdecl)])]
    public static int AppSync(ulong app, ulong* sync) {
        if (sync == null) return CoreStatus.InvalidArgument;
        *sync = 0;
        try {
            if (!Apps.TryGetValue(app, out var crest)) return CoreStatus.InvalidHandle;
            if (crest.StoredSync is not { } component) return CoreStatus.Empty;
            var id = checked((ulong)Interlocked.Increment(ref nextHandle));
            if (!SyncAuthorities.TryAdd(id, component)) return CoreStatus.InternalError;
            *sync = id;
            return CoreStatus.Ok;
        } catch {
            return CoreStatus.InternalError;
        }
    }

    #endregion
}
