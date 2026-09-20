using System.Collections.Concurrent;
using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
using CrestCore.Application;
using CrestCore.Contracts;

namespace CrestCore.Native;

[StructLayout(LayoutKind.Sequential)]
public unsafe struct CoreOptionsV1
{
    public uint StructSize, AbiVersion;
    public byte* Configuration;
    public nuint ConfigurationLength;
}

public static unsafe partial class Exports
{
    private static readonly ConcurrentDictionary<ulong, CoreRuntime> Cores = new();
    private static long nextHandle;
    private const nuint MaxMessage = 1048576;
    private static int With(ulong handle, Func<CoreRuntime, int> action)
    {
        try { return Cores.TryGetValue(handle, out var core) ? action(core) : CoreStatus.InvalidHandle; }
        catch { return CoreStatus.InternalError; }
    }
    [UnmanagedCallersOnly(EntryPoint = "crest_core_abi_version", CallConvs = [typeof(CallConvCdecl)])]
    public static uint AbiVersion() => 1;

    [UnmanagedCallersOnly(EntryPoint = "crest_core_edit_session", CallConvs = [typeof(CallConvCdecl)])]
    public static int EditSession(byte* input, nuint inputLength, byte* destination, nuint capacity, nuint* length)
    {
        if (length == null) return CoreStatus.InvalidArgument;
        *length = 0;
        if (input == null || inputLength == 0 || destination == null && capacity != 0) return CoreStatus.InvalidArgument;
        if (inputLength > NativeSessionEditor.MaximumBytes || capacity > NativeSessionEditor.MaximumBytes) return CoreStatus.LimitExceeded;
        try
        {
            var result = NativeSessionEditor.Evaluate(new ReadOnlySpan<byte>(input, (int)inputLength));
            if (result.Length > NativeSessionEditor.MaximumBytes) return CoreStatus.LimitExceeded;
            *length = (nuint)result.Length;
            if (capacity < *length) return CoreStatus.BufferTooSmall;
            result.CopyTo(new Span<byte>(destination, (int)capacity));
            return CoreStatus.Ok;
        }
        catch (ProtocolException error) { return error.Message == "version_mismatch" ? CoreStatus.VersionMismatch : CoreStatus.InvalidMessage; }
        catch { return CoreStatus.InvalidMessage; }
    }

    [UnmanagedCallersOnly(EntryPoint = "crest_core_evaluate_sync", CallConvs = [typeof(CallConvCdecl)])]
    public static int EvaluateSync(byte* input, nuint inputLength, byte* destination, nuint capacity, nuint* length)
    {
        if (length == null) return CoreStatus.InvalidArgument;
        *length = 0;
        if (input == null || inputLength == 0 || destination == null && capacity != 0) return CoreStatus.InvalidArgument;
        if (inputLength > NativeSyncEvaluator.MaximumBytes || capacity > NativeSyncEvaluator.MaximumBytes)
            return CoreStatus.LimitExceeded;
        try
        {
            var result = NativeSyncEvaluator.Evaluate(new ReadOnlySpan<byte>(input, (int)inputLength));
            *length = (nuint)result.Length;
            if (capacity < *length) return CoreStatus.BufferTooSmall;
            result.CopyTo(new Span<byte>(destination, (int)capacity));
            return CoreStatus.Ok;
        }
        catch (CrestCore.Domain.BrowserRuleException error)
        { return error.Code == "version_mismatch" ? CoreStatus.VersionMismatch : CoreStatus.InvalidMessage; }
        catch { return CoreStatus.InvalidMessage; }
    }

    [UnmanagedCallersOnly(EntryPoint = "crest_core_evaluate_policy", CallConvs = [typeof(CallConvCdecl)])]
    public static int EvaluatePolicy(byte* input, nuint inputLength, byte* destination, nuint capacity, nuint* length)
    {
        if (length == null) return CoreStatus.InvalidArgument;
        *length = 0;
        if (input == null || inputLength == 0 || destination == null && capacity != 0) return CoreStatus.InvalidArgument;
        if (inputLength > NativePolicyEvaluator.MaximumInputBytes || capacity > NativePolicyEvaluator.MaximumOutputBytes)
            return CoreStatus.LimitExceeded;
        try
        {
            var result = NativePolicyEvaluator.Evaluate(new ReadOnlySpan<byte>(input, (int)inputLength));
            if (result.Length > NativePolicyEvaluator.MaximumOutputBytes) return CoreStatus.LimitExceeded;
            *length = (nuint)result.Length;
            if (capacity < *length) return CoreStatus.BufferTooSmall;
            result.CopyTo(new Span<byte>(destination, (int)capacity));
            return CoreStatus.Ok;
        }
        catch (ProtocolException error) { return error.Message == "version_mismatch" ? CoreStatus.VersionMismatch : CoreStatus.InvalidMessage; }
        catch { return CoreStatus.InvalidMessage; }
    }

