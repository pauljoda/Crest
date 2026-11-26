using System.Buffers.Binary;
using System.Net.WebSockets;
using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
using System.Threading.Channels;

namespace CrestDesktop.DevHost;

/// One interface connected over a WebSocket, and the core app it created.
///
/// Every frame is binary. A request is `[op][id: u32]` and its payload; its
/// response is `[op | 0x80][id][status: i32]` and the core's bytes. The core's
/// own changes arrive as `[0xF0][status]` and the drained batch after a wake,
/// and an engine command as `[0xF1][engine: u64]` and the command. The bytes are
/// the contract wire format, which the interface encodes and decodes itself:
/// this host never reads them.
internal sealed class CoreSession : IAsyncDisposable {
    #region Types

    /// The ops a request names.
    private enum Op : byte { Create = 1, Dispatch, Query, Drain, EndTurn, RegisterEngine, Report, Ask }

    /// An engine binding the interface registered, which the core runs commands on.
    private sealed class EngineSlot(CoreSession session) {
        public CoreSession Session { get; } = session;
        public ulong Engine { get; set; }
    }

    #endregion

    #region Variables

    private const byte ChangesPush = 0xF0, CommandPush = 0xF1;

    private readonly WebSocket socket;
    /// The core's calls are synchronous and serialized per app.
    private readonly SemaphoreSlim gate = new(1, 1);
    private readonly Channel<byte[]> outgoing = Channel.CreateUnbounded<byte[]>(new UnboundedChannelOptions { SingleReader = true });
    private readonly List<GCHandle> handles = [];
    private GCHandle self;
    private ulong app;
    private int drainScheduled;

    #endregion

    #region Constructors

    public CoreSession(WebSocket socket) {
        this.socket = socket;
        self = GCHandle.Alloc(this);
    }

    #endregion

    #region Actions - Serving

    /// Answers the interface's requests until it disconnects.
    public async Task Serve(CancellationToken cancellation) {
        var sending = Send(cancellation);
        var buffer = new byte[1 << 16];
        using var message = new MemoryStream();
        while (socket.State == WebSocketState.Open) {
            message.SetLength(0);
            WebSocketReceiveResult result;
            do {
                result = await socket.ReceiveAsync(buffer, cancellation);
                if (result.MessageType == WebSocketMessageType.Close) {
                    outgoing.Writer.TryComplete();
                    await sending;
                    return;
                }
                message.Write(buffer, 0, result.Count);
            } while (!result.EndOfMessage);
            byte[] frame = message.ToArray();
            await gate.WaitAsync(cancellation);
            try {
                Reply(frame);
            } finally {
                gate.Release();
            }
        }
        outgoing.Writer.TryComplete();
        await sending;
    }

    private async Task Send(CancellationToken cancellation) {
        await foreach (var frame in outgoing.Reader.ReadAllAsync(cancellation))
            await socket.SendAsync(frame, WebSocketMessageType.Binary, endOfMessage: true, cancellation);
    }

    private unsafe void Reply(byte[] frame) {
        var op = (Op)frame[0];
        uint id = BinaryPrimitives.ReadUInt32LittleEndian(frame.AsSpan(1));
        var payload = frame.AsSpan(5);
        var (status, bytes) = op switch {
            Op.Create => Create(payload),
            Op.Dispatch => Call(payload, CoreLibrary.crest_app_dispatch),
            Op.Query => Call(payload, CoreLibrary.crest_app_query),
            Op.Drain => Drain(),
            Op.EndTurn => (CoreLibrary.crest_app_end_turn(app), Array.Empty<byte>()),
            Op.RegisterEngine => RegisterEngine(payload),
            Op.Report => Report(payload),
            Op.Ask => Ask(payload),
            _ => (-1, Array.Empty<byte>())
        };
        var response = new byte[9 + bytes.Length];
        response[0] = (byte)((byte)op | 0x80);
        BinaryPrimitives.WriteUInt32LittleEndian(response.AsSpan(1), id);
        BinaryPrimitives.WriteInt32LittleEndian(response.AsSpan(5), status);
        bytes.CopyTo(response, 9);
        outgoing.Writer.TryWrite(response);
    }

    #endregion

    #region Actions - Core

    private unsafe (int, byte[]) Create(ReadOnlySpan<byte> payload) {
        int length = checked((int)BinaryPrimitives.ReadUInt32LittleEndian(payload));
        var fingerprint = payload.Slice(4, length);
        var configuration = payload[(4 + length)..];
        CoreLibrary.Buffer rejection = default;
        int status;
        ulong created;
        fixed (byte* print = fingerprint)
        fixed (byte* settings = configuration)
            status = CoreLibrary.crest_app_create(print, (nuint)fingerprint.Length, settings, (nuint)configuration.Length,
                out created, &rejection);
        if (status != CoreLibrary.Ok) return (status, CoreLibrary.Take(ref rejection));
        app = created;
        CoreLibrary.crest_app_set_wake(app, &Wake, GCHandle.ToIntPtr(self));
        var handle = new byte[8];
        BinaryPrimitives.WriteUInt64LittleEndian(handle, app);
        return (status, handle);
    }

    private unsafe delegate int CoreCall(ulong app, byte* message, nuint length, CoreLibrary.Buffer* output);

