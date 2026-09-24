using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;

using CrestCore.Application;
using CrestCore.Contracts;

namespace CrestCore.Native;

public static unsafe partial class Exports {
    #region Actions - Validation

    /// A durable save that failed answers STORAGE_FAILED; anything else is a
    /// session error.
    private static int DurableError(Exception error) => error switch {
        StorageException => CoreStatus.StorageFailed,
        Rejected => CoreStatus.InvalidMessage,
        InvalidOperationException => CoreStatus.InvalidState,
        _ => SessionError(error)
    };

    #endregion

    #region Actions - Stored session

    [UnmanagedCallersOnly(EntryPoint = "crest_app_session", CallConvs = [typeof(CallConvCdecl)])]
    public static int AppSession(ulong app, ulong* session, ulong* revision, ulong* sync, ulong* projection) {
        if (session == null || revision == null || sync == null || projection == null) return CoreStatus.InvalidArgument;
        *session = 0; *revision = 0; *sync = 0; *projection = 0;
        ulong sessionId = 0, syncId = 0, projectionId = 0;
        try {
            if (!Apps.TryGetValue(app, out var crest)) return CoreStatus.InvalidHandle;
            if (crest.Session is not { } owned || crest.SessionSync is not { } component || crest.SessionProjection() is not { } answer)
                return CoreStatus.Empty;
            sessionId = checked((ulong)Interlocked.Increment(ref nextHandle));
            syncId = checked((ulong)Interlocked.Increment(ref nextHandle));
            projectionId = checked((ulong)Interlocked.Increment(ref nextHandle));
            if (!Sessions.TryAdd(sessionId, owned) || !SyncAuthorities.TryAdd(syncId, component)
                || !SessionCommands.TryAdd(projectionId, answer))
                throw new InvalidOperationException(ProtocolErrorCodes.HandleCollision);
            *session = sessionId; *revision = owned.Revision; *sync = syncId; *projection = projectionId;
            return CoreStatus.Ok;
        } catch {
            Sessions.TryRemove(sessionId, out _); SyncAuthorities.TryRemove(syncId, out _); SessionCommands.TryRemove(projectionId, out _);
            return CoreStatus.InternalError;
        }
    }

    [UnmanagedCallersOnly(EntryPoint = "crest_app_install_session", CallConvs = [typeof(CallConvCdecl)])]
    public static int AppInstallSession(ulong app, byte* session, nuint sessionLength, byte* journal, nuint journalLength) {
        if (!ValidSessionInput(session, sessionLength) || journal == null && journalLength != 0) return CoreStatus.InvalidArgument;
        if (journalLength > NativeSyncJournal.MaximumBytes) return CoreStatus.LimitExceeded;
        try {
            if (!Apps.TryGetValue(app, out var crest)) return CoreStatus.InvalidHandle;
            crest.InstallSession(new ReadOnlySpan<byte>(session, (int)sessionLength), new ReadOnlySpan<byte>(journal, (int)journalLength));
            return CoreStatus.Ok;
        } catch (Exception error) { return DurableError(error); }
    }

    #endregion

    #region Actions - Durable commits

    [UnmanagedCallersOnly(EntryPoint = "crest_session_commit_command_durably", CallConvs = [typeof(CallConvCdecl)])]
    public static int SessionCommitCommandDurably(ulong command, ulong transaction, ulong* revision) {
        if (revision == null) return CoreStatus.InvalidArgument;
        *revision = 0;
        if (!SessionCommands.TryGetValue(command, out var prepared)) return CoreStatus.InvalidHandle;
        NativeSyncTransaction? sync = null;
        if (transaction != 0 && !SyncTransactions.TryGetValue(transaction, out sync)) return CoreStatus.InvalidHandle;
        try {
            *revision = prepared.Commit(Durability.BeforeReturn, sync);
            return CoreStatus.Ok;
        } catch (Exception error) { return DurableError(error); }
    }

    [UnmanagedCallersOnly(EntryPoint = "crest_session_replace_durably", CallConvs = [typeof(CallConvCdecl)])]
    public static int SessionReplaceDurably(ulong handle, ulong expected, ulong transaction, byte* delta, nuint count, ulong* revision) {
        if (revision == null) return CoreStatus.InvalidArgument;
        *revision = 0;
        if (!ValidSessionInput(delta, count)) return CoreStatus.InvalidArgument;
        if (!Sessions.TryGetValue(handle, out var session)) return CoreStatus.InvalidHandle;
        NativeSyncTransaction? sync = null;
        if (transaction != 0 && !SyncTransactions.TryGetValue(transaction, out sync)) return CoreStatus.InvalidHandle;
        try {
            *revision = session.ReplaceDurably(expected, new(delta, (int)count), sync);
            return CoreStatus.Ok;
        } catch (Exception error) { return DurableError(error); }
    }

    #endregion
}
