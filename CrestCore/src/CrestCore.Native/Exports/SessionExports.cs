using System.Collections.Concurrent;
using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.Json.Nodes;

using CrestCore.Application;
using CrestCore.Domain;

namespace CrestCore.Native;

public static unsafe partial class Exports {
    #region Variables

    private static readonly ConcurrentDictionary<ulong, NativeSessionAuthority> Sessions = new();
    private static readonly ConcurrentDictionary<ulong, NativeSessionCheckpoint> Checkpoints = new();
    private static readonly ConcurrentDictionary<ulong, NativeSessionCommand> SessionCommands = new();
    private static readonly ConcurrentDictionary<ulong, NativeSessionReplacement> SessionReplacements = new();

    #endregion

    #region Actions - Validation

    private static bool ValidSessionInput(byte* bytes, nuint count) => bytes != null && count is > 0 and <= NativeSessionAuthority.MaximumBytes;

    private static int SessionError(Exception error) => error is BrowserRuleException rule && rule.Code == "stale_session_revision"
        ? CoreStatus.InvalidState : CoreStatus.InvalidMessage;

    #endregion

    #region Actions - Session lifecycle

    [UnmanagedCallersOnly(EntryPoint = "crest_session_create", CallConvs = [typeof(CallConvCdecl)])]
    public static int SessionCreate(byte* bytes, nuint count, ulong* handle, ulong* revision) {
        if (handle == null || revision == null) return CoreStatus.InvalidArgument;
        *handle = 0; *revision = 0;
        if (!ValidSessionInput(bytes, count)) return CoreStatus.InvalidArgument;
        try {
            var session = new NativeSessionAuthority(new(bytes, (int)count));
            var id = checked((ulong)Interlocked.Increment(ref nextHandle));
            if (!Sessions.TryAdd(id, session)) return CoreStatus.InternalError;
            *handle = id; *revision = session.Revision; return CoreStatus.Ok;
        } catch (Exception e) { return SessionError(e); }
    }

    [UnmanagedCallersOnly(EntryPoint = "crest_session_register_engine", CallConvs = [typeof(CallConvCdecl)])]
    public static int SessionRegisterEngine(ulong handle, byte* bytes, nuint count) {
        if (!ValidSessionInput(bytes, count) || count > 65536) return CoreStatus.InvalidArgument;
        if (!Sessions.TryGetValue(handle, out var session)) return CoreStatus.InvalidHandle;
        try { session.RegisterEngine(new(bytes, (int)count)); return CoreStatus.Ok; } catch (Exception e) { return SessionError(e); }
    }

    [UnmanagedCallersOnly(EntryPoint = "crest_session_create_borrowed", CallConvs = [typeof(CallConvCdecl)])]
    public static int SessionCreateBorrowed(ulong source, ulong expected, byte* bytes, nuint count,
        ulong* handle, ulong* revision, ulong* projection) {
        if (handle == null || revision == null || projection == null) return CoreStatus.InvalidArgument;
        *handle = 0; *revision = 0; *projection = 0;
        if (!ValidSessionInput(bytes, count) || count > 1024) return CoreStatus.InvalidArgument;
        if (!Sessions.TryGetValue(source, out var owner)) return CoreStatus.InvalidHandle;
        try {
            var request = JsonNode.Parse(new ReadOnlySpan<byte>(bytes, (int)count))!;
            var child = owner.CreateBorrowed(expected, Guid.Parse(request["spaceId"]!.GetValue<string>()),
                Guid.Parse(request["profileId"]!.GetValue<string>()));
            var initial = child.PrepareBorrowedRefresh(child.Revision);
            var childId = checked((ulong)Interlocked.Increment(ref nextHandle));
            var commandId = checked((ulong)Interlocked.Increment(ref nextHandle));
            if (!Sessions.TryAdd(childId, child)) return CoreStatus.InternalError;
            if (!SessionCommands.TryAdd(commandId, initial)) { Sessions.TryRemove(childId, out _); child.Release(); return CoreStatus.InternalError; }
            *handle = childId; *revision = child.Revision; *projection = commandId;
            return CoreStatus.Ok;
        } catch (Exception e) { return SessionError(e); }
    }

