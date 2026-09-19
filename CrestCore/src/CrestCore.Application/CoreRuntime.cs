using System.Diagnostics;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json.Nodes;
using CrestCore.Contracts;

namespace CrestCore.Application;

public static class CoreStatus
{
    public const int Ok = 0, Empty = 1, BufferTooSmall = 2, Timeout = 3, Stopped = 4, Busy = 5,
        InvalidArgument = -1, VersionMismatch = -2, InvalidState = -3, InvalidHandle = -4,
        InvalidMessage = -5, InternalError = -6, LimitExceeded = -7;
}

public sealed class CoreRuntime(CoreOptions options)
{
    private enum Phase { Configuring, Running, Quiescing, Stopped }
    private readonly object gate = new();
    private readonly List<Adapter> adapters = [];
    private readonly Queue<(Envelope Message, int Size)> inbox = [];
    private readonly Queue<byte[]> outbox = [];
    private readonly Dictionary<string, ulong> sequences = [];
    private readonly Dictionary<Guid, byte[]> accepted = [];
    private readonly Queue<Guid> acceptedOrder = [];
    private Phase phase;
    private int inputBytes, outputBytes;
    private ulong outputSequence;
    private Guid? shutdownEffect;
    private bool shutdownAcknowledged;
    private Task? executor;
    public CoreOptions Options { get; } = options;

