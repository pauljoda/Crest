using System.Collections.Concurrent;
using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;

using CrestCore.Application;
using CrestCore.Contracts;

namespace CrestCore.Native;

/// TRANSITIONAL until S5.8c: the JSON session commands that remain, which name
/// the workspace they act on by the identity the core published for it.
public static unsafe partial class Exports {
    #region Variables

    private static readonly ConcurrentDictionary<ulong, NativeSessionCommand> SessionCommands = new();

    #endregion

    #region Actions - Validation

    private static bool ValidSessionInput(byte* bytes, nuint count) => bytes != null && count is > 0 and <= NativeSessionAuthority.MaximumBytes;

    /// A command prepared against a state the session has since replaced
    /// answers INVALID_STATE; any other refusal is INVALID_MESSAGE.
    private static int SessionError(Exception error) => error is Rejected { Rejection: StaleCommand }
        ? CoreStatus.InvalidState : CoreStatus.InvalidMessage;

    /// The workspace identity at `workspace`: 16 RFC 4122 bytes.
    private static Guid Workspace(byte* workspace) => new(new ReadOnlySpan<byte>(workspace, 16), bigEndian: true);

    #endregion

    #region Actions - Commands

    [UnmanagedCallersOnly(EntryPoint = "crest_session_prepare_command", CallConvs = [typeof(CallConvCdecl)])]
    public static int SessionPrepareCommand(ulong app, byte* workspace, byte* bytes, nuint count, ulong* command) {
        if (command == null) return CoreStatus.InvalidArgument;
        *command = 0;
        if (workspace == null || !ValidSessionInput(bytes, count)) return CoreStatus.InvalidArgument;
        if (!Apps.TryGetValue(app, out var crest)) return CoreStatus.InvalidHandle;
        try {
            var prepared = crest.PrepareCommand(Workspace(workspace), new(bytes, (int)count));
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