    private unsafe (int, byte[]) Call(ReadOnlySpan<byte> message, CoreCall call) {
        CoreLibrary.Buffer output = default;
        int status;
        fixed (byte* bytes = message) status = call(app, bytes, (nuint)message.Length, &output);
        return (status, CoreLibrary.Take(ref output));
    }

    private unsafe (int, byte[]) Drain() {
        CoreLibrary.Buffer output = default;
        int status = CoreLibrary.crest_app_drain(app, &output);
        return (status, CoreLibrary.Take(ref output));
    }

    /// A wake from a core thread: drains on the host's turn and pushes the batch.
    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    private unsafe static void Wake(nint context) {
        if (GCHandle.FromIntPtr(context).Target is CoreSession session) session.ScheduleDrain();
    }

    private void ScheduleDrain() {
        if (Interlocked.Exchange(ref drainScheduled, 1) == 1) return;
        _ = Task.Run(async () => {
            await gate.WaitAsync();
            try {
                Interlocked.Exchange(ref drainScheduled, 0);
                if (app == 0) return;
                var (status, changes) = Drain();
                CoreLibrary.crest_app_end_turn(app);
                var frame = new byte[5 + changes.Length];
                frame[0] = ChangesPush;
                BinaryPrimitives.WriteInt32LittleEndian(frame.AsSpan(1), status);
                changes.CopyTo(frame, 5);
                outgoing.Writer.TryWrite(frame);
            } finally {
                gate.Release();
            }
        });
    }

    #endregion

    #region Actions - Engines

    private unsafe (int, byte[]) RegisterEngine(ReadOnlySpan<byte> payload) {
        int length = checked((int)BinaryPrimitives.ReadUInt32LittleEndian(payload));
        var fingerprint = payload.Slice(4, length);
        var registration = payload[(4 + length)..];
        var slot = new EngineSlot(this);
        var handle = GCHandle.Alloc(slot);
        handles.Add(handle);
        var binding = new CoreLibrary.EngineBinding { Context = GCHandle.ToIntPtr(handle), Attach = &Attach, Run = &Run };
        CoreLibrary.Buffer rejection = default;
        int status;
        ulong engine;
        fixed (byte* print = fingerprint)
        fixed (byte* bytes = registration)
            status = CoreLibrary.crest_engine_register(app, print, (nuint)fingerprint.Length, bytes, (nuint)registration.Length,
                &binding, out engine, &rejection);
        if (status != CoreLibrary.Ok) return (status, CoreLibrary.Take(ref rejection));
        slot.Engine = engine;
        var answer = new byte[8];
        BinaryPrimitives.WriteUInt64LittleEndian(answer, engine);
        return (status, answer);
    }

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    private unsafe static void Attach(nint context, ulong app, ulong engine, nint report, nint ask) {
        if (GCHandle.FromIntPtr(context).Target is EngineSlot slot) slot.Engine = engine;
    }

    /// A command the core issued to the interface's engine, delivered as it was issued.
    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    private unsafe static void Run(nint context, byte* command, nuint length) {
        if (GCHandle.FromIntPtr(context).Target is not EngineSlot slot) return;
        var frame = new byte[9 + (int)length];
        frame[0] = CommandPush;
        BinaryPrimitives.WriteUInt64LittleEndian(frame.AsSpan(1), slot.Engine);
        new ReadOnlySpan<byte>(command, (int)length).CopyTo(frame.AsSpan(9));
        slot.Session.outgoing.Writer.TryWrite(frame);
    }

    private unsafe (int, byte[]) Report(ReadOnlySpan<byte> payload) {
        ulong engine = BinaryPrimitives.ReadUInt64LittleEndian(payload);
        var report = payload[8..];
        int status;
        fixed (byte* bytes = report) status = CoreLibrary.crest_engine_report(app, engine, bytes, (nuint)report.Length);
        return (status, []);
    }

    private unsafe (int, byte[]) Ask(ReadOnlySpan<byte> payload) {
        ulong engine = BinaryPrimitives.ReadUInt64LittleEndian(payload);
        var question = payload[8..];
        var answer = new StrongBox<byte[]>([]);
        var handle = GCHandle.Alloc(answer);
        try {
            int status;
            fixed (byte* bytes = question)
                status = CoreLibrary.crest_engine_ask(app, engine, bytes, (nuint)question.Length, &Answered, GCHandle.ToIntPtr(handle));
            return (status, answer.Value!);
        } finally {
            handle.Free();
        }
    }

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    private unsafe static void Answered(nint context, byte* answer, nuint length) {
        if (GCHandle.FromIntPtr(context).Target is StrongBox<byte[]> box) box.Value = new ReadOnlySpan<byte>(answer, (int)length).ToArray();
    }

    #endregion

    #region Mutators

    private unsafe void DestroyApp() {
        if (app == 0) return;
        CoreLibrary.crest_app_set_wake(app, null, 0);
        CoreLibrary.crest_app_destroy(app);
        app = 0;
    }

    public async ValueTask DisposeAsync() {
        await gate.WaitAsync();
        try {
            DestroyApp();
        } finally {
            gate.Release();
        }
        foreach (var handle in handles) handle.Free();
        if (self.IsAllocated) self.Free();
    }

    #endregion
}