    public int Register(byte[] bytes)
    {
        Adapter adapter;
        try { adapter = Protocol.Descriptor(bytes); } catch { return CoreStatus.InvalidMessage; }
        lock (gate)
        {
            if (phase != Phase.Configuring) return CoreStatus.InvalidState;
            if (adapters.Count >= 16 || adapters.Any(a => a.Id == adapter.Id || a.Role == adapter.Role)) return CoreStatus.InvalidArgument;
            adapters.Add(adapter); return CoreStatus.Ok;
        }
    }
    public int Start()
    {
        lock (gate)
        {
            if (phase != Phase.Configuring) return CoreStatus.InvalidState;
            if (new[] { "ui", "engine", "platform" }.Any(role => adapters.Count(a => a.Role == role) != 1)) return CoreStatus.InvalidState;
            BrowserSessionKernel kernel;
            try { kernel = new(adapters, initialState: Options.InitialState, persistSession: Options.PersistSession); }
            catch { return CoreStatus.InvalidState; }
            phase = Phase.Running;
            executor = Task.Run(() => Run(kernel)); return CoreStatus.Ok;
        }
    }
    public int Post(byte[] bytes)
    {
        if (bytes.Length > Options.MessageByteLimit) return CoreStatus.LimitExceeded;
        Envelope message;
        try { message = Protocol.Decode(bytes); } catch { return CoreStatus.InvalidMessage; }
        byte[] hash = SHA256.HashData(bytes);
        lock (gate)
        {
            if (phase is Phase.Configuring or Phase.Stopped) return CoreStatus.InvalidState;
            if (message.SessionId != Options.SessionId || message.Recipient != "core"
                || !Protocol.Incoming.TryGetValue(message.Type, out var role)
                || !adapters.Any(a => a.Id == message.Sender && a.Role == role)
                || message.Kind != (role == "ui" ? "command" : "observation")) return CoreStatus.InvalidMessage;
            if (accepted.TryGetValue(message.Id, out var prior))
                return hash.SequenceEqual(prior) ? CoreStatus.Ok : CoreStatus.InvalidMessage;
            if (phase == Phase.Quiescing && message.Kind == "command") return CoreStatus.InvalidState;
            ulong last = sequences.GetValueOrDefault(message.Sender);
            if (last == ulong.MaxValue || message.Sequence != last + 1) return CoreStatus.InvalidMessage;
            if (bytes.Length + inputBytes > Options.QueueByteLimit) return CoreStatus.Busy;
            accepted.Add(message.Id, hash); acceptedOrder.Enqueue(message.Id);
            if (acceptedOrder.Count > 4096) accepted.Remove(acceptedOrder.Dequeue());
            sequences[message.Sender] = message.Sequence;
            inbox.Enqueue((message, bytes.Length)); inputBytes += bytes.Length;
            Monitor.PulseAll(gate); return CoreStatus.Ok;
        }
    }
    private void Run(BrowserSessionKernel kernel)
    {
        try
        {
            while (true)
            {
                Envelope? message = null;
                bool beginShutdown = false;
                lock (gate)
                {
                    while (inbox.Count == 0 && !(phase == Phase.Quiescing
                        && ((shutdownEffect is null && kernel.PendingEffectCount == 0) || shutdownAcknowledged))) Monitor.Wait(gate);
                    if (phase == Phase.Quiescing && kernel.SaveFailed && kernel.PendingEffectCount == 0)
                    {
                        phase = Phase.Running; kernel.CancelShutdown();
                        Publish(new(adapters.Single(a => a.Role == "ui").Id, "result", "core.shutdown_blocked",
                            new() { ["code"] = "persistence_failed" }, Guid.NewGuid(), Guid.NewGuid(), null));
                        continue;
                    }
                    if (phase == Phase.Quiescing) kernel.BeginShutdown();
                    if (inbox.TryDequeue(out var item)) { message = item.Message; inputBytes -= item.Size; }
                    else if (shutdownAcknowledged) break;
                    else { shutdownEffect = Guid.NewGuid(); beginShutdown = true; }
                }
                if (beginShutdown)
                {
                    kernel.BeginShutdown();
                    Publish(new(adapters.Single(a => a.Role == "engine").Id, "effect", "engine.dispose_all", new(),
                        shutdownEffect!.Value, shutdownEffect.Value, null));
                    continue;
                }
                if (message!.Type == "engine.stopped")
                {
                    lock (gate)
                    {
                        if (shutdownEffect is not null && message.CausationId == shutdownEffect && message.CorrelationId == shutdownEffect)
                            shutdownAcknowledged = true;
                        else Publish(new(adapters.Single(a => a.Role == "ui").Id, "result", "core.operation_failed",
                            new() { ["code"] = "unexpected_shutdown_ack" }, Guid.NewGuid(), message.CorrelationId, message.Id));
                    }
                    continue;
                }
                foreach (var item in kernel.Process(message)) Publish(item);
            }
        }
        catch
        {
            // An executor failure terminates the session; it cannot continue with partially published state.
            // Do not include URLs, message bodies, or exception text in diagnostics.
            Publish(new(adapters.Single(a => a.Role == "ui").Id, "result", "core.operation_failed",
                new() { ["code"] = "session_failed" }, Guid.NewGuid(), Guid.NewGuid(), null));
        }
        finally { lock (gate) { phase = Phase.Stopped; Monitor.PulseAll(gate); } }
    }
    private void Publish(Outgoing item)
    {
        var bytes = Protocol.Encode(Options.SessionId, item.Id, item.CorrelationId, item.CausationId,
            item.Recipient, checked(outputSequence + 1), item.Kind, item.Type, item.Payload);
        if (item.Type is "services.save_session" or "ui.snapshot" or "ui.records" && bytes.Length > Options.MessageByteLimit
            && Options.MessageByteLimit >= 4096)
        {
            bool storage = item.Type == "services.save_session";
            var prefix = storage ? "services.session" : item.Type;
            var identityKey = storage ? "saveId" : item.Type == "ui.records" ? "recordsId" : "snapshotId";
            var state = Encoding.UTF8.GetBytes((storage ? item.Payload["state"]! : item.Payload).ToJsonString());
            var revision = item.Payload[item.Type == "ui.records" ? "queryId" : "revision"]!.GetValue<string>();
            int chunkSize = Math.Min(65536, (Options.MessageByteLimit - 1024) * 3 / 4);
            int count = (state.Length + chunkSize - 1) / chunkSize;
            Publish(item with { Type = prefix + "_begin", Payload = new()
            {
                ["revision"] = revision, ["byteCount"] = state.Length, ["chunkCount"] = count,
                ["sha256"] = Convert.ToHexStringLower(SHA256.HashData(state))
            } });
            for (int index = 0; index < count; index++)
                Publish(item with { Id = Guid.NewGuid(), CausationId = item.Id, Type = prefix + "_chunk", Payload = new()
                {
                    ["revision"] = revision, [identityKey] = item.Id.ToString(), ["index"] = index,
                    ["data"] = Convert.ToBase64String(state.AsSpan(index * chunkSize, Math.Min(chunkSize, state.Length - index * chunkSize)))
                } });
            Publish(item with { Id = Guid.NewGuid(), CausationId = item.Id, Type = prefix + "_commit", Payload = new()
            { ["revision"] = revision, [identityKey] = item.Id.ToString() } });
            return;
        }
        if (bytes.Length > Options.MessageByteLimit) throw new InvalidOperationException("output_limit");
        lock (gate)
        {
            while (bytes.Length + outputBytes > Options.QueueByteLimit) Monitor.Wait(gate);
            outbox.Enqueue(bytes); outputSequence++; outputBytes += bytes.Length; Monitor.PulseAll(gate);
        }
    }
    public int WaitOutput(uint timeout)
    {
        lock (gate)
        {
            if (phase == Phase.Configuring) return CoreStatus.InvalidState;
            if (!WaitUntil(() => outbox.Count > 0 || phase == Phase.Stopped, timeout)) return CoreStatus.Timeout;
            return outbox.Count > 0 ? CoreStatus.Ok : CoreStatus.Stopped;
        }
    }
    private bool WaitUntil(Func<bool> ready, uint timeout)
    {
        long started = Stopwatch.GetTimestamp();
        while (!ready())
        {
            double left = timeout - Stopwatch.GetElapsedTime(started).TotalMilliseconds;
            if (left <= 0) return false;
            Monitor.Wait(gate, TimeSpan.FromMilliseconds(Math.Min(left, int.MaxValue)));
        }
        return true;
    }
    public int Read(Span<byte> destination, out int length)
    {
        lock (gate)
        {
            if (!outbox.TryPeek(out var bytes)) { length = 0; return phase == Phase.Stopped ? CoreStatus.Stopped : CoreStatus.Empty; }
            length = bytes.Length;
            if (destination.Length < length) return CoreStatus.BufferTooSmall;
            bytes.CopyTo(destination); outbox.Dequeue(); outputBytes -= length; Monitor.PulseAll(gate); return CoreStatus.Ok;
        }
    }
    public int BeginShutdown()
    {
        lock (gate)
        {
            if (phase == Phase.Configuring) phase = Phase.Stopped;
            else if (phase == Phase.Running) phase = Phase.Quiescing;
            Monitor.PulseAll(gate); return CoreStatus.Ok;
        }
    }
    public int WaitStopped(uint timeout)
    {
        long started = Stopwatch.GetTimestamp();
        lock (gate) if (!WaitUntil(() => phase == Phase.Stopped, timeout)) return CoreStatus.Timeout;
        int remaining = (int)Math.Clamp(timeout - Stopwatch.GetElapsedTime(started).TotalMilliseconds, 0, int.MaxValue);
        return executor is null || executor.Wait(remaining) ? CoreStatus.Ok : CoreStatus.Timeout;
    }
    public bool CanDestroy
    {
        get { lock (gate) return (phase == Phase.Configuring || (phase == Phase.Stopped && executor?.IsCompleted != false)) && outbox.Count == 0; }
    }
}
