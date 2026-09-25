using CrestCore.Contracts;

namespace CrestCore.Application;

public sealed partial class CrestApp {
    #region Variables

    /// The engine bindings pages open on.
    private readonly Engines engines = new();

    /// Commands issued and not yet delivered, oldest first.
    private readonly Queue<(Engine Engine, EngineCommand Command)> undelivered = [];
    private readonly Lock deliveryGate = new();

    /// A call is handing commands to bindings. Any other call, on this thread
    /// inside a binding or on another, only adds to the queue.
    private bool delivering;

    #endregion

    #region Actions - Engines

    /// Registers an engine binding. The core hands it commands through `run`,
    /// in the order it issued them, never while it holds a lock. Throws
    /// `Rejected` when the engine lacks a required capability, is already
    /// registered, or asks to be the default beside another default.
    /// The commands this device offers follow the default engine, so the
    /// bindings are published again when they change.
    public Engine RegisterEngine(EngineRegistration registration, Action<EngineCommand> run) {
        Engine engine;
        lock (gate) {
            var offered = engines.OfferedCommands();
            engine = engines.Register(registration, run);
            AnnounceOffered(offered);
        }
        WakeIfOwed();
        return engine;
    }

    /// Removes a binding. Commands still waiting for it are dropped.
    public void UnregisterEngine(Engine engine) {
        lock (gate) {
            var offered = engines.OfferedCommands();
            engines.Unregister(engine);
            AnnounceOffered(offered);
        }
        WakeIfOwed();
    }

    /// Announces the bindings when the commands this device offers are no
    /// longer `before`. The caller holds the lock.
    private void AnnounceOffered(IReadOnlyList<ShortcutCommand> before) {
        if (device.ShortcutsAfter(before, engines.OfferedCommands()) is { } changed) Announce(changed);
    }

    /// Applies what an engine saw happen to one of its pages. A report is
    /// never refused; one about a page the core no longer knows changes
    /// nothing. What it changed arrives through the next drain, and commands
    /// it caused are delivered after it, never on its stack when it arrives
    /// inside a delivery.
    public void Report(Engine engine, EngineEvent report) {
        ArgumentNullException.ThrowIfNull(engine);
        ArgumentNullException.ThrowIfNull(report);
        var changes = new ChangeFeed();
        lock (gate) pages.Report(engine, report, changes);
        foreach (var change in changes.Published) Announce(change);
        WakeIfOwed();
        WakeForRequestedTurn();
        Deliver();
    }

    #endregion

    #region Actions - Delivery

    /// Queues a command for delivery once the core lets go of its lock.
    private void Issue(Engine engine, EngineCommand command) {
        lock (deliveryGate) undelivered.Enqueue((engine, command));
    }

    /// Hands every queued command to its binding, oldest first, unless a
    /// delivery is already under way: that one delivers what was added. A
    /// binding that sends an intent or a report while it runs a command adds to
    /// the queue, and the queue is never entered twice.
    private void Deliver() {
        lock (deliveryGate) {
            if (delivering) return;
            delivering = true;
        }
        while (true) {
            (Engine Engine, EngineCommand Command) next;
            lock (deliveryGate) {
                if (!undelivered.TryDequeue(out next)) {
                    delivering = false;
                    return;
                }
            }
            try {
                next.Engine.Run(next.Command);
            } catch {
                lock (deliveryGate) delivering = false;
                throw;
            }
        }
    }

    #endregion
}
