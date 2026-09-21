using System.Collections.Concurrent;
using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;

using CrestCore.Application;
using CrestCore.Domain;

namespace CrestCore.Native;

public static unsafe partial class Exports {
    #region Variables

    private static readonly ConcurrentDictionary<ulong, SpaceAccessAuthority> AccessAuthorities = new();

    #endregion

    #region Actions - Native exports

    private static bool AccessIdentity(byte* space, byte* profile, out SpaceAccessAssignment assignment) {
        assignment = default;
        if (space == null || profile == null) return false;
        assignment = new(new Guid(new ReadOnlySpan<byte>(space, 16), bigEndian: true),
            new Guid(new ReadOnlySpan<byte>(profile, 16), bigEndian: true));
        return assignment.Space != Guid.Empty && assignment.Profile != Guid.Empty;
    }

    [UnmanagedCallersOnly(EntryPoint = "crest_access_create", CallConvs = [typeof(CallConvCdecl)])]
    public static int AccessCreate(ulong* handle) {
        if (handle == null) return CoreStatus.InvalidArgument;
        *handle = 0;
        try {
            var id = checked((ulong)Interlocked.Increment(ref nextHandle));
            if (!AccessAuthorities.TryAdd(id, new())) return CoreStatus.InternalError;
            *handle = id;
            return CoreStatus.Ok;
        } catch { return CoreStatus.InternalError; }
    }

    [UnmanagedCallersOnly(EntryPoint = "crest_session_attach_access", CallConvs = [typeof(CallConvCdecl)])]
    public static int SessionAttachAccess(ulong session, ulong access) {
        try {
            if (!Sessions.TryGetValue(session, out var authority)) return CoreStatus.InvalidHandle;
            if (!AccessAuthorities.TryGetValue(access, out var grants)) return CoreStatus.InvalidHandle;
            authority.AttachAccess(grants);
            return CoreStatus.Ok;
        } catch (Exception e) { return SessionError(e); }
    }

    [UnmanagedCallersOnly(EntryPoint = "crest_access_is_locked", CallConvs = [typeof(CallConvCdecl)])]
    public static int AccessIsLocked(ulong handle, byte* space, byte* profile, int required, int* locked) {
        if (locked == null) return CoreStatus.InvalidArgument;
        *locked = 1;
        try {
            if (required is not (0 or 1) || !AccessIdentity(space, profile, out var assignment)) return CoreStatus.InvalidArgument;
            if (!AccessAuthorities.TryGetValue(handle, out var access)) return CoreStatus.InvalidHandle;
            lock (access) *locked = access.IsLocked(assignment, required == 1) ? 1 : 0;
            return CoreStatus.Ok;
        } catch { return CoreStatus.InternalError; }
    }

    [UnmanagedCallersOnly(EntryPoint = "crest_access_begin", CallConvs = [typeof(CallConvCdecl)])]
    public static int AccessBegin(ulong handle, byte* space, byte* profile, int required, ulong* request) {
        if (request == null) return CoreStatus.InvalidArgument;
        *request = 0;
        try {
            if (required is not (0 or 1) || !AccessIdentity(space, profile, out var assignment)) return CoreStatus.InvalidArgument;
            if (!AccessAuthorities.TryGetValue(handle, out var access)) return CoreStatus.InvalidHandle;
            lock (access) *request = access.Begin(assignment, required == 1);
            return CoreStatus.Ok;
        } catch (BrowserRuleException error) when (error.Code == "authentication_busy") { return CoreStatus.Busy; } catch { return CoreStatus.InternalError; }
    }

    [UnmanagedCallersOnly(EntryPoint = "crest_access_complete", CallConvs = [typeof(CallConvCdecl)])]
    public static int AccessComplete(ulong handle, byte* space, byte* profile, ulong request, int succeeded) {
        try {
            if (request == 0 || succeeded is not (0 or 1) || !AccessIdentity(space, profile, out var assignment))
                return CoreStatus.InvalidArgument;
            if (!AccessAuthorities.TryGetValue(handle, out var access)) return CoreStatus.InvalidHandle;
            lock (access) return access.Complete(request, assignment, succeeded == 1) is null
                ? CoreStatus.InvalidState : CoreStatus.Ok;
        } catch { return CoreStatus.InternalError; }
    }

    [UnmanagedCallersOnly(EntryPoint = "crest_access_lock_space", CallConvs = [typeof(CallConvCdecl)])]
    public static int AccessLockSpace(ulong handle, byte* space) {
        if (space == null) return CoreStatus.InvalidArgument;
        try {
            var id = new Guid(new ReadOnlySpan<byte>(space, 16), bigEndian: true);
            if (id == Guid.Empty) return CoreStatus.InvalidArgument;
            if (!AccessAuthorities.TryGetValue(handle, out var access)) return CoreStatus.InvalidHandle;
            lock (access) access.Lock(id);
            return CoreStatus.Ok;
        } catch { return CoreStatus.InternalError; }
    }

    [UnmanagedCallersOnly(EntryPoint = "crest_access_lock_all", CallConvs = [typeof(CallConvCdecl)])]
    public static int AccessLockAll(ulong handle, int inactiveScene, int* applied) {
        if (applied == null) return CoreStatus.InvalidArgument;
        *applied = 0;
        if (inactiveScene is not (0 or 1)) return CoreStatus.InvalidArgument;
        try {
            if (!AccessAuthorities.TryGetValue(handle, out var access)) return CoreStatus.InvalidHandle;
            lock (access) *applied = access.LockAll(inactiveScene == 1) ? 1 : 0;
            return CoreStatus.Ok;
        } catch { return CoreStatus.InternalError; }
    }

    [UnmanagedCallersOnly(EntryPoint = "crest_access_destroy", CallConvs = [typeof(CallConvCdecl)])]
    public static int AccessDestroy(ulong handle) {
        try { return AccessAuthorities.TryRemove(handle, out _) ? CoreStatus.Ok : CoreStatus.InvalidHandle; } catch { return CoreStatus.InternalError; }
    }

    #endregion
}
