using System.Text;
using System.Text.Json.Nodes;

using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

public sealed partial class NativeSessionAuthority {
    #region Actions - Commands

    /// Prepares against the accepted records, which the command remembers: it
    /// commits only while they are still the accepted ones. The session's
    /// changes are published when it commits.
    public NativeSessionCommand PrepareCommand(ReadOnlySpan<byte> bytes) {
        lock (Gate) {
            RequireWritable();
            var request = Parse(bytes);
            if (request["version"]!.GetValue<int>() != 1) throw new BrowserRuleException(BrowserRuleCodes.VersionMismatch);
            RequireAccessibleCommand(request);
            var operation = SessionOperationCodes.Parse(request["operation"]!.GetValue<string>());
            return PrepareOperation(request, operation, bytes.Length)
                .StagedAs(SessionOperationCodes.Staging(operation, request));
        }
    }

    private NativeSessionCommand PrepareOperation(JsonObject request, SessionOperation operation, int length) {
        if (operation == SessionOperation.WorkspaceImport) return PrepareWorkspaceCommand(request);
        if (length > MaximumEditBytes) throw new BrowserRuleException(BrowserRuleCodes.SessionEditLimit);
        if (operation == SessionOperation.TabsBatch) return PrepareTabBatch(request);
        if (operation == SessionOperation.TabTransfer) return PrepareTabTransfer(request);
        throw new ProtocolException(ProtocolErrorCodes.UnknownSessionEdit);
    }

    /// The window that issued `request`, as it is now, or null for a command
    /// issued without one.
    private Window? IssuingWindow(JsonObject request) {
        var windowId = request[WindowField] is { } value ? Id(value) : (Guid?)null;
        return device?.Snapshot(workspaceId, windowId);
    }

    /// The request's time, in the stored date format.
    private static DateTimeOffset Now(JsonObject request) => StoredSessionCodec.Date(request["now"]!.GetValue<double>());

    /// A command answer, within the size a native read accepts.
    private static byte[] Output(JsonObject answer) {
        var bytes = Encoding.UTF8.GetBytes(answer.ToJsonString());
        if (bytes.Length > MaximumEditBytes) throw new BrowserRuleException(BrowserRuleCodes.SessionEditLimit);
        return bytes;
    }

    /// A command that changes nothing and answers `output`, read and released
    /// with the command API like any other.
    internal NativeSessionCommand Projection(byte[] output) {
        lock (Gate) return new(this, session, session, output);
    }

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
