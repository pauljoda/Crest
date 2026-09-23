using System.Text;
using System.Text.Json.Nodes;

using CrestCore.Domain;

namespace CrestCore.Application;

public sealed partial class NativeSessionAuthority {
    #region Actions - Workspace

    private NativeSessionCommand PrepareWorkspaceCommand(ulong expected, JsonObject request) {
        if (workspaceKind != BrowserWorkspaceKind.Persistent) throw new BrowserRuleException(BrowserRuleCodes.PersistentWorkspaceRequired);
        var source = document.Metadata.DeepClone().AsObject();
        source["spaces"] = new JsonArray(document.Spaces.Select(space => {
            var value = space.Metadata.DeepClone().AsObject();
            foreach (var section in Sections) value[section] = new JsonArray(space.Sections[section].Select(n => n.DeepClone()).ToArray());
            return (JsonNode)value;
        }).ToArray());
        var result = NativeWorkspaceImport.Preview(source, request["arguments"]!.AsObject(),
            request["mode"]!.GetValue<string>(), request["now"]!.GetValue<double>());
        var output = Encoding.UTF8.GetBytes(result.ToJsonString());
        if (output.Length > MaximumBytes) throw new BrowserRuleException(BrowserRuleCodes.SessionSizeLimit);
        if (result["error"] is { } error) return new(this, expected, document, output, error.GetValue<string>());
        var session = result["session"]!.AsObject();
        var next = new SessionDocument(Fields(session, ["spaces", LegacySelectionFields.SelectedSpace]), session["spaces"]!.AsArray().Select(node =>
            new SpaceDocument(SpaceFields(node!.AsObject()), Sections.ToDictionary(section => section,
                section => (IReadOnlyList<JsonNode>)node[section]!.AsArray().Select(n => n!.DeepClone()).ToArray()))).ToArray());
        Validate(next);
        return new(this, expected, next, output);
    }

    #endregion
}