    [UnmanagedCallersOnly(EntryPoint = "crest_session_prepare_borrowed_refresh", CallConvs = [typeof(CallConvCdecl)])]
    public static int SessionPrepareBorrowedRefresh(ulong handle, ulong expected, ulong* command) {
        if (command == null) return CoreStatus.InvalidArgument;
        *command = 0;
        if (!Sessions.TryGetValue(handle, out var session)) return CoreStatus.InvalidHandle;
        try {
            var value = session.PrepareBorrowedRefresh(expected);
            var id = checked((ulong)Interlocked.Increment(ref nextHandle));
            if (!SessionCommands.TryAdd(id, value)) return CoreStatus.InternalError;
            *command = id; return CoreStatus.Ok;
        } catch (Exception e) { return SessionError(e); }
    }

    [UnmanagedCallersOnly(EntryPoint = "crest_session_commit", CallConvs = [typeof(CallConvCdecl)])]
    public static int SessionCommit(ulong handle, ulong expected, byte* bytes, nuint count, ulong* revision) {
        if (revision == null) return CoreStatus.InvalidArgument;
        *revision = 0;
        if (!ValidSessionInput(bytes, count)) return CoreStatus.InvalidArgument;
        if (!Sessions.TryGetValue(handle, out var session)) return CoreStatus.InvalidHandle;
        try { *revision = session.Commit(expected, new(bytes, (int)count)); return CoreStatus.Ok; } catch (Exception e) { return SessionError(e); }
    }

    [UnmanagedCallersOnly(EntryPoint = "crest_session_commit_pair", CallConvs = [typeof(CallConvCdecl)])]
    public static int SessionCommitPair(ulong source, ulong sourceExpected, byte* sourceBytes, nuint sourceCount,
        ulong destination, ulong destinationExpected, byte* destinationBytes, nuint destinationCount,
        ulong* sourceRevision, ulong* destinationRevision) {
        if (sourceRevision == null || destinationRevision == null) return CoreStatus.InvalidArgument;
        *sourceRevision = 0; *destinationRevision = 0;
        if (!ValidSessionInput(sourceBytes, sourceCount) || !ValidSessionInput(destinationBytes, destinationCount)) return CoreStatus.InvalidArgument;
        if (!Sessions.TryGetValue(source, out var a) || !Sessions.TryGetValue(destination, out var b)) return CoreStatus.InvalidHandle;
        try {
            var result = NativeSessionAuthority.CommitPair(a, sourceExpected, new(sourceBytes, (int)sourceCount),
                b, destinationExpected, new(destinationBytes, (int)destinationCount));
            *sourceRevision = result.Source; *destinationRevision = result.Destination; return CoreStatus.Ok;
        } catch (Exception e) { return SessionError(e); }
    }

    [UnmanagedCallersOnly(EntryPoint = "crest_session_checkpoint", CallConvs = [typeof(CallConvCdecl)])]
    public static int SessionCheckpoint(ulong handle, ulong expected, byte* selection, nuint count, ulong* checkpoint) {
        if (checkpoint == null) return CoreStatus.InvalidArgument;
        *checkpoint = 0;
        if (!ValidSessionInput(selection, count)) return CoreStatus.InvalidArgument;
        if (!Sessions.TryGetValue(handle, out var session)) return CoreStatus.InvalidHandle;
        try {
            var value = session.Checkpoint(expected, new(selection, (int)count));
            var id = checked((ulong)Interlocked.Increment(ref nextHandle));
            if (!Checkpoints.TryAdd(id, value)) return CoreStatus.InternalError;
            *checkpoint = id; return CoreStatus.Ok;
        } catch (Exception e) { return SessionError(e); }
    }

