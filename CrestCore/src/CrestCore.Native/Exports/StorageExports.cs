using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;

using CrestCore.Application;
using CrestCore.Contracts;

namespace CrestCore.Native;

public static unsafe partial class Exports {
    #region Actions - Validation

    /// A durable save that failed answers STORAGE_FAILED, a session that
    /// cannot take the replacement now INVALID_STATE, and any other refusal
    /// INVALID_MESSAGE.
    private static int DurableError(Exception error) => error switch {
        StorageException => CoreStatus.StorageFailed,
        InvalidOperationException => CoreStatus.InvalidState,
        _ => CoreStatus.InvalidMessage
    };

    #endregion

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

    #region Actions - Durable commits

    /// TRANSITIONAL until slice 8a (typed sync).
    [UnmanagedCallersOnly(EntryPoint = "crest_session_replace_durably", CallConvs = [typeof(CallConvCdecl)])]
    public static int SessionReplaceDurably(ulong app, byte* workspace, ulong transaction, byte* delta, nuint count) {
        if (workspace == null || !ValidSessionInput(delta, count)) return CoreStatus.InvalidArgument;
        if (!Apps.TryGetValue(app, out var crest)) return CoreStatus.InvalidHandle;
        NativeSyncTransaction? sync = null;
        if (transaction != 0 && !SyncTransactions.TryGetValue(transaction, out sync)) return CoreStatus.InvalidHandle;
        try {
            crest.ReplaceDurably(Workspace(workspace), new(delta, (int)count), sync);
            return CoreStatus.Ok;
        } catch (Exception error) { return DurableError(error); }
    }

    #endregion
}
