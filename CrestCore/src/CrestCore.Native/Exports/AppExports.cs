using System.Collections.Concurrent;
using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;

using CrestCore.Application;
using CrestCore.Contracts;

namespace CrestCore.Native;

/// A byte buffer the core allocated for the caller, released with `crest_buffer_free`.
[StructLayout(LayoutKind.Sequential)]
public unsafe struct CrestBuffer {
    public byte* Bytes;
    public nuint Length;
}

public static unsafe partial class Exports {
    #region Variables

    /// Intents and queries are small; anything larger is a caller bug.
    public const int MaximumMessageBytes = 16 * 1024 * 1024;

    private static readonly ConcurrentDictionary<ulong, CrestApp> Apps = new();

    #endregion

    #region Actions - Native exports

    [UnmanagedCallersOnly(EntryPoint = "crest_app_create", CallConvs = [typeof(CallConvCdecl)])]
    public static int AppCreate(byte* fingerprint, nuint length, byte* configuration, nuint configurationLength,
        ulong* app, CrestBuffer* rejection) {
        if (app == null || rejection == null) return CoreStatus.InvalidArgument;
        *app = 0;
        *rejection = default;
        if (fingerprint == null && length != 0 || configuration == null && configurationLength != 0) return CoreStatus.InvalidArgument;
        if (configurationLength > MaximumMessageBytes) return CoreStatus.LimitExceeded;
        try {
            if (length != (nuint)ContractCodec.Fingerprint.Length
                || !new ReadOnlySpan<byte>(fingerprint, (int)length).SequenceEqual(ContractCodec.Fingerprint))
                return CoreStatus.VersionMismatch;
            var reader = new WireReader(new ReadOnlySpan<byte>(configuration, (int)configurationLength).ToArray());
            var settings = Finished(ContractCodec.ReadAppConfiguration(reader), reader);
            CrestApp created;
            try {
                created = new CrestApp(settings);
            } catch (Rejected refused) {
                var writer = new WireWriter();
                ContractCodec.WriteRejection(writer, refused.Rejection);
                *rejection = Allocate(writer.WrittenSpan);
                return CoreStatus.Rejected;
            }
            var id = checked((ulong)Interlocked.Increment(ref nextHandle));
            if (!Apps.TryAdd(id, created)) {
                created.Dispose();
                return CoreStatus.InternalError;
            }
            *app = id;
            return CoreStatus.Ok;
        } catch (WireFormatException) {
            return CoreStatus.InvalidMessage;
        } catch {
            return CoreStatus.InternalError;
        }
    }

    /// Saves what the app's session file still owes and closes it. Clear the
    /// wake callback first.
    [UnmanagedCallersOnly(EntryPoint = "crest_app_destroy", CallConvs = [typeof(CallConvCdecl)])]
    public static int AppDestroy(ulong app) {
        try {
            if (!Apps.TryRemove(app, out var crest)) return CoreStatus.InvalidHandle;
            crest.Dispose();
            return CoreStatus.Ok;
        } catch { return CoreStatus.InternalError; }
    }

    [UnmanagedCallersOnly(EntryPoint = "crest_app_set_wake", CallConvs = [typeof(CallConvCdecl)])]
    public static int AppSetWake(ulong app, delegate* unmanaged[Cdecl]<nint, void> callback, nint context) {
        try {
            if (!Apps.TryGetValue(app, out var crest)) return CoreStatus.InvalidHandle;
            var function = (nint)callback;
            crest.SetWake(function == 0 ? null : () => Wake(function, context));
            return CoreStatus.Ok;
        } catch { return CoreStatus.InternalError; }
    }

    [UnmanagedCallersOnly(EntryPoint = "crest_app_drain", CallConvs = [typeof(CallConvCdecl)])]
    public static int AppDrain(ulong app, CrestBuffer* output) {
        if (output == null) return CoreStatus.InvalidArgument;
        *output = default;
        try {
            if (!Apps.TryGetValue(app, out var crest)) return CoreStatus.InvalidHandle;
            var changes = crest.Drain();
            var writer = new WireWriter();
            writer.WriteCount(changes.Count);
            foreach (var change in changes) ContractCodec.WriteChange(writer, change);
            *output = Allocate(writer.WrittenSpan);
            return CoreStatus.Ok;
        } catch { return CoreStatus.InternalError; }
    }

    [UnmanagedCallersOnly(EntryPoint = "crest_app_dispatch", CallConvs = [typeof(CallConvCdecl)])]
    public static int AppDispatch(ulong app, byte* intent, nuint length, CrestBuffer* output) =>
        Call(app, intent, length, output, (crest, reader, writer) => {
            var changes = crest.Send(Finished(ContractCodec.ReadIntent(reader), reader));
            writer.WriteCount(changes.Count);
            foreach (var change in changes) ContractCodec.WriteChange(writer, change);
        });

    [UnmanagedCallersOnly(EntryPoint = "crest_app_query", CallConvs = [typeof(CallConvCdecl)])]
    public static int AppQuery(ulong app, byte* query, nuint length, CrestBuffer* output) =>
        Call(app, query, length, output, (crest, reader, writer) =>
            ContractCodec.WriteAnswer(writer, crest, Finished(ContractCodec.ReadQuery(reader), reader)));

    [UnmanagedCallersOnly(EntryPoint = "crest_buffer_free", CallConvs = [typeof(CallConvCdecl)])]
    public static void BufferFree(CrestBuffer* buffer) {
        if (buffer == null) return;
        NativeMemory.Free(buffer->Bytes);
        *buffer = default;
    }

    #endregion

    #region Actions - Messages

    /// Decodes one message, runs it and hands the caller the encoded answer, or
    /// the encoded rejection with REJECTED.
    private static int Call(ulong app, byte* input, nuint length, CrestBuffer* output,
        Action<CrestApp, WireReader, WireWriter> run) {
        if (output == null) return CoreStatus.InvalidArgument;
        *output = default;
        if (input == null && length != 0) return CoreStatus.InvalidArgument;
        if (length > MaximumMessageBytes) return CoreStatus.LimitExceeded;
        try {
            if (!Apps.TryGetValue(app, out var crest)) return CoreStatus.InvalidHandle;
            var reader = new WireReader(new ReadOnlySpan<byte>(input, (int)length).ToArray());
            var writer = new WireWriter();
            try {
                run(crest, reader, writer);
            } catch (Rejected rejected) {
                var rejection = new WireWriter();
                ContractCodec.WriteRejection(rejection, rejected.Rejection);
                *output = Allocate(rejection.WrittenSpan);
                return CoreStatus.Rejected;
            }
            *output = Allocate(writer.WrittenSpan);
            return CoreStatus.Ok;
        } catch (WireFormatException) {
            return CoreStatus.InvalidMessage;
        } catch {
            return CoreStatus.InternalError;
        }
    }

    private static void Wake(nint callback, nint context) => ((delegate* unmanaged[Cdecl]<nint, void>)callback)(context);

    /// A decoded message must use every byte it arrived with.
    private static T Finished<T>(T message, WireReader reader) {
        reader.EnsureEnd();
        return message;
    }

    private static CrestBuffer Allocate(ReadOnlySpan<byte> bytes) {
        var memory = (byte*)NativeMemory.Alloc((nuint)Math.Max(bytes.Length, 1));
        bytes.CopyTo(new Span<byte>(memory, bytes.Length));
        return new CrestBuffer { Bytes = memory, Length = (nuint)bytes.Length };
    }

    #endregion
}