    [UnmanagedCallersOnly(EntryPoint = "crest_session_read_checkpoint", CallConvs = [typeof(CallConvCdecl)])]
    public static int SessionReadCheckpoint(ulong handle, byte* part, nuint partLength, byte* destination, nuint capacity, nuint* length) {
        if (length == null) return CoreStatus.InvalidArgument;
        *length = 0;
        if (part == null || partLength is 0 or > 64 || destination == null && capacity != 0) return CoreStatus.InvalidArgument;
        if (capacity > NativeSessionAuthority.MaximumBytes) return CoreStatus.LimitExceeded;
        if (!Checkpoints.TryGetValue(handle, out var checkpoint)) return CoreStatus.InvalidHandle;
        try {
            var data = checkpoint.Read(Encoding.UTF8.GetString(new ReadOnlySpan<byte>(part, (int)partLength)));
            if (data.Length > NativeSessionAuthority.MaximumBytes) return CoreStatus.LimitExceeded;
            *length = (nuint)data.Length;
            if (capacity < *length) return CoreStatus.BufferTooSmall;
            data.CopyTo(new Span<byte>(destination, (int)capacity)); return CoreStatus.Ok;
        } catch (Exception e) { return SessionError(e); }
    }

    [UnmanagedCallersOnly(EntryPoint = "crest_session_destroy", CallConvs = [typeof(CallConvCdecl)])]
    public static int SessionDestroy(ulong handle) {
        if (!Sessions.TryRemove(handle, out var session)) return CoreStatus.InvalidHandle;
        session.Release(); return CoreStatus.Ok;
    }

    [UnmanagedCallersOnly(EntryPoint = "crest_session_release_checkpoint", CallConvs = [typeof(CallConvCdecl)])]
    public static int SessionReleaseCheckpoint(ulong handle) => Checkpoints.TryRemove(handle, out _) ? CoreStatus.Ok : CoreStatus.InvalidHandle;

    #endregion

    #region Actions - Commands and replacements

