using System.Collections.Concurrent;
using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
using System.Text;
using CrestCore.Application;
using CrestCore.Domain;

namespace CrestCore.Native;

public static unsafe partial class Exports
{
    private static readonly ConcurrentDictionary<ulong, NativeSessionAuthority> Sessions = new();
    private static readonly ConcurrentDictionary<ulong, NativeSessionCheckpoint> Checkpoints = new();
    private static bool ValidSessionInput(byte* bytes, nuint count) => bytes != null && count is > 0 and <= NativeSessionAuthority.MaximumBytes;
    private static int SessionError(Exception error) => error is BrowserRuleException rule && rule.Code == "stale_session_revision"
        ? CoreStatus.InvalidState : CoreStatus.InvalidMessage;

    [UnmanagedCallersOnly(EntryPoint = "crest_session_create", CallConvs = [typeof(CallConvCdecl)])]
    public static int SessionCreate(byte* bytes, nuint count, ulong* handle, ulong* revision)
    {
        if (handle == null || revision == null) return CoreStatus.InvalidArgument;
        *handle = 0; *revision = 0;
        if (!ValidSessionInput(bytes, count)) return CoreStatus.InvalidArgument;
        try
        {
            var session = new NativeSessionAuthority(new(bytes, (int)count));
            var id = checked((ulong)Interlocked.Increment(ref nextHandle));
            if (!Sessions.TryAdd(id, session)) return CoreStatus.InternalError;
            *handle = id; *revision = session.Revision; return CoreStatus.Ok;
        }
        catch (Exception e) { return SessionError(e); }
    }
    [UnmanagedCallersOnly(EntryPoint = "crest_session_commit", CallConvs = [typeof(CallConvCdecl)])]
    public static int SessionCommit(ulong handle, ulong expected, byte* bytes, nuint count, ulong* revision)
    {
        if (revision == null) return CoreStatus.InvalidArgument;
        *revision = 0;
        if (!ValidSessionInput(bytes, count)) return CoreStatus.InvalidArgument;
        if (!Sessions.TryGetValue(handle, out var session)) return CoreStatus.InvalidHandle;
        try { *revision = session.Commit(expected, new(bytes, (int)count)); return CoreStatus.Ok; }
        catch (Exception e) { return SessionError(e); }
    }
    [UnmanagedCallersOnly(EntryPoint = "crest_session_commit_pair", CallConvs = [typeof(CallConvCdecl)])]
    public static int SessionCommitPair(ulong source, ulong sourceExpected, byte* sourceBytes, nuint sourceCount,
        ulong destination, ulong destinationExpected, byte* destinationBytes, nuint destinationCount,
        ulong* sourceRevision, ulong* destinationRevision)
    {
        if (sourceRevision == null || destinationRevision == null) return CoreStatus.InvalidArgument;
        *sourceRevision = 0; *destinationRevision = 0;
        if (!ValidSessionInput(sourceBytes, sourceCount) || !ValidSessionInput(destinationBytes, destinationCount)) return CoreStatus.InvalidArgument;
        if (!Sessions.TryGetValue(source, out var a) || !Sessions.TryGetValue(destination, out var b)) return CoreStatus.InvalidHandle;
        try
        {
            var result = NativeSessionAuthority.CommitPair(a, sourceExpected, new(sourceBytes, (int)sourceCount),
                b, destinationExpected, new(destinationBytes, (int)destinationCount));
            *sourceRevision = result.Source; *destinationRevision = result.Destination; return CoreStatus.Ok;
        }
        catch (Exception e) { return SessionError(e); }
    }
    [UnmanagedCallersOnly(EntryPoint = "crest_session_checkpoint", CallConvs = [typeof(CallConvCdecl)])]
    public static int SessionCheckpoint(ulong handle, ulong expected, byte* selection, nuint count, ulong* checkpoint)
    {
        if (checkpoint == null) return CoreStatus.InvalidArgument;
        *checkpoint = 0;
        if (!ValidSessionInput(selection, count)) return CoreStatus.InvalidArgument;
        if (!Sessions.TryGetValue(handle, out var session)) return CoreStatus.InvalidHandle;
        try
        {
            var value = session.Checkpoint(expected, new(selection, (int)count));
            var id = checked((ulong)Interlocked.Increment(ref nextHandle));
            if (!Checkpoints.TryAdd(id, value)) return CoreStatus.InternalError;
            *checkpoint = id; return CoreStatus.Ok;
        }
        catch (Exception e) { return SessionError(e); }
    }
    [UnmanagedCallersOnly(EntryPoint = "crest_session_read_checkpoint", CallConvs = [typeof(CallConvCdecl)])]
    public static int SessionReadCheckpoint(ulong handle, byte* part, nuint partLength, byte* destination, nuint capacity, nuint* length)
    {
        if (length == null) return CoreStatus.InvalidArgument;
        *length = 0;
        if (part == null || partLength is 0 or > 64 || destination == null && capacity != 0) return CoreStatus.InvalidArgument;
        if (capacity > NativeSessionAuthority.MaximumBytes) return CoreStatus.LimitExceeded;
        if (!Checkpoints.TryGetValue(handle, out var checkpoint)) return CoreStatus.InvalidHandle;
        try
        {
            var data = checkpoint.Read(Encoding.UTF8.GetString(new ReadOnlySpan<byte>(part, (int)partLength)));
            if (data.Length > NativeSessionAuthority.MaximumBytes) return CoreStatus.LimitExceeded;
            *length = (nuint)data.Length;
            if (capacity < *length) return CoreStatus.BufferTooSmall;
            data.CopyTo(new Span<byte>(destination, (int)capacity)); return CoreStatus.Ok;
        }
        catch (Exception e) { return SessionError(e); }
    }
    [UnmanagedCallersOnly(EntryPoint = "crest_session_destroy", CallConvs = [typeof(CallConvCdecl)])]
    public static int SessionDestroy(ulong handle) => Sessions.TryRemove(handle, out _) ? CoreStatus.Ok : CoreStatus.InvalidHandle;
    [UnmanagedCallersOnly(EntryPoint = "crest_session_release_checkpoint", CallConvs = [typeof(CallConvCdecl)])]
    public static int SessionReleaseCheckpoint(ulong handle) => Checkpoints.TryRemove(handle, out _) ? CoreStatus.Ok : CoreStatus.InvalidHandle;
}