    [UnmanagedCallersOnly(EntryPoint = "crest_core_create", CallConvs = [typeof(CallConvCdecl)])]
    public static int Create(CoreOptionsV1* options, ulong* result)
    {
        if (result == null) return CoreStatus.InvalidArgument;
        *result = 0;
        if (options == null || options->StructSize < sizeof(CoreOptionsV1)) return CoreStatus.InvalidArgument;
        if (options->AbiVersion != 1) return CoreStatus.VersionMismatch;
        if (options->Configuration == null || options->ConfigurationLength is 0 or > 16777216) return CoreStatus.InvalidArgument;
        try
        {
            var config = Protocol.Options(new ReadOnlySpan<byte>(options->Configuration, (int)options->ConfigurationLength));
            var core = new CoreRuntime(config);
            var handle = checked((ulong)Interlocked.Increment(ref nextHandle));
            if (!Cores.TryAdd(handle, core)) return CoreStatus.InternalError;
            *result = handle; return CoreStatus.Ok;
        }
        catch (ProtocolException e) { return e.Message == "version_mismatch" ? CoreStatus.VersionMismatch : CoreStatus.InvalidMessage; }
        catch { return CoreStatus.InvalidMessage; }
    }
    [UnmanagedCallersOnly(EntryPoint = "crest_core_register_adapter", CallConvs = [typeof(CallConvCdecl)])]
    public static int Register(ulong handle, byte* bytes, nuint length)
    {
        if (bytes == null || length == 0) return CoreStatus.InvalidArgument;
        if (length > MaxMessage) return CoreStatus.LimitExceeded;
        try { var copy = new ReadOnlySpan<byte>(bytes, (int)length).ToArray(); return With(handle, c => c.Register(copy)); }
        catch { return CoreStatus.InternalError; }
    }
    [UnmanagedCallersOnly(EntryPoint = "crest_core_start", CallConvs = [typeof(CallConvCdecl)])]
    public static int Start(ulong handle) => With(handle, c => c.Start());
    [UnmanagedCallersOnly(EntryPoint = "crest_core_post", CallConvs = [typeof(CallConvCdecl)])]
    public static int Post(ulong handle, byte* bytes, nuint length)
    {
        if (bytes == null || length == 0) return CoreStatus.InvalidArgument;
        if (length > MaxMessage) return CoreStatus.LimitExceeded;
        try { var copy = new ReadOnlySpan<byte>(bytes, (int)length).ToArray(); return With(handle, c => c.Post(copy)); }
        catch { return CoreStatus.InternalError; }
    }
    [UnmanagedCallersOnly(EntryPoint = "crest_core_wait_output", CallConvs = [typeof(CallConvCdecl)])]
    public static int WaitOutput(ulong handle, uint timeout) => With(handle, c => c.WaitOutput(timeout));
    [UnmanagedCallersOnly(EntryPoint = "crest_core_read_output", CallConvs = [typeof(CallConvCdecl)])]
    public static int Read(ulong handle, byte* destination, nuint capacity, nuint* length)
    {
        if (length == null) return CoreStatus.InvalidArgument;
        *length = 0;
        if (destination == null && capacity != 0) return CoreStatus.InvalidArgument;
        if (capacity > MaxMessage) return CoreStatus.LimitExceeded;
        try
        {
            if (!Cores.TryGetValue(handle, out var core)) return CoreStatus.InvalidHandle;
            int status = core.Read(new Span<byte>(destination, (int)capacity), out int count);
            *length = (nuint)count; return status;
        }
        catch { return CoreStatus.InternalError; }
    }
    [UnmanagedCallersOnly(EntryPoint = "crest_core_begin_shutdown", CallConvs = [typeof(CallConvCdecl)])]
    public static int BeginShutdown(ulong handle) => With(handle, c => c.BeginShutdown());
    [UnmanagedCallersOnly(EntryPoint = "crest_core_wait_stopped", CallConvs = [typeof(CallConvCdecl)])]
    public static int WaitStopped(ulong handle, uint timeout) => With(handle, c => c.WaitStopped(timeout));
    [UnmanagedCallersOnly(EntryPoint = "crest_core_destroy", CallConvs = [typeof(CallConvCdecl)])]
    public static int Destroy(ulong handle) => With(handle, c =>
        c.CanDestroy && Cores.TryRemove(handle, out _) ? CoreStatus.Ok : CoreStatus.InvalidState);
}
