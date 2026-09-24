using CrestCore.Contracts;

namespace CrestCore.Application;

public sealed partial class NativeSessionAuthority {
    #region Actions - Commands

    /// Accepts a prepared command, saved behind, publishes what it changed and
    /// queues its stage. Throws `Rejected` with `StaleCommand` when the session
    /// accepted anything after the command was prepared.
    internal void CommitCommand(NativeSessionCommand command) {
        SessionState previous;
        lock (Gate) {
            RequireWritable(requireCurrentBorrowedPolicy: false);
            command.RequireAccepted(session);
            if (command.TransientCompletion is { } completed) completedTransients.Add(completed);
            previous = Accept(command.Session);
        }
        Published(previous, command.Session, command.FollowUp, command.Events);
        QueueStage(previous, command.Session, command.Staging);
    }

    #endregion
}
