using System.Collections.Concurrent;
using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.Json.Nodes;

using CrestCore.Application;
using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Native;

public static unsafe partial class Exports {
    #region Variables

    private static readonly ConcurrentDictionary<ulong, NativeSessionAuthority> Sessions = new();
    private static readonly ConcurrentDictionary<ulong, NativeSessionCommand> SessionCommands = new();

    #endregion

    #region Actions - Validation

    private static bool ValidSessionInput(byte* bytes, nuint count) => bytes != null && count is > 0 and <= NativeSessionAuthority.MaximumBytes;

    /// A command prepared against a state the session has since replaced
    /// answers INVALID_STATE; any other refusal is INVALID_MESSAGE.
    private static int SessionError(Exception error) => error is Rejected { Rejection: StaleCommand }
        ? CoreStatus.InvalidState : CoreStatus.InvalidMessage;

    #endregion

    #region Actions - Session lifecycle

    [UnmanagedCallersOnly(EntryPoint = "crest_session_create", CallConvs = [typeof(CallConvCdecl)])]
    public static int SessionCreate(byte* bytes, nuint count, ulong* handle) {
        if (handle == null) return CoreStatus.InvalidArgument;
        *handle = 0;
        if (!ValidSessionInput(bytes, count)) return CoreStatus.InvalidArgument;
        try {
            var session = new NativeSessionAuthority(new(bytes, (int)count));
            var id = checked((ulong)Interlocked.Increment(ref nextHandle));
            if (!Sessions.TryAdd(id, session)) return CoreStatus.InternalError;
            *handle = id; return CoreStatus.Ok;
        } catch (Exception e) { return SessionError(e); }
    }

    [UnmanagedCallersOnly(EntryPoint = "crest_session_create_borrowed", CallConvs = [typeof(CallConvCdecl)])]
    public static int SessionCreateBorrowed(ulong source, byte* bytes, nuint count, ulong* handle) {
        if (handle == null) return CoreStatus.InvalidArgument;
        *handle = 0;
        if (!ValidSessionInput(bytes, count) || count > 1024) return CoreStatus.InvalidArgument;
        if (!Sessions.TryGetValue(source, out var owner)) return CoreStatus.InvalidHandle;
        try {
            var request = JsonNode.Parse(new ReadOnlySpan<byte>(bytes, (int)count))!;
            var child = owner.CreateBorrowed(Guid.Parse(request["spaceId"]!.GetValue<string>()),
                Guid.Parse(request["profileId"]!.GetValue<string>()));
            var childId = checked((ulong)Interlocked.Increment(ref nextHandle));
            if (!Sessions.TryAdd(childId, child)) { child.Release(); return CoreStatus.InternalError; }
            *handle = childId;
            return CoreStatus.Ok;
        } catch (Exception e) { return SessionError(e); }
    }

    [UnmanagedCallersOnly(EntryPoint = "crest_session_prepare_borrowed_refresh", CallConvs = [typeof(CallConvCdecl)])]
    public static int SessionPrepareBorrowedRefresh(ulong handle, ulong* command) {
        if (command == null) return CoreStatus.InvalidArgument;
        *command = 0;
        if (!Sessions.TryGetValue(handle, out var session)) return CoreStatus.InvalidHandle;
        try {
            var value = session.PrepareBorrowedRefresh();
            var id = checked((ulong)Interlocked.Increment(ref nextHandle));
            if (!SessionCommands.TryAdd(id, value)) return CoreStatus.InternalError;
            *command = id; return CoreStatus.Ok;
        } catch (Exception e) { return SessionError(e); }
    }

    /// Attaches a session to an app's device so its windows may show it, and
    /// writes the workspace identity the core gave it (16 RFC 4122 bytes).
    [UnmanagedCallersOnly(EntryPoint = "crest_session_attach_device", CallConvs = [typeof(CallConvCdecl)])]
    public static int SessionAttachDevice(ulong handle, ulong app, byte* workspace) {
        if (workspace == null) return CoreStatus.InvalidArgument;
        if (!Sessions.TryGetValue(handle, out var session) || !Apps.TryGetValue(app, out var crest)) return CoreStatus.InvalidHandle;
        try {
            return crest.AttachWorkspace(session).TryWriteBytes(new Span<byte>(workspace, 16), bigEndian: true, out _)
                ? CoreStatus.Ok : CoreStatus.InternalError;
        } catch (Exception e) { return SessionError(e); }
    }

    [UnmanagedCallersOnly(EntryPoint = "crest_session_destroy", CallConvs = [typeof(CallConvCdecl)])]
    public static int SessionDestroy(ulong handle) {
        if (!Sessions.TryRemove(handle, out var session)) return CoreStatus.InvalidHandle;
        session.Release(); return CoreStatus.Ok;
    }

    #endregion

    #region Actions - Commands

    [UnmanagedCallersOnly(EntryPoint = "crest_session_prepare_command", CallConvs = [typeof(CallConvCdecl)])]
    public static int SessionPrepareCommand(ulong handle, byte* bytes, nuint count, ulong* command) {
        if (command == null) return CoreStatus.InvalidArgument;
        *command = 0;
        if (!ValidSessionInput(bytes, count)) return CoreStatus.InvalidArgument;
        if (!Sessions.TryGetValue(handle, out var session)) return CoreStatus.InvalidHandle;
        try {
            var prepared = session.PrepareCommand(new(bytes, (int)count));
            var id = checked((ulong)Interlocked.Increment(ref nextHandle));
            if (!SessionCommands.TryAdd(id, prepared)) return CoreStatus.InternalError;
            *command = id; return CoreStatus.Ok;
        } catch (Exception e) { return SessionError(e); }
    }

    [UnmanagedCallersOnly(EntryPoint = "crest_session_read_command", CallConvs = [typeof(CallConvCdecl)])]
    public static int SessionReadCommand(ulong handle, byte* destination, nuint capacity, nuint* length) {
        if (length == null || destination == null && capacity != 0) return CoreStatus.InvalidArgument;
        *length = 0;
        if (capacity > NativeSessionAuthority.MaximumBytes) return CoreStatus.LimitExceeded;
        if (!SessionCommands.TryGetValue(handle, out var command)) return CoreStatus.InvalidHandle;
        try {
            *length = (nuint)command.Output.Length;
            if (capacity < *length) return CoreStatus.BufferTooSmall;
            command.Output.CopyTo(new Span<byte>(destination, (int)capacity)); return CoreStatus.Ok;
        } catch (Exception e) { return SessionError(e); }
    }

    [UnmanagedCallersOnly(EntryPoint = "crest_session_commit_command", CallConvs = [typeof(CallConvCdecl)])]
    public static int SessionCommitCommand(ulong handle) {
        if (!SessionCommands.TryGetValue(handle, out var command)) return CoreStatus.InvalidHandle;
        try { command.Commit(); return CoreStatus.Ok; } catch (Exception e) { return DurableError(e); }
    }

    [UnmanagedCallersOnly(EntryPoint = "crest_session_release_command", CallConvs = [typeof(CallConvCdecl)])]
    public static int SessionReleaseCommand(ulong handle) => SessionCommands.TryRemove(handle, out _) ? CoreStatus.Ok : CoreStatus.InvalidHandle;

    #endregion
}