    [UnmanagedCallersOnly(EntryPoint = "crest_session_prepare_command", CallConvs = [typeof(CallConvCdecl)])]
    public static int SessionPrepareCommand(ulong handle, ulong expected, byte* bytes, nuint count, ulong* command) {
        if (command == null) return CoreStatus.InvalidArgument;
        *command = 0;
        if (!ValidSessionInput(bytes, count)) return CoreStatus.InvalidArgument;
        if (!Sessions.TryGetValue(handle, out var session)) return CoreStatus.InvalidHandle;
        try {
            var prepared = session.PrepareCommand(expected, new(bytes, (int)count));
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
    public static int SessionCommitCommand(ulong handle, ulong* revision) {
        if (revision == null) return CoreStatus.InvalidArgument;
        *revision = 0;
        if (!SessionCommands.TryGetValue(handle, out var command)) return CoreStatus.InvalidHandle;
        try { *revision = command.Commit(); return CoreStatus.Ok; } catch (Exception e) { return SessionError(e); }
    }

    [UnmanagedCallersOnly(EntryPoint = "crest_session_release_command", CallConvs = [typeof(CallConvCdecl)])]
    public static int SessionReleaseCommand(ulong handle) => SessionCommands.TryRemove(handle, out _) ? CoreStatus.Ok : CoreStatus.InvalidHandle;

    [UnmanagedCallersOnly(EntryPoint = "crest_session_reserve_command", CallConvs = [typeof(CallConvCdecl)])]
    public static int SessionReserveCommand(ulong handle, byte* selection, nuint selectionCount, ulong* replacement, ulong* checkpoint) {
        if (replacement == null || checkpoint == null) return CoreStatus.InvalidArgument;
        *replacement = 0; *checkpoint = 0;
        if (!ValidSessionInput(selection, selectionCount)) return CoreStatus.InvalidArgument;
        if (!SessionCommands.TryGetValue(handle, out var command)) return CoreStatus.InvalidHandle;
        NativeSessionReplacement? value = null;
        ulong id = 0, snapshot = 0;
        try {
            value = command.Reserve(new(selection, (int)selectionCount));
            id = checked((ulong)Interlocked.Increment(ref nextHandle));
            snapshot = checked((ulong)Interlocked.Increment(ref nextHandle));
            if (!SessionReplacements.TryAdd(id, value) || !Checkpoints.TryAdd(snapshot, value.Checkpoint))
                throw new InvalidOperationException("handle_collision");
            *replacement = id; *checkpoint = snapshot;
            return CoreStatus.Ok;
        } catch (Exception e) {
            SessionReplacements.TryRemove(id, out _); Checkpoints.TryRemove(snapshot, out _);
            value?.Dispose(); return SessionError(e);
        }
    }

    [UnmanagedCallersOnly(EntryPoint = "crest_session_reserve_replacement", CallConvs = [typeof(CallConvCdecl)])]
    public static int SessionReserveReplacement(ulong handle, ulong expected, byte* delta, nuint count,
        byte* selection, nuint selectionCount, ulong* replacement, ulong* checkpoint) {
        if (replacement == null || checkpoint == null) return CoreStatus.InvalidArgument;
        *replacement = 0; *checkpoint = 0;
        if (!ValidSessionInput(delta, count) || !ValidSessionInput(selection, selectionCount)) return CoreStatus.InvalidArgument;
        if (!Sessions.TryGetValue(handle, out var session)) return CoreStatus.InvalidHandle;
        NativeSessionReplacement? value = null;
        ulong id = 0, snapshot = 0;
        try {
            value = session.ReserveReplacement(expected, new(delta, (int)count), new(selection, (int)selectionCount));
            id = checked((ulong)Interlocked.Increment(ref nextHandle));
            snapshot = checked((ulong)Interlocked.Increment(ref nextHandle));
            if (!SessionReplacements.TryAdd(id, value) || !Checkpoints.TryAdd(snapshot, value.Checkpoint))
                throw new InvalidOperationException("handle_collision");
            *replacement = id; *checkpoint = snapshot;
            return CoreStatus.Ok;
        } catch (Exception e) {
            SessionReplacements.TryRemove(id, out _); Checkpoints.TryRemove(snapshot, out _);
            value?.Dispose();
            return SessionError(e);
        }
    }

    [UnmanagedCallersOnly(EntryPoint = "crest_session_reserve_sync_replacement", CallConvs = [typeof(CallConvCdecl)])]
    public static int SessionReserveSyncReplacement(ulong handle, ulong expected, ulong transaction, byte* delta, nuint count,
        byte* selection, nuint selectionCount, ulong* replacement, ulong* checkpoint) {
        if (replacement == null || checkpoint == null) return CoreStatus.InvalidArgument;
        *replacement = 0; *checkpoint = 0;
        if (!ValidSessionInput(delta, count) || !ValidSessionInput(selection, selectionCount)) return CoreStatus.InvalidArgument;
        if (!Sessions.TryGetValue(handle, out var session)) return CoreStatus.InvalidHandle;
        if (!SyncTransactions.TryGetValue(transaction, out var sync)) return CoreStatus.InvalidHandle;
        NativeSessionReplacement? value = null;
        ulong id = 0, snapshot = 0;
        try {
            value = session.ReserveReplacement(expected, new(delta, (int)count), new(selection, (int)selectionCount), sync);
            id = checked((ulong)Interlocked.Increment(ref nextHandle));
            snapshot = checked((ulong)Interlocked.Increment(ref nextHandle));
            if (!SessionReplacements.TryAdd(id, value) || !Checkpoints.TryAdd(snapshot, value.Checkpoint))
                throw new InvalidOperationException("handle_collision");
            *replacement = id; *checkpoint = snapshot;
            return CoreStatus.Ok;
        } catch (Exception e) {
            SessionReplacements.TryRemove(id, out _); Checkpoints.TryRemove(snapshot, out _);
            value?.Dispose();
            return SessionError(e);
        }
    }

    [UnmanagedCallersOnly(EntryPoint = "crest_session_commit_replacement", CallConvs = [typeof(CallConvCdecl)])]
    public static int SessionCommitReplacement(ulong handle, ulong* revision) {
        if (revision == null) return CoreStatus.InvalidArgument;
        *revision = 0;
        if (!SessionReplacements.TryGetValue(handle, out var value)) return CoreStatus.InvalidHandle;
        try { *revision = value.Commit(); return CoreStatus.Ok; } catch (Exception e) { return SessionError(e); }
    }

    [UnmanagedCallersOnly(EntryPoint = "crest_session_release_replacement", CallConvs = [typeof(CallConvCdecl)])]
    public static int SessionReleaseReplacement(ulong handle) {
        if (!SessionReplacements.TryRemove(handle, out var value)) return CoreStatus.InvalidHandle;
        value.Dispose(); return CoreStatus.Ok;
    }

    #endregion
}
