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
        var window = request["window"]!;
        var selection = window["selectedTabs"]!.AsArray().ToDictionary(n => Id(n!["spaceID"]), n => n!["tabID"]);
        var compact = original.Metadata.DeepClone().AsObject();
        compact["selectedTabID"] = selection.GetValueOrDefault(spaceId)?.DeepClone();
        foreach (var section in Sections)
            compact[section] = new JsonArray(section is "history" or "archivedTabs" ? [] :
                original.Sections[section].Select(n => n.DeepClone()).ToArray());
        var editorRequest = new JsonObject {
            ["version"] = 1,
            ["operation"] = request["operation"]!.DeepClone(),
            ["arguments"] = request["arguments"]!.DeepClone(),
            ["now"] = request["now"]!.DeepClone(),
            ["space"] = compact,
        };
        var output = NativeSessionEditor.Evaluate(System.Text.Encoding.UTF8.GetBytes(editorRequest.ToJsonString()));
        if (output.Length > NativeSessionEditor.MaximumBytes) throw new BrowserRuleException(BrowserRuleCodes.SessionEditLimit);
        var result = JsonNode.Parse(output)!;
        var edited = result["space"]!;
        var nextSpaces = document.Spaces.Select(space => {
            var fields = space.Metadata.DeepClone().AsObject();
            fields["selectedTabID"] = selection.GetValueOrDefault(Id(fields["id"]))?.DeepClone();
            if (Id(fields["id"]) != spaceId) return new SpaceDocument(fields, space.Sections);
            fields["selectedTabID"] = edited["selectedTabID"]?.DeepClone();
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
        var metadata = document.Metadata.DeepClone().AsObject();
        metadata["selectedSpaceID"] = (result["selectSpace"]!.GetValue<bool>()
            ? original.Metadata["id"] : window["selectedSpaceID"])!.DeepClone();
        var next = new SessionDocument(metadata, nextSpaces);
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
