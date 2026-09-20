using System.Text.Json.Nodes;
using CrestCore.Domain;

namespace CrestCore.Application;

public sealed partial class NativeSessionAuthority
{
    /// Prepares against owned records. The native caller decodes the resulting
    /// projection before committing, so a failed read cannot leave its UI behind.
    public NativeSessionCommand PrepareCommand(ulong expected, ReadOnlySpan<byte> bytes)
    {
        lock (Gate)
        {
            if (expected != Revision) throw new BrowserRuleException("stale_session_revision");
            if (bytes.Length > NativeSessionEditor.MaximumBytes) throw new BrowserRuleException("session_edit_limit");
            var request = Parse(bytes);
            if (request["version"]!.GetValue<int>() != 1) throw new BrowserRuleException("version_mismatch");
            if (request["operation"]!.GetValue<string>().StartsWith("space.", StringComparison.Ordinal))
                return PrepareSpaceCommand(expected, request);
            var spaceId = Id(request["spaceId"]);
            var original = document.Spaces.Single(s => Id(s.Metadata["id"]) == spaceId);
            if (Id(request["profileId"]) != Id(original.Metadata["profile"]!["id"]))
                throw new BrowserRuleException("wrong_profile_identity");
            var window = request["window"]!;
            var selection = window["selectedTabs"]!.AsArray().ToDictionary(n => Id(n!["spaceID"]), n => n!["tabID"]);
            var compact = original.Metadata.DeepClone().AsObject();
            compact["selectedTabID"] = selection.GetValueOrDefault(spaceId)?.DeepClone();
            foreach (var section in Sections)
                compact[section] = new JsonArray(section is "history" or "archivedTabs" ? [] :
                    original.Sections[section].Select(n => n.DeepClone()).ToArray());
            var editorRequest = new JsonObject
            {
                ["version"] = 1, ["operation"] = request["operation"]!.DeepClone(),
                ["arguments"] = request["arguments"]!.DeepClone(), ["now"] = request["now"]!.DeepClone(),
                ["space"] = compact,
            };
            var output = NativeSessionEditor.Evaluate(System.Text.Encoding.UTF8.GetBytes(editorRequest.ToJsonString()));
            if (output.Length > NativeSessionEditor.MaximumBytes) throw new BrowserRuleException("session_edit_limit");
            var result = JsonNode.Parse(output)!;
            var edited = result["space"]!;
            var nextSpaces = document.Spaces.Select(space =>
            {
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
                    sections["archivedTabs"] = space.Sections["archivedTabs"].Concat(
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
    }

    internal ulong CommitCommand(NativeSessionCommand command)
    {
        lock (Gate)
        {
            RequireWritable();
            if (command.ExpectedRevision != Revision) throw new BrowserRuleException("stale_session_revision");
            var nextRevision = checked(Revision + 1);
            document = command.Document;
            Revision = nextRevision;
            return Revision;
        }
    }
}

public sealed class NativeSessionCommand
{
    private readonly NativeSessionAuthority owner;
    internal ulong ExpectedRevision { get; }
    internal NativeSessionAuthority.SessionDocument Document { get; }
    public byte[] Output { get; }
    internal NativeSessionCommand(NativeSessionAuthority owner, ulong revision,
        NativeSessionAuthority.SessionDocument document, byte[] output)
    { this.owner = owner; ExpectedRevision = revision; Document = document; Output = output; }
    public ulong Commit() => owner.CommitCommand(this);
}
