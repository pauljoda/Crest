using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;

using CrestCore.Application;
using CrestCore.Contracts;

namespace CrestCore.Native;

public static unsafe partial class Exports {
    /// One monotonic sequence for every handle table in this image, so a handle
    /// from one authority can never be mistaken for a live handle in another.
    private static long nextHandle;

    [UnmanagedCallersOnly(EntryPoint = "crest_core_abi_version", CallConvs = [typeof(CallConvCdecl)])]
    public static uint AbiVersion() => 1;

    [UnmanagedCallersOnly(EntryPoint = "crest_core_edit_session", CallConvs = [typeof(CallConvCdecl)])]
    public static int EditSession(byte* input, nuint inputLength, byte* destination, nuint capacity, nuint* length) {
        if (length == null) return CoreStatus.InvalidArgument;
        *length = 0;
        if (input == null || inputLength == 0 || destination == null && capacity != 0) return CoreStatus.InvalidArgument;
        if (inputLength > NativeSessionEditor.MaximumBytes || capacity > NativeSessionEditor.MaximumBytes) return CoreStatus.LimitExceeded;
        try {
            var result = NativeSessionEditor.Evaluate(new ReadOnlySpan<byte>(input, (int)inputLength));
            if (result.Length > NativeSessionEditor.MaximumBytes) return CoreStatus.LimitExceeded;
            *length = (nuint)result.Length;
            if (capacity < *length) return CoreStatus.BufferTooSmall;
            result.CopyTo(new Span<byte>(destination, (int)capacity));
            return CoreStatus.Ok;
        } catch (ProtocolException error) { return error.Message == "version_mismatch" ? CoreStatus.VersionMismatch : CoreStatus.InvalidMessage; } catch { return CoreStatus.InvalidMessage; }
    }

    [UnmanagedCallersOnly(EntryPoint = "crest_core_evaluate_sync", CallConvs = [typeof(CallConvCdecl)])]
    public static int EvaluateSync(byte* input, nuint inputLength, byte* destination, nuint capacity, nuint* length) {
        if (length == null) return CoreStatus.InvalidArgument;
        *length = 0;
        if (input == null || inputLength == 0 || destination == null && capacity != 0) return CoreStatus.InvalidArgument;
        if (inputLength > NativeSyncEvaluator.MaximumBytes || capacity > NativeSyncEvaluator.MaximumBytes)
            return CoreStatus.LimitExceeded;
        try {
            var result = NativeSyncEvaluator.Evaluate(new ReadOnlySpan<byte>(input, (int)inputLength));
            *length = (nuint)result.Length;
            if (capacity < *length) return CoreStatus.BufferTooSmall;
            result.CopyTo(new Span<byte>(destination, (int)capacity));
            return CoreStatus.Ok;
        } catch (CrestCore.Domain.BrowserRuleException error) { return error.Code == "version_mismatch" ? CoreStatus.VersionMismatch : CoreStatus.InvalidMessage; } catch { return CoreStatus.InvalidMessage; }
    }

    [UnmanagedCallersOnly(EntryPoint = "crest_core_evaluate_policy", CallConvs = [typeof(CallConvCdecl)])]
    public static int EvaluatePolicy(byte* input, nuint inputLength, byte* destination, nuint capacity, nuint* length) {
        if (length == null) return CoreStatus.InvalidArgument;
        *length = 0;
        if (input == null || inputLength == 0 || destination == null && capacity != 0) return CoreStatus.InvalidArgument;
        if (inputLength > NativePolicyEvaluator.MaximumInputBytes || capacity > NativePolicyEvaluator.MaximumOutputBytes)
            return CoreStatus.LimitExceeded;
        try {
            var result = NativePolicyEvaluator.Evaluate(new ReadOnlySpan<byte>(input, (int)inputLength));
            if (result.Length > NativePolicyEvaluator.MaximumOutputBytes) return CoreStatus.LimitExceeded;
            *length = (nuint)result.Length;
            if (capacity < *length) return CoreStatus.BufferTooSmall;
            result.CopyTo(new Span<byte>(destination, (int)capacity));
            return CoreStatus.Ok;
        } catch (ProtocolException error) { return error.Message == "version_mismatch" ? CoreStatus.VersionMismatch : CoreStatus.InvalidMessage; } catch { return CoreStatus.InvalidMessage; }
    }

}
