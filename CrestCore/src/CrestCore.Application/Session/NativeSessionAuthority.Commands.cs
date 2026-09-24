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
        if (SessionOperationCodes.IsPreferences(operation)) return PreparePreferencesCommand(request, operation);
        if (length > MaximumEditBytes) throw new BrowserRuleException(BrowserRuleCodes.SessionEditLimit);
        if (operation == SessionOperation.TabsBatch) return PrepareTabBatch(request);
        if (SessionOperationCodes.IsRecord(operation))
            return PrepareRecordCommand(request);
        if (SessionOperationCodes.IsTransient(operation))
            return PrepareTransientCommand(request);
        if (operation == SessionOperation.TabTransfer) return PrepareTabTransfer(request);
        if (SessionOperationCodes.IsSpace(operation))
            return PrepareSpaceCommand(request);
        if (operation is SessionOperation.TabPromoteTransient or SessionOperation.TabArchiveTransient)
            throw new BrowserRuleException(BrowserRuleCodes.TransientRequiresCommand);
        var (next, answer, followUp, events) = EditSpace(request, operation);
        return new NativeSessionCommand(this, session, next, Output(answer), followUp: followUp, events: events);
    }

    /// One tab, folder or split edit in the Space the request names: the next
    /// session, the answer for the requesting window, what that window shows
    /// next and what the edit did that the sessions cannot tell. A tab the
    /// window shows that the edit dismisses gives way to the tab it showed
    /// before, from its history.
    private (SessionState Next, JsonObject Answer, WindowFollowUp FollowUp, SessionTabEvents Events) EditSpace(JsonObject request,
        SessionOperation operation) {
        var spaceId = Id(request["spaceId"]);
        if (PendingDeletion(session, spaceId) is not null)
            throw new BrowserRuleException(BrowserRuleCodes.SpaceDeletionInProgress);
        var original = session.Spaces.Single(s => s.Id == spaceId);
        if (Id(request["profileId"]) != original.ProfileId)
            throw new BrowserRuleException(BrowserRuleCodes.WrongProfileIdentity);
        var followUp = new WindowFollowUp(IssuingWindow(request));
        var arguments = SessionEditArguments.Decode(request["arguments"]!.AsObject(), operation);
        arguments = arguments with { FallbackTabId = DismissalFallback(operation, original, arguments, followUp) };
        var result = NativeSessionEditor.Evaluate(operation, original, arguments, Now(request), followUp.Window?.Tab(spaceId));
        followUp.ShowTab(spaceId, result.SelectedTabId);
        if (result.SelectSpace) followUp.ShowSpace(spaceId);
        var edited = result.Edited.Capture(original);
        var next = Replacing(session, edited);
        Validate(next);
        return (next, result.Answer(edited), followUp, result.Events);
    }

    /// The window that issued `request`, as it is now, or null for a command
    /// issued without one.
    private Window? IssuingWindow(JsonObject request) {
        var windowId = request[WindowField] is { } value ? Id(value) : (Guid?)null;
        return device?.Snapshot(workspaceId, windowId);
    }

    /// The tab to show after a close or deletion dismisses the tab the window
    /// shows: the one it showed before. A durable close skips the tab's split,
    /// whose other members would present the closed card again.
    private static Guid? DismissalFallback(SessionOperation operation, SpaceState space, SessionEditArguments arguments,
        WindowFollowUp followUp) {
        if (operation is not (SessionOperation.TabClose or SessionOperation.TabDelete or SessionOperation.TabCloseDurable)
            || arguments.TabId is not { } dismissed) return null;
        var group = space.Tabs.FirstOrDefault(tab => tab.Id == dismissed)?.SplitGroupId;
        var available = space.Tabs.Where(tab => operation != SessionOperation.TabCloseDurable
            || tab.Id != dismissed && (group is null || tab.SplitGroupId != group)).Select(tab => tab.Id).ToHashSet();
        return followUp.FallbackAfterDismissing(space.Id, dismissed, available);
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
