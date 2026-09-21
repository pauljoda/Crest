using System.Text;
using System.Text.Json.Nodes;
using CrestCore.Domain;

namespace CrestCore.Application;

public sealed partial class NativeSessionAuthority {
    private NativeSessionCommand PrepareWorkspaceCommand(ulong expected, JsonObject request) {
        if (workspaceKind != BrowserWorkspaceKind.Persistent) throw new BrowserRuleException("persistent_workspace_required");
        var source = document.Metadata.DeepClone().AsObject();
        var window = request["window"]!;
        var selection = window["selectedTabs"]!.AsArray().ToDictionary(n => Id(n!["spaceID"]), n => n!["tabID"]);
        source["selectedSpaceID"] = window["selectedSpaceID"]!.DeepClone();
        source["spaces"] = new JsonArray(document.Spaces.Select(space => {
            var value = space.Metadata.DeepClone().AsObject();
            value["selectedTabID"] = selection.GetValueOrDefault(Id(value["id"]))?.DeepClone();
            foreach (var section in Sections) value[section] = new JsonArray(space.Sections[section].Select(n => n.DeepClone()).ToArray());
            return (JsonNode)value;
        }).ToArray());
        var result = NativeWorkspaceImport.Preview(source, request["arguments"]!.AsObject(),
            request["mode"]!.GetValue<string>(), request["now"]!.GetValue<double>());
        var output = Encoding.UTF8.GetBytes(result.ToJsonString());
        if (output.Length > MaximumBytes) throw new BrowserRuleException("session_size_limit");
        if (result["error"] is { } error) return new(this, expected, document, output, error.GetValue<string>());
        var session = result["session"]!.AsObject();
        var next = new SessionDocument(Fields(session, ["spaces"]), session["spaces"]!.AsArray().Select(node =>
            new SpaceDocument(Fields(node!.AsObject(), Sections), Sections.ToDictionary(section => section,
                section => (IReadOnlyList<JsonNode>)node[section]!.AsArray().Select(n => n!.DeepClone()).ToArray()))).ToArray());
        Validate(next);
        return new(this, expected, next, output);
    }
}
