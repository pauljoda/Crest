using System.Text.Json.Nodes;

using CrestCore.Domain;

namespace CrestCore.Application;

public sealed partial class NativeSessionAuthority {
    #region Actions - Commands

    /// Prepares against owned records. The native caller decodes the resulting
    /// projection before committing, so a failed read cannot leave its UI behind.
    public NativeSessionCommand PrepareCommand(ulong expected, ReadOnlySpan<byte> bytes) {
        lock (Gate) {
            RequireWritable();
            if (expected != Revision) throw new BrowserRuleException(BrowserRuleCodes.StaleSessionRevision);
            var request = Parse(bytes);
            if (request["version"]!.GetValue<int>() != 1) throw new BrowserRuleException(BrowserRuleCodes.VersionMismatch);
            RequireAccessibleCommand(request);
            var operation = SessionOperationCodes.Parse(request["operation"]!.GetValue<string>());
            if (operation == SessionOperation.WorkspaceImport) return PrepareWorkspaceCommand(expected, request);
            if (SessionOperationCodes.IsPreferences(operation)) return PreparePreferencesCommand(expected, request, operation);
            if (bytes.Length > NativeSessionEditor.MaximumBytes) throw new BrowserRuleException(BrowserRuleCodes.SessionEditLimit);
            if (operation == SessionOperation.TabsBatch) return PrepareTabBatch(expected, request);
            if (SessionOperationCodes.IsRecord(operation))
                return PrepareRecordCommand(expected, request);
            if (SessionOperationCodes.IsTransient(operation))
                return PrepareTransientCommand(expected, request);
            if (operation == SessionOperation.TabTransfer) return PrepareTabTransfer(expected, request);
            if (SessionOperationCodes.IsSpace(operation))
                return PrepareSpaceCommand(expected, request);
            if (operation is SessionOperation.TabPromoteTransient or SessionOperation.TabArchiveTransient)
                throw new BrowserRuleException(BrowserRuleCodes.TransientRequiresCommand);
            return PrepareTabCommand(expected, request);
        }
    }

    private NativeSessionCommand PrepareTabCommand(ulong expected, JsonObject request) {
        var spaceId = Id(request["spaceId"]);
        if (PendingDeletion(document.Metadata, spaceId) is not null)
            throw new BrowserRuleException(BrowserRuleCodes.SpaceDeletionInProgress);
        var original = document.Spaces.Single(s => Id(s.Metadata["id"]) == spaceId);
        if (Id(request["profileId"]) != Id(original.Metadata["profile"]!["id"]))
            throw new BrowserRuleException(BrowserRuleCodes.WrongProfileIdentity);
        var view = SessionView.Decode(request[SessionView.Key]);
        var compact = original.Metadata.DeepClone().AsObject();
        foreach (var section in Sections)
            compact[section] = new JsonArray(section is "history" or "archivedTabs" ? [] :
                original.Sections[section].Select(n => n.DeepClone()).ToArray());
        var operation = SessionOperationCodes.Parse(request["operation"]!.GetValue<string>());
        var editorRequest = SessionEditRequest.Create(operation, compact,
            SessionEditArguments.Decode(request["arguments"]!.AsObject(), operation), request["now"]!.GetValue<double>(),
            view.Tab(spaceId));
        var result = SessionEditResult.Decode(NativeSessionEditor.Evaluate(editorRequest.Encode()));
        var hint = new SessionSelectionHint().SelectTab(view, spaceId, result.SelectedTabId);
        if (result.SelectSpace) hint.SelectSpace(spaceId);
        var output = result.Encode(hint);
        if (output.Length > NativeSessionEditor.MaximumBytes) throw new BrowserRuleException(BrowserRuleCodes.SessionEditLimit);
        var edited = result.Space;
        var nextSpaces = document.Spaces.Select(space => {
            if (Id(space.Metadata["id"]) != spaceId) return space;
            var fields = space.Metadata.DeepClone().AsObject();
            fields["splitGroups"] = edited["splitGroups"]?.DeepClone();
            var sections = space.Sections.ToDictionary(pair => pair.Key, pair => pair.Value);
            sections["tabs"] = edited["tabs"]!.AsArray().Select(n => n!.DeepClone()).ToArray();
            sections["folders"] = edited["folders"]!.AsArray().Select(n => n!.DeepClone()).ToArray();
            var archived = edited["archivedTabs"]!.AsArray();
            if (archived.Count > 0)
                sections["archivedTabs"] = space.ArchivedTabs.Concat(
                    archived.Select(n => n!.DeepClone())).ToArray();
            return new SpaceDocument(fields, sections);
        }).ToArray();
        var next = new SessionDocument(document.Metadata, nextSpaces);
        Validate(next);
        return new NativeSessionCommand(this, expected, next, output);
    }

    internal ulong CommitCommand(NativeSessionCommand command) {
        lock (Gate) {
            RequireWritable(requireCurrentBorrowedPolicy: false);
            command.RequireAccepted();
            if (command.ExpectedRevision != Revision) throw new BrowserRuleException(BrowserRuleCodes.StaleSessionRevision);
            var nextRevision = checked(Revision + 1);
            document = command.Document;
            if (command.TransientCompletion is { } completed) completedTransients.Add(completed);
            borrowedSourceRevision = command.BorrowedSourceRevision ?? borrowedSourceRevision;
            Revision = nextRevision;
            return Revision;
        }
    }

    #endregion
}
