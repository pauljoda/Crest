using CrestCore.Contracts;

namespace CrestCore.Application;

public sealed partial class CrestApp {
    #region Variables

    /// Changes the core started itself, oldest first, until the host drains them.
    private readonly List<Change> pending = [];
    private readonly Lock pendingGate = new();
    private readonly Lock wakeGate = new();
    private Action? wake;
    private int wakesInFlight;

    #endregion

    #region Actions - Changes

    /// The changes the core started itself since the last drain, oldest first.
    public IReadOnlyList<Change> Drain() {
        lock (pendingGate) {
            var drained = pending.ToArray();
            pending.Clear();
            return drained;
        }
    }

    /// Sets the callback that tells the host a drain has something for it, or
    /// removes it with null. The callback carries nothing, runs on whichever
    /// thread published the change, and is never called while the core holds
    /// a lock. When this returns, no earlier callback is still running.
    public void SetWake(Action? value) {
        lock (wakeGate) wake = value;
        var spinner = new SpinWait();
        while (Volatile.Read(ref wakesInFlight) > 0) spinner.SpinOnce();
    }

    /// Queues a change for the next drain. The host is woken only when the
    /// batch goes from empty to not empty; a drain is already due otherwise.
    /// A newer save replaces an undrained older one.
    private void Announce(Change change) {
        bool wakes;
        lock (pendingGate) {
            if (change is Saved && pending.Count > 0 && pending[^1] is Saved) pending[^1] = change;
            else pending.Add(change);
            wakes = pending.Count == 1;
        }
        if (wakes) Wake();
    }

    private void Wake() {
        Action? target;
        lock (wakeGate) {
            target = wake;
            if (target is null) return;
            Interlocked.Increment(ref wakesInFlight);
        }
        try {
            target();
        } finally {
            Interlocked.Decrement(ref wakesInFlight);
        }
    }

    #endregion
}
